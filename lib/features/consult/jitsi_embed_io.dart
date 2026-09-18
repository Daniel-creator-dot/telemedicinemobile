import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'jitsi_embed_api.dart';
import 'jitsi_html.dart';

/// Native audio routing for Android WebView WebRTC (speaker + voice mode).
const _kCallAudioChannel = MethodChannel('medilynks/call_audio');

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

class _JitsiRoomViewState extends State<JitsiRoomView> with WidgetsBindingObserver {
  late final WebViewController _web;
  late final JitsiRoomController _room;
  bool _ready = false;
  bool _bridgeInjected = false;
  bool _joined = false;
  bool _camGranted = true;
  bool _micGranted = true;
  bool _permPermanentlyDenied = false;
  String? _error;
  String? _softWarning;
  Timer? _joinWatchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final params = _controllerCreationParams();
    _web = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (request) async {
        // Critical: grant CAMERA + RECORD_AUDIO for getUserMedia in WebView.
        await request.grant();
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF071018))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageFinished(),
          onWebResourceError: (err) {
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

    _room = JitsiRoomController();
    _room.toggleAudio = () => _web.runJavaScript('typeof toggleAudio==="function"&&toggleAudio();');
    _room.toggleVideo = () => _web.runJavaScript('typeof toggleVideo==="function"&&toggleVideo();');
    _room.switchCamera = () => _web.runJavaScript('typeof switchCamera==="function"&&switchCamera();');
    _room.hangup = () => _web.runJavaScript('typeof hangup==="function"&&hangup();');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_room);
      _prepareAndLoad();
    });
  }

  PlatformWebViewControllerCreationParams _controllerCreationParams() {
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      return WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    return const PlatformWebViewControllerCreationParams();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _joinWatchdog?.cancel();
    _leaveCallAudio();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionFlags();
      if (_joined) _enterCallAudio();
    }
  }

  void _onBridgeMessage(String message) {
    if (message.startsWith('error:')) {
      _surfaceError(message.substring(6));
      return;
    }
    if (message == 'mediaDenied') {
      if (mounted) {
        setState(() {
          _softWarning =
              'Camera or microphone blocked in the room. Tap Allow media, then unmute in the Jitsi toolbar if needed.';
        });
      }
      widget.onEvent?.call('mediaDenied');
      return;
    }
    if (message == 'bridgeTimeout') {
      widget.onEvent?.call('ready');
      return;
    }
    if (message == 'joined') {
      _joined = true;
      _joinWatchdog?.cancel();
      _enterCallAudio();
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
    await _ensureMediaPermissions(forcePrompt: true);
    await _configurePlatformWebView();
    await _enterCallAudio();
    if (!mounted) return;
    if (!_camGranted || !_micGranted) {
      setState(() {
        _ready = true;
        _softWarning = _permBannerText();
      });
      // Still load so user can open browser / retry after Settings.
    } else {
      setState(() => _ready = true);
    }
    _loadDirectRoom();
    _armJoinWatchdog();
  }

  String _permBannerText() {
    if (_permPermanentlyDenied) {
      return 'Camera/mic permanently denied. Open Settings → Permissions, enable both, then Retry.';
    }
    return 'Camera and microphone are required for video consult. Tap Allow media.';
  }

  Future<void> _ensureMediaPermissions({bool forcePrompt = false}) async {
    if (kIsWeb) {
      _camGranted = true;
      _micGranted = true;
      return;
    }
    try {
      var cam = await Permission.camera.status;
      var mic = await Permission.microphone.status;
      if (forcePrompt || !cam.isGranted || !mic.isGranted) {
        final results = await [
          Permission.camera,
          Permission.microphone,
        ].request();
        cam = results[Permission.camera] ?? cam;
        mic = results[Permission.microphone] ?? mic;
      }
      _camGranted = cam.isGranted;
      _micGranted = mic.isGranted;
      _permPermanentlyDenied = cam.isPermanentlyDenied || mic.isPermanentlyDenied;
      if (mounted) setState(() {});
    } catch (_) {
      // permission_handler can throw on unsupported platforms — proceed.
      _camGranted = true;
      _micGranted = true;
    }
  }

  Future<void> _refreshPermissionFlags() async {
    if (kIsWeb) return;
    try {
      final cam = await Permission.camera.status;
      final mic = await Permission.microphone.status;
      if (!mounted) return;
      setState(() {
        _camGranted = cam.isGranted;
        _micGranted = mic.isGranted;
        _permPermanentlyDenied = cam.isPermanentlyDenied || mic.isPermanentlyDenied;
        if (_camGranted && _micGranted && _softWarning != null && _softWarning!.contains('Camera')) {
          _softWarning = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _configurePlatformWebView() async {
    try {
      final platform = _web.platform;
      if (platform is AndroidWebViewController) {
        await platform.setMediaPlaybackRequiresUserGesture(false);
        await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
        await platform.setGeolocationEnabled(false);
        // Allow third-party cookies so Jitsi session storage works in WebView.
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          await cookies.setAcceptThirdPartyCookies(platform, true);
        }
      } else if (platform is WebKitWebViewController) {
        await platform.setAllowsBackForwardNavigationGestures(false);
      }
    } catch (_) {}
  }

  Future<void> _enterCallAudio() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _kCallAudioChannel.invokeMethod('enterCallAudio');
    } catch (_) {}
  }

  Future<void> _leaveCallAudio() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _kCallAudioChannel.invokeMethod('leaveCallAudio');
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
      // Prime getUserMedia so Chrome WebView permission + tracks are ready
      // before Jitsi conference join (helps Android WebRTC).
      await _web.runJavaScript(jitsiMediaWarmupScript());
      await _web.runJavaScript(jitsiMeetBridgeScript());
    } catch (_) {}
  }

  void _armJoinWatchdog() {
    _joinWatchdog?.cancel();
    _joinWatchdog = Timer(const Duration(seconds: 45), () {
      if (!mounted || _joined || _error != null) return;
      setState(() {
        _softWarning =
            'Taking longer than usual to confirm join. If you see the room, you are connected. '
            'Check the mic/cam icons in the Jitsi bar — they may be muted. Otherwise Retry or Browser.';
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
    await _ensureMediaPermissions(forcePrompt: true);
    await _enterCallAudio();
    if (!mounted) return;
    if (!_camGranted || !_micGranted) {
      setState(() => _softWarning = _permBannerText());
    }
    _loadDirectRoom();
    _armJoinWatchdog();
  }

  Future<void> _requestMediaAgain() async {
    if (_permPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await _ensureMediaPermissions(forcePrompt: true);
    if (!mounted) return;
    if (_camGranted && _micGranted) {
      setState(() => _softWarning = null);
      await _retry();
    } else {
      setState(() => _softWarning = _permBannerText());
    }
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

  /// Texture Layer Hybrid Composition (default) black-screens WebRTC camera.
  /// Hybrid Composition is required for reliable getUserMedia preview on Android.
  Widget _buildWebView() {
    if (!kIsWeb && Platform.isAndroid) {
      final androidCtrl = _web.platform;
      if (androidCtrl is AndroidWebViewController) {
        return WebViewWidget.fromPlatformCreationParams(
          params: AndroidWebViewWidgetCreationParams(
            controller: androidCtrl,
            displayWithHybridComposition: true,
          ),
        );
      }
    }
    return WebViewWidget(controller: _web);
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
        _buildWebView(),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          (!_camGranted || !_micGranted)
                              ? Icons.privacy_tip_outlined
                              : Icons.info_outline,
                          color: const Color(0xFFFBBF24),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _softWarning!,
                            style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (!_camGranted || !_micGranted)
                          TextButton(
                            onPressed: _requestMediaAgain,
                            child: Text(_permPermanentlyDenied ? 'Settings' : 'Allow media'),
                          ),
                        TextButton(onPressed: _retry, child: const Text('Retry')),
                        TextButton(onPressed: _openExternal, child: const Text('Browser')),
                      ],
                    ),
                    _permStatusRow(),
                  ],
                ),
              ),
            ),
          ),
        if (_error == null &&
            _joined &&
            _camGranted &&
            _micGranted &&
            _softWarning == null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: IgnorePointer(
              child: Text(
                'Tip: if peers cannot hear you, tap the mic icon in the video toolbar to unmute.',
                textAlign: TextAlign.center,
                style: GoogleFonts.roboto(color: Colors.white38, fontSize: 10),
              ),
            ),
          ),
        if (_error != null) _errorOverlay(_error!),
      ],
    );
  }

  Widget _permStatusRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            _camGranted ? Icons.videocam : Icons.videocam_off,
            size: 14,
            color: _camGranted ? const Color(0xFF34D399) : const Color(0xFFF87171),
          ),
          const SizedBox(width: 4),
          Text(
            _camGranted ? 'Camera on' : 'Camera blocked',
            style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 12),
          Icon(
            _micGranted ? Icons.mic : Icons.mic_off,
            size: 14,
            color: _micGranted ? const Color(0xFF34D399) : const Color(0xFFF87171),
          ),
          const SizedBox(width: 4),
          Text(
            _micGranted ? 'Mic on' : 'Mic blocked',
            style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
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
