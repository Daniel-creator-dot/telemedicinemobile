import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/appointment.dart';
import '../../models/doctor_profile.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';
import '../patient/chat_screen.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  List<Map<String, dynamic>> _triage = [];
  List<DoctorProfile> _doctors = [];
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final care = context.read<CareRepository>();
      final list = await care.getTriage();
      List<DoctorProfile> docs = _doctors;
      try {
        docs = await care.getDirectory();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _triage = list;
        _doctors = docs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _readInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> _setUrgency(Map<String, dynamic> row, String urgency) async {
    final id = _readInt(row['id']);
    if (id == null) return;
    try {
      await context.read<CareRepository>().updateTriage(id, {
        'urgency': urgency,
        'status': 'reviewed',
      });
      final aptId = _readInt(row['appointment_pk'] ?? row['appointment_id']);
      if (aptId != null) {
        await context.read<CareRepository>().assignQueue(aptId, {
          'urgency': urgency == 'emergency' || urgency == 'urgent' ? 'High' : 'Medium',
        });
      }
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update urgency: $e')));
    }
  }

  Future<void> _openReview(Map<String, dynamic> row) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TriageReviewSheet(
        row: row,
        doctors: _doctors,
      ),
    );
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: RoleChrome(
        title: 'Triage',
        subtitle: session.user?.name ?? 'Nurse',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/nurse/programs'),
        backgroundColor: digiForest,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.favorite_outline),
        label: const Text('Care programs'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _triage.isEmpty
              ? const ClinicalEmptyState(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Triage queue is clear',
                  message: 'New Consult Now patients will appear here for vitals, urgency and handover to a doctor.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _triage.length,
                    itemBuilder: (_, i) {
                      final t = _triage[i];
                      final urgency = t['urgency']?.toString() ?? 'routine';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      t['full_name']?.toString() ?? 'Patient',
                                      style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Text('#${t['queue_number'] ?? '-'}', style: const TextStyle(color: Color(0xFF8B5CF6))),
                                ],
                              ),
                              Text(t['complaint']?.toString() ?? 'No complaint recorded'),
                              Text('Symptoms: ${t['symptoms'] ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              Text('Allergies: ${t['allergies'] ?? '-'} · Meds: ${t['medications'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                              Text(
                                'Vitals: BP ${t['vitals_bp'] ?? '-'} · Temp ${t['vitals_temp'] ?? '-'} · '
                                'Pulse ${t['vitals_pulse'] ?? '-'} · SpO₂ ${t['vitals_spo2'] ?? '-'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (t['doctor_name'] != null)
                                Text('Doctor: ${t['doctor_name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _chip('routine', urgency, t),
                                  _chip('urgent', urgency, t),
                                  _chip('emergency', urgency, t),
                                  TextButton.icon(
                                    onPressed: () => _openReview(t),
                                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                                    label: const Text('Review & assign'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      final apt = Appointment.fromJson({
                                        'id': t['appointment_pk'] ?? t['appointment_id'],
                                        'appointment_id': t['apt_code']?.toString() ?? '',
                                        'full_name': t['full_name'],
                                        'phone_number': '',
                                        'preferred_date': '',
                                        'preferred_time': '',
                                        'status': t['appointment_status'] ?? 'queued',
                                        'is_telemedicine': true,
                                        'payment_status': 'unpaid',
                                        'doctor_name': t['doctor_name'],
                                      });
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => ClinicalChatScreen(appointment: apt),
                                      ));
                                    },
                                    child: const Text('Chat'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _chip(String value, String current, Map<String, dynamic> row) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(value),
      selected: selected,
      onSelected: (_) => _setUrgency(row, value),
    );
  }
}

class _TriageReviewSheet extends StatefulWidget {
  const _TriageReviewSheet({required this.row, required this.doctors});

  final Map<String, dynamic> row;
  final List<DoctorProfile> doctors;

  @override
  State<_TriageReviewSheet> createState() => _TriageReviewSheetState();
}

class _TriageReviewSheetState extends State<_TriageReviewSheet> {
  late final TextEditingController _notes;
  late final TextEditingController _bp;
  late final TextEditingController _temp;
  late final TextEditingController _pulse;
  late final TextEditingController _spo2;
  late String _urgency;
  int? _doctorId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.row;
    _notes = TextEditingController(text: t['notes']?.toString() ?? '');
    _bp = TextEditingController(text: t['vitals_bp']?.toString() ?? '');
    _temp = TextEditingController(text: t['vitals_temp']?.toString() ?? '');
    _pulse = TextEditingController(text: t['vitals_pulse']?.toString() ?? '');
    _spo2 = TextEditingController(text: t['vitals_spo2']?.toString() ?? '');
    _urgency = t['urgency']?.toString() ?? 'routine';
    final online = widget.doctors.where((d) => d.isOnline).toList();
    if (online.isNotEmpty) {
      _doctorId = online.first.id;
    } else if (widget.doctors.isNotEmpty) {
      _doctorId = widget.doctors.first.id;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _bp.dispose();
    _temp.dispose();
    _pulse.dispose();
    _spo2.dispose();
    super.dispose();
  }

  int? _readInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> _save() async {
    final triageId = _readInt(widget.row['id']);
    final aptId = _readInt(widget.row['appointment_pk'] ?? widget.row['appointment_id']);
    if (triageId == null || aptId == null) return;
    setState(() => _saving = true);
    try {
      final care = context.read<CareRepository>();
      await care.updateTriage(triageId, {
        'urgency': _urgency,
        'status': 'reviewed',
        'notes': _notes.text.trim(),
        'vitals_bp': _bp.text.trim(),
        'vitals_temp': _temp.text.trim(),
        'vitals_pulse': _pulse.text.trim(),
        'vitals_spo2': _spo2.text.trim(),
      });
      await care.assignQueue(aptId, {
        'urgency': _urgency == 'emergency' || _urgency == 'urgent' ? 'High' : 'Medium',
        'triage_urgency': _urgency,
        'status': 'approved',
        if (_doctorId != null) 'doctor_id': _doctorId,
        'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Review & assign',
              style: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.row['full_name']?.toString() ?? 'Patient',
              style: GoogleFonts.roboto(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _urgency,
              decoration: const InputDecoration(labelText: 'Urgency', border: OutlineInputBorder()),
              items: const ['routine', 'urgent', 'emergency']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _urgency = v ?? _urgency),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _doctorId,
              decoration: const InputDecoration(labelText: 'Assign doctor', border: OutlineInputBorder()),
              items: widget.doctors
                  .map(
                    (d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        '${d.name}${d.isOnline ? ' · online' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _doctorId = v),
            ),
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
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Nursing notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2C4),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(_saving ? 'Saving…' : 'Save & hand off to doctor'),
            ),
          ],
        ),
      ),
    );
  }
}
