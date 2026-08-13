import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/appointment.dart';
import '../consult/open_video_consult.dart';
import 'care_repository.dart';
import 'chat_screen.dart';

class ConsultNowScreen extends StatefulWidget {
  const ConsultNowScreen({super.key});

  @override
  State<ConsultNowScreen> createState() => _ConsultNowScreenState();
}

class _ConsultNowScreenState extends State<ConsultNowScreen> {
  final _complaint = TextEditingController();
  final _duration = TextEditingController();
  final _symptoms = TextEditingController();
  final _meds = TextEditingController();
  final _allergies = TextEditingController();
  final _conditions = TextEditingController();
  final _bp = TextEditingController();
  final _temp = TextEditingController();
  final _pulse = TextEditingController();
  final _spo2 = TextEditingController();
  String _consultType = 'general consultation';
  bool _submitting = false;
  Appointment? _queued;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkQueue();
  }

  @override
  void dispose() {
    for (final c in [_complaint, _duration, _symptoms, _meds, _allergies, _conditions, _bp, _temp, _pulse, _spo2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkQueue() async {
    try {
      final q = await context.read<CareRepository>().getQueue();
      if (q.isNotEmpty) setState(() => _queued = q.first);
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_complaint.text.trim().isEmpty) {
      setState(() => _error = 'Describe your main complaint.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final apt = await context.read<CareRepository>().consultNow({
        'consult_type': _consultType,
        'reason': _complaint.text.trim(),
        'complaint': _complaint.text.trim(),
        'duration': _duration.text.trim(),
        'symptoms': _symptoms.text.trim(),
        'medications': _meds.text.trim(),
        'allergies': _allergies.text.trim(),
        'conditions': _conditions.text.trim(),
        'vitals_bp': _bp.text.trim(),
        'vitals_temp': _temp.text.trim(),
        'vitals_pulse': _pulse.text.trim(),
        'vitals_spo2': _spo2.text.trim(),
      });
      setState(() => _queued = apt);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Consult Now', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: _queued != null ? _queueCard() : _form(),
    );
  }

  Widget _queueCard() {
    final q = _queued!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You are in the live queue', style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Queue number #${q.queueNumber ?? '-'}', style: GoogleFonts.roboto(fontSize: 18, color: const Color(0xFF8B5CF6))),
          const SizedBox(height: 8),
          Text('Estimated wait: ${q.etaMinutes ?? 12} minutes'),
          Text('Status: ${q.status}'),
          if (q.doctorName != null) Text('Assigned clinician: ${q.doctorName}'),
          const SizedBox(height: 16),
          const Text('A nurse will review your triage. You will be notified when a doctor is ready.'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => openVideoConsult(context, q),
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Enter video consultation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2C4),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ClinicalChatScreen(appointment: q),
              ));
            },
            child: const Text('Open clinical chat'),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Pre-consultation triage', style: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('This information is sent to the nurse and assigned doctor before you join.'),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _consultType,
          items: const [
            'general consultation',
            'specialist consultation',
            'follow-up',
            'prescription review',
            'chronic disease review',
            'second medical opinion',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _consultType = v ?? _consultType),
          decoration: const InputDecoration(labelText: 'Consultation type', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        _field(_complaint, 'Main complaint'),
        _field(_duration, 'How long has this lasted?'),
        _field(_symptoms, 'Symptoms', maxLines: 2),
        _field(_meds, 'Current medications'),
        _field(_allergies, 'Known allergies'),
        _field(_conditions, 'Existing conditions'),
        Row(children: [
          Expanded(child: _field(_bp, 'BP')),
          const SizedBox(width: 8),
          Expanded(child: _field(_temp, 'Temp')),
        ]),
        Row(children: [
          Expanded(child: _field(_pulse, 'Pulse')),
          const SizedBox(width: 8),
          Expanded(child: _field(_spo2, 'SpO2')),
        ]),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(_submitting ? 'Joining queue…' : 'Join live queue'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
