// iframe + camera/mic permissions on Flutter web.
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

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
  late final String _viewType;
  late final html.IFrameElement _iframe;
  late final html.EventListener _messageListener;
  late final JitsiRoomController _room;

  @override
  void initState() {
    super.initState();
    _viewType = 'digi-jitsi-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';

    final htmlDoc = buildJitsiHostHtml(
      roomName: jitsiRoomNameFromUrl(widget.meetingUrl),
      displayName: widget.displayName,
      startAudioMuted: widget.startAudioMuted,
      startVideoMuted: widget.startVideoMuted,
    );
    _iframe = html.IFrameElement()
      ..srcdoc = htmlDoc
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'camera; microphone; fullscreen; display-capture; autoplay'
      ..allowFullscreen = true;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _iframe);

    _room = JitsiRoomController();
    _room.toggleAudio = () async {
      _call('toggleAudio');
    };
    _room.toggleVideo = () async {
      _call('toggleVideo');
    };
    _room.switchCamera = () async {
      _call('switchCamera');
    };
    _room.hangup = () async {
      _call('hangup');
    };

    _messageListener = (event) {
      final e = event as html.MessageEvent;
      final data = e.data;
      if (data is Map && data['source'] == 'digi-jitsi') {
        widget.onEvent?.call(data['event']?.toString() ?? '');
      }
    };
    html.window.addEventListener('message', _messageListener);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_room);
    });
  }

  void _call(String cmd) {
    _iframe.contentWindow?.postMessage({'source': 'digi-host', 'cmd': cmd}, '*');
  }

  @override
  void dispose() {
    html.window.removeEventListener('message', _messageListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
