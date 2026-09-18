import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  bool _fellBack = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _room = JitsiRoomController();
    _web = WebViewController(
      onPermissionRequest: (request) {
        request.grant();
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF071018))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => widget.onEvent?.call('loaded'),
          onWebResourceError: (_) => _fallbackToDirectJitsi(),
        ),
      )
      ..addJavaScriptChannel(
        'DigiJitsi',
        onMessageReceived: (msg) => widget.onEvent?.call(msg.message),
      );
    _room.toggleAudio = () => _web.runJavaScript('toggleAudio();');
    _room.toggleVideo = () => _web.runJavaScript('toggleVideo();');
    _room.switchCamera = () => _web.runJavaScript('switchCamera();');
    _room.hangup = () => _web.runJavaScript('hangup();');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_room);
      _prepareAndLoad();
    });
  }

  Future<void> _prepareAndLoad() async {
    // Android WebView getUserMedia requires the app to hold runtime grants.
    if (!kIsWeb) {
      try {
        await [
          Permission.camera,
          Permission.microphone,
        ].request();
      } catch (_) {}
    }
    if (!mounted) return;
    _loadEmbed();
    setState(() => _ready = true);
  }

  void _loadEmbed() {
    final normalized = normalizeJitsiMeetingUrl(widget.meetingUrl);
    final domain = digiJitsiDomainFromUrl(normalized);
    final html = buildJitsiHostHtml(
      roomName: jitsiRoomNameFromUrl(normalized),
      displayName: widget.displayName,
      domain: domain,
      startAudioMuted: widget.startAudioMuted,
      startVideoMuted: widget.startVideoMuted,
    );
    _web.loadHtmlString(html, baseUrl: 'https://$domain/');
  }

  void _fallbackToDirectJitsi() {
    if (_fellBack) return;
    _fellBack = true;
    _web.loadRequest(
      Uri.parse(
        jitsiDirectJoinUrl(
          meetingUrl: widget.meetingUrl,
          displayName: widget.displayName,
          startAudioMuted: widget.startAudioMuted,
          startVideoMuted: widget.startVideoMuted,
        ),
      ),
    );
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
    return WebViewWidget(controller: _web);
  }
}
