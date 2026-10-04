import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

/// Clinician / ops roster of NCD + antenatal care-program enrollments.
class CareProgramsRosterScreen extends StatefulWidget {
  const CareProgramsRosterScreen({super.key});

  @override
  State<CareProgramsRosterScreen> createState() => _CareProgramsRosterScreenState();
}

class _CareProgramsRosterScreenState extends State<CareProgramsRosterScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String _programFilter = 'all';
  String _statusFilter = 'all';
  final _search = TextEditingController();
  final _patientCode = TextEditingController();
  String? _enrolKey;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    _patientCode.dispose();
    super.dispose();
  }

  Map<String, dynamic> _summary() =>
      (_data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> _list(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> get _enrollments => _list(_data['enrollments']);
  List<Map<String, dynamic>> get _catalog => _list(_data['catalog']);
  List<Map<String, dynamic>> get _byProgram => _list(_summary()['by_program']);

  int _n(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().chronicRoster(
            programKey: _programFilter == 'all' ? null : _programFilter,
            status: _statusFilter == 'all' ? null : _statusFilter,
            q: _search.text.trim().isEmpty ? null : _search.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
        _enrolKey ??= _catalog.isNotEmpty ? _catalog.first['key']?.toString() : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _enrol() async {
    final code = _patientCode.text.trim();
    final key = _enrolKey;
    if (code.isEmpty || key == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().enrollChronic({
        'patient_code': code,
        'program_key': key,
      });
      _patientCode.clear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Patient enrolled in care program')));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Enrol failed: $e')));
    }
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    final id = _n(row['id']);
    if (id == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().updateChronicProgram(id, {'status': status});
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Status → $status')));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    final id = _n(row['id']);
    if (id == 0) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: digiPaper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _EnrollmentDetailSheet(
        enrollmentId: id,
        patientName: row['patient_name']?.toString() ?? 'Patient',
        onChanged: () {
          if (mounted) _load(silent: true);
        },
      ),
    );
    if (mounted) await _load(silent: true);
  }

  String _dateLabel(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return digiForest;
      case 'suspended':
        return const Color(0xFFB45309);
      case 'completed':
        return digiSlate;
      default:
        return digiSlate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final summary = _summary();

    return Scaffold(
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: 'Care programs',
        subtitle: 'NCD · antenatal roster — assistive, not a diagnosis',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: _loading && _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: digiForest,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    MaterialBanner(
                      content: Text(_error!, style: const TextStyle(fontSize: 12)),
                      actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
                    ),
                  Text(
                    'Program roster',
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: digiInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _data['note']?.toString() ??
                        'Hypertension, diabetes, asthma, sickle cell, and antenatal enrollments.',
                    style: GoogleFonts.dmSans(color: digiSlate, height: 1.4, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _kpi('Active', summary['active']),
                      _kpi('Suspended', summary['suspended']),
                      _kpi('Completed', summary['completed']),
                      _kpi('Total', summary['total']),
                    ],
                  ),
                  if (_byProgram.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _byProgram.map((p) {
                        final key = p['program_key']?.toString() ?? '';
                        final selected = _programFilter == key;
                        return FilterChip(
                          selected: selected,
                          label: Text(
                            '${p['name'] ?? key} (${_n(p['active'])})',
                            style: GoogleFonts.dmSans(fontSize: 12),
                          ),
                          selectedColor: digiForest.withValues(alpha: 0.15),
                          checkmarkColor: digiForest,
                          onSelected: (_) {
                            setState(() => _programFilter = selected ? 'all' : key);
                            _load();
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Enrol patient',
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: digiInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Link by patient ID. Duplicate active enrollments for the same program are ignored.',
                    style: GoogleFonts.dmSans(color: digiSlate, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _patientCode,
                    decoration: const InputDecoration(
                      labelText: 'Patient ID (DH-100001)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _enrolKey != null && _catalog.any((c) => c['key'] == _enrolKey)
                        ? _enrolKey
                        : (_catalog.isNotEmpty ? _catalog.first['key']?.toString() : null),
                    decoration: const InputDecoration(
                      labelText: 'Program',
                      border: OutlineInputBorder(),
                    ),
                    items: _catalog
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['key']?.toString(),
                            child: Text(c['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _enrolKey = v),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _enrol,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Enrol'),
                      style: FilledButton.styleFrom(backgroundColor: digiForest),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Search name, code, phone',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in ['all', 'active', 'suspended', 'completed'])
                        ChoiceChip(
                          label: Text(s == 'all' ? 'All status' : s, style: GoogleFonts.dmSans(fontSize: 12)),
                          selected: _statusFilter == s,
                          onSelected: (_) {
                            setState(() => _statusFilter = s);
                            _load();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_enrollments.isEmpty)
                    Text('No enrollments match.', style: GoogleFonts.dmSans(color: digiSlate))
                  else
                    ..._enrollments.map(_enrollmentCard),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _kpi(String label, dynamic value) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: digiLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_n(value)}',
            style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.bold, color: digiForest),
          ),
          Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
        ],
      ),
    );
  }

  Widget _enrollmentCard(Map<String, dynamic> row) {
    final status = (row['status']?.toString() ?? 'active').toLowerCase();
    final adherence = (row['adherence'] as Map?)?.cast<String, dynamic>() ?? {};
    final pct = _n(adherence['percent']);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(row),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: digiLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row['patient_name']?.toString() ?? 'Patient',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk, fontSize: 15),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(status),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: digiSlate.withValues(alpha: 0.7), size: 22),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${row['patient_code'] ?? '—'} · ${row['condition'] ?? row['program_key'] ?? 'Program'}',
                style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('Last visit ${_dateLabel(row['last_visit'])}',
                      style: GoogleFonts.dmSans(fontSize: 12, color: digiInk)),
                  Text('Review ${_dateLabel(row['next_review'])}',
                      style: GoogleFonts.dmSans(fontSize: 12, color: digiInk)),
                  Text('Tasks $pct% · ${_n(row['pending_tasks'])} pending',
                      style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
                ],
              ),
              if (row['enrolled_by_name'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Enrolled by ${row['enrolled_by_name']}',
                  style: GoogleFonts.dmSans(fontSize: 11, color: digiSlate),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Tap for adherence tasks',
                style: GoogleFonts.dmSans(fontSize: 11, color: digiForest, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (status != 'active')
                    OutlinedButton(
                      onPressed: () => _setStatus(row, 'active'),
                      child: const Text('Activate'),
                    ),
                  if (status == 'active')
                    OutlinedButton(
                      onPressed: () => _setStatus(row, 'suspended'),
                      child: const Text('Suspend'),
                    ),
                  if (status != 'completed')
                    OutlinedButton(
                      onPressed: () => _setStatus(row, 'completed'),
                      child: const Text('Complete'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnrollmentDetailSheet extends StatefulWidget {
  const _EnrollmentDetailSheet({
    required this.enrollmentId,
    required this.patientName,
    required this.onChanged,
  });

  final int enrollmentId;
  final String patientName;
  final VoidCallback onChanged;

  @override
  State<_EnrollmentDetailSheet> createState() => _EnrollmentDetailSheetState();
}

class _EnrollmentDetailSheetState extends State<_EnrollmentDetailSheet> {
  Map<String, dynamic> _detail = {};
  bool _loading = true;
  String? _error;
  bool _saving = false;
  late final TextEditingController _review;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _review = TextEditingController();
    _notes = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _review.dispose();
    _notes.dispose();
    super.dispose();
  }

  int _n(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _dateLabel(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  List<Map<String, dynamic>> get _tasks {
    final raw = _detail['tasks'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<CareRepository>().chronicEnrollment(widget.enrollmentId);
      if (!mounted) return;
      setState(() {
        _detail = data;
        _loading = false;
        _review.text = _dateLabel(data['next_review']);
        _notes.text = data['notes']?.toString() ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    final programId = _n(_detail['id']);
    final taskId = _n(task['id']);
    if (programId == 0 || taskId == 0) return;
    final next = task['status'] == 'done' ? 'pending' : 'done';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().updateChronicTask(
        programId,
        taskId,
        {'status': next},
      );
      widget.onChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Task update failed: $e')));
    }
  }

  Future<void> _saveMeta() async {
    final programId = _n(_detail['id']);
    if (programId == 0) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final review = _review.text.trim();
      await context.read<CareRepository>().updateChronicProgram(programId, {
        if (review.isNotEmpty) 'next_review': review,
        'notes': _notes.text.trim(),
      });
      widget.onChanged();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Review & notes saved')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickReviewDate() async {
    final now = DateTime.now();
    DateTime initial = now;
    final parsed = DateTime.tryParse(_review.text.trim());
    if (parsed != null) initial = parsed;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _review.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final adherence = (_detail['adherence'] as Map?)?.cast<String, dynamic>() ?? {};
    final pct = _n(adherence['percent']);
    final done = _n(adherence['done']);
    final total = _n(adherence['total']);
    final status = (_detail['status']?.toString() ?? '').toLowerCase();

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    )
                  : ListView(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: digiLine,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.patientName,
                          style: GoogleFonts.sourceSerif4(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: digiInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_detail['patient_code'] ?? '—'} · ${_detail['condition'] ?? 'Program'}'
                          '${status.isNotEmpty ? ' · $status' : ''}',
                          style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                        ),
                        if (_detail['note'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _detail['note'].toString(),
                            style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate, height: 1.35),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: digiLine),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Adherence $pct%',
                                    style: GoogleFonts.dmSans(
                                      fontWeight: FontWeight.w700,
                                      color: digiForest,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '$done / $total tasks',
                                    style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: total == 0 ? 0 : done / total,
                                  minHeight: 8,
                                  backgroundColor: digiLine,
                                  color: digiForest,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Next review ${_dateLabel(_detail['next_review']).isEmpty ? '—' : _dateLabel(_detail['next_review'])}'
                                ' · last visit ${_dateLabel(_detail['last_visit']).isEmpty ? '—' : _dateLabel(_detail['last_visit'])}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: digiInk),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Adherence tasks',
                          style: GoogleFonts.sourceSerif4(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: digiInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Toggle tasks the patient completed. Assistive checklist — not a diagnosis.',
                          style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                        ),
                        const SizedBox(height: 8),
                        if (_tasks.isEmpty)
                          Text('No tasks on this enrollment.', style: GoogleFonts.dmSans(color: digiSlate))
                        else
                          ..._tasks.map((t) {
                            final isDone = t['status'] == 'done';
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: isDone,
                              activeColor: digiForest,
                              onChanged: (_) => _toggleTask(t),
                              title: Text(
                                t['title']?.toString() ?? 'Task',
                                style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w600,
                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              subtitle: Text(
                                '${t['cadence'] ?? ''} · due ${_dateLabel(t['due_on']).isEmpty ? '—' : _dateLabel(t['due_on'])}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                              ),
                            );
                          }),
                        const SizedBox(height: 16),
                        Text(
                          'Clinician notes',
                          style: GoogleFonts.sourceSerif4(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: digiInk,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _review,
                          readOnly: true,
                          onTap: _pickReviewDate,
                          decoration: InputDecoration(
                            labelText: 'Next review (YYYY-MM-DD)',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today_outlined),
                              onPressed: _pickReviewDate,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _saveMeta,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving…' : 'Save review & notes'),
                            style: FilledButton.styleFrom(backgroundColor: digiForest),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
        ),
      ),
    );
  }
}
