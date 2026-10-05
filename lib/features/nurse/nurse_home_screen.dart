import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';
import '../auth/pending_review_banner.dart';
import '../homecare/home_care_screen.dart';
import 'nurse_job_alerts.dart';
import '../../models/role.dart';
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
  Map<String, dynamic>? _agency;
  bool _loading = true;
  int _homeCareToken = 0;
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
    Map<String, dynamic>? agency = _agency;
    var agencyKnown = false;
    try {
      final res = await context.read<ApiClient>().dio.get<Map<String, dynamic>>('/api/agency/me');
      agency = res.data;
      agencyKnown = true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        agency = null;
        agencyKnown = true;
      }
    } catch (_) {}
    if (!mounted) return;

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
        if (agencyKnown) _agency = agency;
        _loading = false;
        _homeCareToken++;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (agencyKnown) _agency = agency;
          _loading = false;
          _homeCareToken++;
        });
      }
    }
  }

  bool _canAddPatient(Session session) {
    final user = session.user;
    if (user == null) return false;
    if (user.role == AppRole.admin) return true;
    if (user.role != AppRole.nurse) return false;
    final status = (user.verificationStatus ?? _agency?['verification_status']?.toString() ?? '')
        .trim()
        .toLowerCase();
    return status == 'approved';
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
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: 'Triage',
        subtitle: session.user?.name ?? 'Nurse',
        trailing: const [NurseJobAlertButton()],
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PendingReviewBanner(
            status: _agency?['verification_status']?.toString() ?? session.user?.verificationStatus,
          ),
          if (_agency != null) _agencyCard(_agency!),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_canAddPatient(session)) ...[
                          ClinicalPrimaryButton(
                            label: 'Add a patient',
                            onPressed: () => context.push('/nurse/add-patient'),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (session.user?.role == AppRole.nurse) ...[
                          HomeCareNurseSection(reloadToken: _homeCareToken),
                          const SizedBox(height: 8),
                        ],
                        if (_triage.isEmpty)
                          DigiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Triage queue is clear', style: clinicalDisplay(18)),
                                const SizedBox(height: 8),
                                Text(
                                  'New Consult Now patients will appear here for vitals, urgency and handover to a doctor.',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45, color: digiSlate),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final t in _triage) _triageCard(t),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _triageCard(Map<String, dynamic> t) {
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
  }

  Widget _agencyCard(Map<String, dynamic> agency) {
    final region = agency['region']?.toString().trim() ?? '';
    final town = agency['town']?.toString().trim() ?? '';
    final place = [region, town].where((part) => part.isNotEmpty).join(' · ');
    final phone = agency['phone']?.toString().trim() ?? '';
    final status = agency['verification_status']?.toString();
    final statusLabel = switch (status) {
      'approved' => 'Approved',
      'rejected' => 'Not approved',
      _ => 'Pending review',
    };

    final tone = switch (status) {
      'approved' => ClinicalTone.forest,
      'rejected' => ClinicalTone.clay,
      _ => ClinicalTone.gold,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DigiCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(AppBrand.logoAsset, width: 40, height: 40, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nurse agency',
                    style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: digiSlate),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agency['name']?.toString().trim().isNotEmpty == true ? agency['name'].toString() : 'Agency',
                    style: clinicalDisplay(22),
                  ),
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(place, style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4)),
                  ],
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(phone, style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate)),
                  ],
                  const SizedBox(height: 10),
                  ClinicalStatusPill(label: statusLabel, tone: tone),
                ],
              ),
            ),
          ],
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
