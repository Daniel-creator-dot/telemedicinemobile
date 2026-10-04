// iframe + camera/mic permissions on Flutter web.
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final String _joinUrl;
  late final String _domain;
  late final bool _frameBlocked;
  bool _openedExternal = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'digi-jitsi-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';

    final normalized = normalizeJitsiMeetingUrl(widget.meetingUrl);
    _domain = digiJitsiDomainFromUrl(normalized);
    _frameBlocked = jitsiHostBlocksIframeEmbed(_domain);
    _joinUrl = jitsiDirectJoinUrl(
      meetingUrl: widget.meetingUrl,
      displayName: widget.displayName,
      startAudioMuted: widget.startAudioMuted,
      startVideoMuted: widget.startVideoMuted,
    );

    _iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'camera *; microphone *; fullscreen *; display-capture *; autoplay *'
      ..setAttribute(
        'allow',
        'camera *; microphone *; fullscreen *; display-capture *; autoplay *',
      )
      ..allowFullscreen = true;

    if (_frameBlocked) {
      // meet.ffmuc.net (and similar) set CSP frame-ancestors / XFO — iframe is blank.
      // Use External API only when framing is allowed; otherwise open the room URL.
      _iframe.srcdoc = '''
<!DOCTYPE html><html><body style="margin:0;background:#071018;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100%;">
<p style="opacity:.7">Opening secure video room…</p>
</body></html>''';
    } else {
      final htmlDoc = buildJitsiHostHtml(
        roomName: jitsiRoomNameFromUrl(normalized),
        displayName: widget.displayName,
        domain: _domain,
        startAudioMuted: widget.startAudioMuted,
        startVideoMuted: widget.startVideoMuted,
      );
      _iframe.srcdoc = htmlDoc;
    }

    try {
      html.window.navigator.mediaDevices?.getUserMedia({'audio': true, 'video': true}).then((stream) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
      });
    } catch (_) {}

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
      if (_frameBlocked) {
        widget.onEvent?.call('ready');
        _openExternal(auto: true);
      }
    });
  }

  void _call(String cmd) {
    _iframe.contentWindow?.postMessage({'source': 'digi-host', 'cmd': cmd}, '*');
  }

  Future<void> _openExternal({bool auto = false}) async {
    if (auto && _openedExternal) return;
    _openedExternal = true;
    final uri = Uri.tryParse(_joinUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {
      try {
        html.window.open(_joinUrl, '_blank');
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    html.window.removeEventListener('message', _messageListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frameBlocked) {
      return ColoredBox(
        color: const Color(0xFF071018),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_rounded, color: Color(0xFF00D2C4), size: 42),
                  const SizedBox(height: 14),
                  Text(
                    'Video opens in a browser tab',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This Jitsi host blocks in-page embeds (frame policy). '
                    'Use the browser tab for camera and mic, then return here for chat and SOAP.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.roboto(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => _openExternal(),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open video room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D2C4),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}
