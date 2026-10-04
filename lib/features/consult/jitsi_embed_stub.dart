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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(JitsiRoomController());
      widget.onEvent?.call('ready');
    });
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(normalizeJitsiMeetingUrl(widget.meetingUrl));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF071018),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_rounded, color: Color(0xFF00D2C4), size: 42),
            const SizedBox(height: 12),
            Text(
              'Video room ready',
              style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openExternal,
              child: const Text('Open Jitsi in browser'),
            ),
          ],
        ),
      ),
    );
  }
}
