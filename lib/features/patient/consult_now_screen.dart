import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/appointment.dart';
import '../consult/open_video_consult.dart';
import 'care_repository.dart';
import 'chat_screen.dart';
import 'pay_visit.dart';

class ConsultNowScreen extends StatefulWidget {
  const ConsultNowScreen({super.key, this.dependentPatientId});

  final int? dependentPatientId;

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
  bool _paying = false;
  Appointment? _queued;
  String? _error;
  Timer? _queueTimer;

  @override
  void initState() {
    super.initState();
    _checkQueue();
    _queueTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _queued == null) return;
      _checkQueue(silent: true);
    });
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    for (final c in [_complaint, _duration, _symptoms, _meds, _allergies, _conditions, _bp, _temp, _pulse, _spo2]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canEnterVideo {
    final q = _queued;
    if (q == null) return false;
    if (q.paymentStatus == 'paid') return true;
    if ((q.meetingLink ?? '').trim().isNotEmpty) return true;
    if (q.doctorId != null || (q.doctorName ?? '').trim().isNotEmpty) return true;
    final s = q.status.toLowerCase();
    return s == 'approved' || s == 'consulting' || s == 'arrived';
  }

  Future<void> _payQueued() async {
    final q = _queued;
    if (q == null) return;
    setState(() => _paying = true);
    final result = await payVisitWithPaystack(context, appointmentId: q.id);
    if (!mounted) return;
    setState(() => _paying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      setState(() => _queued = q.copyWith(paymentStatus: 'paid'));
      _checkQueue();
    }
  }

  Future<void> _checkQueue({bool silent = false}) async {
    try {
      final q = await context.read<CareRepository>().getQueue();
      if (!mounted) return;
      if (q.isEmpty) {
        if (!silent && _queued != null) {
          setState(() => _queued = null);
        }
        return;
      }
      setState(() => _queued = q.first);
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
        if (widget.dependentPatientId != null) 'dependent_patient_id': widget.dependentPatientId,
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
        actions: [
          if (_queued != null)
            IconButton(
              tooltip: 'Refresh queue',
              onPressed: () => _checkQueue(),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _queued != null ? _queueCard() : _form(),
    );
  }

  Widget _queueCard() {
    final q = _queued!;
    final waitingForDoctor = q.doctorName == null || q.doctorName!.trim().isEmpty;
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
          Text(
            waitingForDoctor
                ? 'Assigned clinician: waiting for nurse / ops match…'
                : 'Assigned clinician: ${q.doctorName}',
          ),
          const SizedBox(height: 8),
          Text(
            'Live updates every few seconds.',
            style: GoogleFonts.roboto(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Text(
            q.paymentStatus == 'paid'
                ? 'Copay received. A nurse will review your triage. You will be notified when a doctor is ready.'
                : _canEnterVideo
                    ? 'A clinician is ready. You can enter the video room (pay later if needed).'
                    : 'Pay the visit copay (MoMo/card when Paystack is live, or confirm demo payment if keys are not set).',
          ),
          const SizedBox(height: 24),
          if (q.paymentStatus != 'paid')
            ElevatedButton.icon(
              onPressed: _paying ? null : _payQueued,
              icon: const Icon(Icons.payment_rounded),
              label: Text(_paying ? 'Confirming payment…' : 'Pay visit copay'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2C4),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          if (q.paymentStatus == 'paid') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Text(
                'Payment confirmed for this visit.',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w600, color: const Color(0xFF065F46)),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_canEnterVideo) ...[
            if (q.paymentStatus != 'paid') const SizedBox(height: 10),
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
          ],
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
        Text(
          widget.dependentPatientId != null
              ? 'This live queue visit is for a dependent on your account.'
              : 'This information is sent to the nurse and assigned doctor before you join.',
        ),
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
        const SizedBox(height: 12),
        TextField(
          controller: _complaint,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Main complaint *', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(controller: _duration, decoration: const InputDecoration(labelText: 'How long?', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _symptoms, decoration: const InputDecoration(labelText: 'Symptoms', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _meds, decoration: const InputDecoration(labelText: 'Current medications', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _allergies, decoration: const InputDecoration(labelText: 'Allergies', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _conditions, decoration: const InputDecoration(labelText: 'Chronic conditions', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: _bp, decoration: const InputDecoration(labelText: 'BP', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _temp, decoration: const InputDecoration(labelText: 'Temp', border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: _pulse, decoration: const InputDecoration(labelText: 'Pulse', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _spo2, decoration: const InputDecoration(labelText: 'SpO2', border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D2C4),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(_submitting ? 'Joining queue…' : 'Join live queue'),
        ),
      ],
    );
  }
}
