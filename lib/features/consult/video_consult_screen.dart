import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/appointment.dart';
import '../../models/chat_message.dart';
import '../../models/role.dart';
import '../doctor/consultation_dialog.dart';
import '../doctor/prescription_dialog.dart';
import '../patient/appointments_repository.dart';
import '../patient/care_repository.dart';
import 'jitsi_embed.dart';
import 'jitsi_embed_api.dart';
import 'jitsi_html.dart';

const _teal = Color(0xFF00D2C4);
const _bg = Color(0xFF071018);
const _panel = Color(0xFF0F1C2E);

class VideoConsultScreen extends StatefulWidget {
  const VideoConsultScreen({
    super.key,
    required this.appointment,
    this.isClinician = false,
  });

  final Appointment appointment;
  final bool isClinician;

  @override
  State<VideoConsultScreen> createState() => _VideoConsultScreenState();
}

class _VideoConsultScreenState extends State<VideoConsultScreen> {
  late Appointment _apt;
  JitsiRoomController? _jitsi;
  Timer? _poll;
  Timer? _clock;

  bool _micOn = true;
  bool _camOn = true;
  bool _showChat = false;
  bool _showSoap = false;
  bool _inCall = false;
  bool _remoteJoined = false;
  bool _completing = false;
  String _connection = 'Waiting';
  Duration _elapsed = Duration.zero;
  DateTime? _callStartedAt;

  final _chatInput = TextEditingController();
  final _soapComplaint = TextEditingController();
  final _soapDx = TextEditingController();
  final _soapNotes = TextEditingController();
  final _soapPlan = TextEditingController();
  List<ChatMessage> _messages = [];
  dynamic _consultation;

  @override
  void initState() {
    super.initState();
    _apt = widget.appointment;
    _soapComplaint.text = _apt.complaint ?? '';
    _bootstrap();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshAppointment());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _chatInput.dispose();
    _soapComplaint.dispose();
    _soapDx.dispose();
    _soapNotes.dispose();
    _soapPlan.dispose();
    super.dispose();
  }

  bool get _isClinician {
    if (widget.isClinician) return true;
    final role = context.read<Session>().user?.role;
    return role == AppRole.doctor || role == AppRole.nurse || role == AppRole.medicalOps;
  }

  String get _peerName {
    if (_isClinician) return _apt.fullName;
    return _apt.doctorName ?? 'Clinician';
  }

  String get _selfName {
    final user = context.read<Session>().user;
    if (user?.name.isNotEmpty == true) return user!.name;
    return _isClinician ? 'Doctor' : 'Patient';
  }

  String get _patientIdLabel {
    return _apt.appointmentId.isNotEmpty
        ? _apt.appointmentId
        : (_apt.nationwideId ?? 'PT-${_apt.id}');
  }

  String get _consultType {
    return _apt.consultType ?? _apt.service ?? (_apt.isConsultNow ? 'Consult Now' : 'Telemedicine');
  }

  Future<void> _bootstrap() async {
    await _refreshAppointment();
    if (!mounted) return;
    if (_isClinician) {
      await _ensureMeetingLink();
      await _markConsulting();
    }
    await _loadChat();
    if (_isClinician) await _loadSoap();
    if (mounted) _maybeEnterCall();
  }

  Future<void> _refreshAppointment() async {
    try {
      final latest = await context.read<AppointmentsRepository>().getAppointmentById(_apt.id);
      if (latest == null || !mounted) return;
      setState(() {
        _apt = latest.copyWith(
          meetingLink: latest.hasMeetingLink ? latest.meetingLink : _apt.meetingLink,
          doctorName: latest.doctorName ?? _apt.doctorName,
        );
      });
      _maybeEnterCall();
      if (_showChat) await _loadChat();
    } catch (_) {}
  }

  Future<void> _ensureMeetingLink() async {
    if (_apt.hasMeetingLink) {
      final normalized = normalizeJitsiMeetingUrl(_apt.meetingLink!);
      if (normalized != _apt.meetingLink) {
        setState(() => _apt = _apt.copyWith(meetingLink: normalized));
        // Persist rewritten host so patient + doctor share one room URL.
        try {
          await context.read<AppointmentsRepository>().generateMeetingLink(_apt.id);
        } catch (_) {}
      }
      return;
    }
    try {
      final updated = await context.read<AppointmentsRepository>().generateMeetingLink(_apt.id);
      if (mounted) {
        setState(() => _apt = updated.copyWith(
          meetingLink: normalizeJitsiMeetingUrl(updated.meetingLink ?? ''),
          doctorName: updated.doctorName ?? _apt.doctorName,
        ));
      }
    } catch (_) {}
  }

  Future<void> _markConsulting() async {
    final s = _apt.status.toLowerCase();
    if (s == 'completed' || s == 'cancelled') return;
    if (s == 'consulting') return;
    try {
      await context.read<AppointmentsRepository>().updateAppointmentStatus(_apt.id, 'consulting');
      if (mounted) setState(() => _apt = _apt.copyWith(status: 'consulting'));
    } catch (_) {}
  }

  void _maybeEnterCall() {
    final hasLink = _apt.hasMeetingLink;
    if (!hasLink) return;
    if (_inCall) return;
    // Patients wait until approved/arrived/consulting (or live consult_now after approval).
    final ready = _isClinician || _apt.isLiveConsult || !_apt.isWaitingInQueue;
    if (!ready) return;
    setState(() {
      _inCall = true;
      _connection = 'Connecting';
    });
  }

  void _startTimer() {
    _callStartedAt ??= DateTime.now();
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _callStartedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_callStartedAt!));
    });
  }

  void _onJitsiEvent(String event) {
    if (!mounted) return;
    // Digi chrome used to mark "In room" on iframe ready — that lied while
    // Jitsi was still stuck on the moderator/lobby gate.
    if (event.startsWith('error:')) {
      setState(() => _connection = 'Error');
      final detail = event.substring(6).trim();
      if (detail.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video: $detail'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(label: 'Browser', onPressed: _openExternal),
          ),
        );
      }
      return;
    }
    if (event == 'ready' || event == 'loaded' || event == 'bridgeTimeout') {
      setState(() => _connection = 'Connecting');
      return;
    }
    if (event == 'slowJoin') {
      setState(() => _connection = 'Connecting…');
      return;
    }
    if (event == 'joined') {
      setState(() => _connection = _remoteJoined ? 'Connected' : 'In room');
      _startTimer();
      return;
    }
    if (event == 'participantJoined') {
      setState(() {
        _remoteJoined = true;
        _connection = 'Connected';
      });
      _startTimer();
      return;
    }
    if (event == 'participantLeft') {
      setState(() {
        _remoteJoined = false;
        _connection = 'Waiting';
      });
      return;
    }
    if (event == 'left' && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadChat() async {
    try {
      final care = context.read<CareRepository>();
      final list = await care.getChat(_apt.id);
      await care.markChatRead(_apt.id);
      if (mounted) setState(() => _messages = list);
    } catch (_) {}
  }

  Future<void> _sendChat() async {
    final text = _chatInput.text.trim();
    if (text.isEmpty) return;
    _chatInput.clear();
    try {
      final care = context.read<CareRepository>();
      await care.sendChat(_apt.id, text);
      await care.markChatRead(_apt.id);
      await _loadChat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chat failed: $e')));
      }
    }
  }

  Future<void> _loadSoap() async {
    try {
      final api = context.read<ApiClient>();
      final res = await api.dio.get<List<dynamic>>('/api/consultations/${_apt.id}');
      final data = res.data;
      if (data != null && data.isNotEmpty) {
        _consultation = data.first;
        _soapComplaint.text = _consultation['chief_complaint']?.toString() ?? _soapComplaint.text;
        _soapDx.text = _consultation['diagnosis']?.toString() ?? '';
        _soapNotes.text = _consultation['clinical_notes']?.toString() ?? '';
        _soapPlan.text = _consultation['treatment_plan']?.toString() ?? '';
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _saveSoap({String status = 'in_progress'}) async {
    try {
      final api = context.read<ApiClient>();
      final payload = {
        'appointment_id': _apt.id,
        'patient_id': _apt.patientId ?? 0,
        'chief_complaint': _soapComplaint.text.trim(),
        'diagnosis': _soapDx.text.trim(),
        'working_diagnosis': _soapDx.text.trim(),
        'clinical_notes': _soapNotes.text.trim(),
        'treatment_plan': _soapPlan.text.trim(),
        'status': status,
      };
      if (_consultation != null) {
        final res = await api.dio.put<Map<String, dynamic>>(
          '/api/consultations/${_consultation['id']}',
          data: payload,
        );
        _consultation = res.data;
      } else {
        final res = await api.dio.post<Map<String, dynamic>>('/api/consultations', data: payload);
        _consultation = res.data;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'completed' ? 'Consult completed' : 'SOAP draft saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SOAP save failed: $e')));
      }
    }
  }

  Future<void> _endCall({bool complete = false}) async {
    if (_completing) return;
    if (complete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _panel,
          title: Text('Complete consult?', style: GoogleFonts.roboto(color: Colors.white)),
          content: Text(
            'End the video call and mark this consultation as completed.',
            style: GoogleFonts.roboto(color: Colors.white70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
              child: const Text('Complete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
      setState(() => _completing = true);
      await _saveSoap(status: 'completed');
      if (!mounted) return;
      try {
        await context.read<AppointmentsRepository>().updateAppointmentStatus(_apt.id, 'completed');
      } catch (_) {}
    }
    try {
      await _jitsi?.hangup?.call();
    } catch (_) {}
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _openExternal() async {
    if (!_apt.hasMeetingLink) return;
    final uri = Uri.tryParse(normalizeJitsiMeetingUrl(_apt.meetingLink!));
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _fmtTimer() {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = _elapsed.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _stage()),
                  if (_showChat && wide) _chatPanel(width: 340),
                  if (_showSoap && _isClinician && wide) _soapPanel(width: 360),
                ],
              ),
            ),
            if (_showChat && !wide) SizedBox(height: 240, child: _chatPanel()),
            if (_showSoap && _isClinician && !wide) SizedBox(height: 280, child: _soapPanel()),
            _callBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1624),
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _endCall(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
            tooltip: 'Leave',
          ),
          CircleAvatar(
            radius: 16,
            backgroundColor: _teal.withOpacity(0.2),
            child: Text(
              _peerName.isNotEmpty ? _peerName[0].toUpperCase() : 'C',
              style: GoogleFonts.roboto(color: _teal, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Text(
                  '$_consultType  ·  Patient ID $_patientIdLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          _statusChip(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _fmtTimer(),
              style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6),
            ),
          ),
          IconButton(
            tooltip: 'Open in browser',
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    final live = _connection == 'Connected' || _connection == 'In room';
    final color = _connection == 'Error'
        ? const Color(0xFFF87171)
        : live
            ? _teal
            : const Color(0xFFFBBF24);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _connection,
            style: GoogleFonts.roboto(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _stage() {
    return Stack(
      children: [
        Positioned.fill(
          child: _inCall && _apt.hasMeetingLink
              ? JitsiRoomView(
                  meetingUrl: normalizeJitsiMeetingUrl(_apt.meetingLink!),
                  displayName: _selfName,
                  startAudioMuted: !_micOn,
                  startVideoMuted: !_camOn,
                  onControllerReady: (c) => _jitsi = c,
                  onEvent: _onJitsiEvent,
                )
              : _waitingRoom(),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _localPip(),
        ),
      ],
    );
  }

  Widget _waitingRoom() {
    return Container(
      color: _bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _teal.withOpacity(0.5), width: 3),
                    color: _teal.withOpacity(0.08),
                  ),
                  child: const Icon(Icons.hourglass_top_rounded, color: _teal, size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  _isClinician ? 'Preparing the consult room' : 'Waiting room',
                  style: GoogleFonts.roboto(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _isClinician
                      ? '$_peerName will appear here when they join.'
                      : 'A clinician will join shortly. Stay on this screen.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(color: Colors.white70, height: 1.4),
                ),
                if (_apt.isConsultNow) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111C2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Queue #${_apt.queueNumber ?? '—'}',
                          style: GoogleFonts.roboto(color: _teal, fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Estimated wait ${_apt.etaMinutes ?? 12} min',
                          style: GoogleFonts.roboto(color: Colors.white70),
                        ),
                        Text(
                          'Status: ${_apt.status}',
                          style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (_apt.hasMeetingLink)
                  ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _inCall = true;
                      _connection = 'Connecting';
                    }),
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('Enter video room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _localPip() {
    return Container(
      width: 118,
      height: 158,
      decoration: BoxDecoration(
        color: const Color(0xFF122033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _camOn ? _teal.withOpacity(0.7) : Colors.white24, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_camOn)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF134E4A), Color(0xFF0F172A)],
                ),
              ),
              child: const Icon(Icons.videocam_rounded, color: Colors.white54, size: 32),
            )
          else
            ColoredBox(
              color: const Color(0xFF0B1220),
              child: Icon(Icons.videocam_off_rounded, color: Colors.white.withOpacity(0.35), size: 32),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              'You${_micOn ? '' : ' · muted'}',
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _callBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1624),
        border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          _roundAction(
            icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: _micOn ? 'Mute' : 'Unmute',
            active: !_micOn,
            danger: !_micOn,
            onTap: () {
              setState(() => _micOn = !_micOn);
              _jitsi?.toggleAudio?.call();
            },
          ),
          _roundAction(
            icon: _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: _camOn ? 'Camera' : 'Cam off',
            active: !_camOn,
            onTap: () {
              setState(() => _camOn = !_camOn);
              _jitsi?.toggleVideo?.call();
            },
          ),
          _roundAction(
            icon: Icons.cameraswitch_rounded,
            label: 'Flip',
            onTap: () => _jitsi?.switchCamera?.call(),
          ),
          _roundAction(
            icon: Icons.chat_bubble_rounded,
            label: 'Chat',
            active: _showChat,
            onTap: () => setState(() => _showChat = !_showChat),
          ),
          if (_isClinician)
            _roundAction(
              icon: Icons.assignment_rounded,
              label: 'SOAP',
              active: _showSoap,
              onTap: () => setState(() => _showSoap = !_showSoap),
            ),
          if (_isClinician)
            _roundAction(
              icon: Icons.medication_rounded,
              label: 'e-Rx',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => PrescriptionDialog(appointment: _apt),
                );
              },
            ),
          _roundAction(
            icon: Icons.call_end_rounded,
            label: 'End',
            danger: true,
            onTap: () => _endCall(),
          ),
          if (_isClinician)
            _roundAction(
              icon: Icons.check_circle_rounded,
              label: 'Complete',
              active: true,
              onTap: () => _endCall(complete: true),
            ),
        ],
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
  }) {
    final bg = danger
        ? const Color(0xFFEF4444)
        : active
            ? _teal
            : const Color(0xFF1E293B);
    final fg = danger || active ? (danger ? Colors.white : Colors.black) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: fg, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: GoogleFonts.roboto(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _chatPanel({double? width}) {
    final me = context.watch<Session>().user?.id;
    return Container(
      width: width,
      color: _panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Text('Consult chat', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _showChat = false),
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final mine = m.senderId.toString() == me;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFF155E75) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.senderName, style: GoogleFonts.roboto(fontSize: 10, color: Colors.white54)),
                        Text(m.body, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInput,
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Message the consult…',
                      hintStyle: GoogleFonts.roboto(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                IconButton(onPressed: _sendChat, icon: const Icon(Icons.send_rounded, color: _teal)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _soapPanel({double? width}) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.roboto(color: Colors.white54, fontSize: 12),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        );
    return Container(
      width: width,
      color: _panel,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              Text('SOAP notes', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _showSoap = false),
                icon: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
          TextField(
            controller: _soapComplaint,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 2,
            decoration: deco('Subjective / complaint'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _soapDx,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: deco('Assessment / diagnosis'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _soapNotes,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 3,
            decoration: deco('Objective / notes'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _soapPlan,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 2,
            decoration: deco('Plan'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _saveSoap(),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            child: const Text('Save draft'),
          ),
          TextButton(
            onPressed: () {
              showDialog(context: context, builder: (_) => ConsultationDialog(appointment: _apt));
            },
            child: const Text('Open full workspace'),
          ),
          TextButton(
            onPressed: _openExternal,
            child: const Text('Open Jitsi in browser'),
          ),
        ],
      ),
    );
  }
}
