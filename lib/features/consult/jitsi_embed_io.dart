import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'jitsi_embed_api.dart';
import 'jitsi_html.dart';

class JitsiRoomView extends StatefulWidget {
  const JitsiRoomView({
    super.key,
    required this.meetingUrl,
    required this.displayName,
    this.startAudioMuted = false,
    this.startVideoMuted = false,
    this.onControllerReady,
    this.onEvent,
  });

  final String meetingUrl;
  final String displayName;
  final bool startAudioMuted;
  final bool startVideoMuted;
  final ValueChanged<JitsiRoomController>? onControllerReady;
  final JitsiEventCallback? onEvent;

  @override
  State<JitsiRoomView> createState() => _JitsiRoomViewState();
}

class _JitsiRoomViewState extends State<JitsiRoomView> {
  late final WebViewController _web;
  late final JitsiRoomController _room;
  bool _ready = false;
  bool _bridgeInjected = false;
  bool _joined = false;
  String? _error;
  String? _softWarning;
  Timer? _joinWatchdog;

  @override
  void initState() {
    super.initState();
    _room = JitsiRoomController();
    _web = WebViewController(
      onPermissionRequest: (request) async {
        // Critical for getUserMedia inside Android WebView.
        await request.grant();
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF071018))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageFinished(),
          onWebResourceError: (err) {
            // Ignore subresource noise (favicons, analytics); surface main-frame failures.
            if (err.isForMainFrame == true) {
              _surfaceError(err.description.isNotEmpty ? err.description : 'Page failed to load');
            }
          },
          onHttpError: (err) {
            if ((err.response?.statusCode ?? 0) >= 400) {
              _surfaceError('HTTP ${err.response?.statusCode} loading video room');
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'DigiJitsi',
        onMessageReceived: (msg) => _onBridgeMessage(msg.message),
      );
    _room.toggleAudio = () => _web.runJavaScript('typeof toggleAudio==="function"&&toggleAudio();');
    _room.toggleVideo = () => _web.runJavaScript('typeof toggleVideo==="function"&&toggleVideo();');
    _room.switchCamera = () => _web.runJavaScript('typeof switchCamera==="function"&&switchCamera();');
    _room.hangup = () => _web.runJavaScript('typeof hangup==="function"&&hangup();');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_room);
      _prepareAndLoad();
    });
  }

  @override
  void dispose() {
    _joinWatchdog?.cancel();
    super.dispose();
  }

  void _onBridgeMessage(String message) {
    if (message.startsWith('error:')) {
      _surfaceError(message.substring(6));
      return;
    }
    if (message == 'bridgeTimeout') {
      // Bridge hook timed out — room UI may still work; keep waiting for join.
      widget.onEvent?.call('ready');
      return;
    }
    if (message == 'joined') {
      _joined = true;
      _joinWatchdog?.cancel();
      if (mounted) {
        setState(() {
          _error = null;
          _softWarning = null;
        });
      }
    }
    widget.onEvent?.call(message);
  }

  Future<void> _prepareAndLoad() async {
    if (!kIsWeb) {
      try {
        await [
          Permission.camera,
          Permission.microphone,
        ].request();
      } catch (_) {}
    }
    await _configurePlatformWebView();
    if (!mounted) return;
    _loadDirectRoom();
    setState(() => _ready = true);
    _armJoinWatchdog();
  }

  Future<void> _configurePlatformWebView() async {
    try {
      final platform = _web.platform;
      if (platform is AndroidWebViewController) {
        await platform.setMediaPlaybackRequiresUserGesture(false);
        // Allow third-party cookies so Jitsi session storage works in WebView.
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          await cookies.setAcceptThirdPartyCookies(platform, true);
        }
      }
    } catch (_) {}
  }

  void _loadDirectRoom() {
    _bridgeInjected = false;
    final url = jitsiDirectJoinUrl(
      meetingUrl: widget.meetingUrl,
      displayName: widget.displayName,
      startAudioMuted: widget.startAudioMuted,
      startVideoMuted: widget.startVideoMuted,
    );
    _web.loadRequest(Uri.parse(url));
  }

  Future<void> _onPageFinished() async {
    widget.onEvent?.call('loaded');
    if (_bridgeInjected) return;
    _bridgeInjected = true;
    try {
      await _web.runJavaScript(jitsiMeetBridgeScript());
    } catch (_) {}
  }

  void _armJoinWatchdog() {
    _joinWatchdog?.cancel();
    _joinWatchdog = Timer(const Duration(seconds: 45), () {
      if (!mounted || _joined || _error != null) return;
      // Soft banner only — do not cover a possibly-working WebView.
      setState(() {
        _softWarning =
            'Taking longer than usual to confirm join. If you see the room, you are connected. '
            'Otherwise try Retry or Open in browser.';
      });
      widget.onEvent?.call('slowJoin');
    });
  }

  void _surfaceError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    widget.onEvent?.call('error:$message');
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _softWarning = null;
      _joined = false;
    });
    _loadDirectRoom();
    _armJoinWatchdog();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(
      jitsiDirectJoinUrl(
        meetingUrl: widget.meetingUrl,
        displayName: widget.displayName,
        startAudioMuted: widget.startAudioMuted,
        startVideoMuted: widget.startVideoMuted,
      ),
    );
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF071018),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF00D2C4)),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _web),
        if (_softWarning != null && _error == null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: const Color(0xEE1E293B),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFBBF24), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _softWarning!,
                        style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12, height: 1.3),
                      ),
                    ),
                    TextButton(onPressed: _retry, child: const Text('Retry')),
                    TextButton(onPressed: _openExternal, child: const Text('Browser')),
                  ],
                ),
              ),
            ),
          ),
        if (_error != null) _errorOverlay(_error!),
      ],
    );
  }

  Widget _errorOverlay(String message) {
    return ColoredBox(
      color: const Color(0xEE071018),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded, color: Color(0xFFF87171), size: 40),
                const SizedBox(height: 14),
                Text(
                  'Video room error',
                  style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(color: Colors.white70, height: 1.4, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D2C4),
                        foregroundColor: Colors.black,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openExternal,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open in browser'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
