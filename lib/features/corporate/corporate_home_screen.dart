import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class CorporateHomeScreen extends StatefulWidget {
  const CorporateHomeScreen({super.key});

  @override
  State<CorporateHomeScreen> createState() => _CorporateHomeScreenState();
}

class _CorporateHomeScreenState extends State<CorporateHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String _utilFilter = 'all';
  Timer? _poll;
  late final TabController _tabs;
  final _code = TextEditingController();
  final _staff = TextEditingController();
  final _department = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    _code.dispose();
    _staff.dispose();
    _department.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().corporateDashboard();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic> get _corp =>
      (_data['corporate'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic> get _stats =>
      (_data['stats'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> _list(String key) {
    final raw = _data[key];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int _idOf(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is int) return id;
    return int.tryParse('$id') ?? 0;
  }

  List<Map<String, dynamic>> get _filteredUtilisation {
    final all = _list('utilisation');
    switch (_utilFilter) {
      case 'open':
        return all
            .where((u) => ['submitted', 'queried'].contains(u['status']?.toString()))
            .toList();
      case 'approved':
        return all.where((u) => u['status']?.toString() == 'approved').toList();
      case 'paid':
        return all.where((u) => u['status']?.toString() == 'paid').toList();
      case 'rejected':
        return all.where((u) => u['status']?.toString() == 'rejected').toList();
      default:
        return all;
    }
  }

  Future<void> _enroll() async {
    if (_code.text.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().addCorporateMember(
            patientCode: _code.text.trim(),
            staffId: _staff.text.trim().isEmpty ? null : _staff.text.trim(),
            department: _department.text.trim().isEmpty ? null : _department.text.trim(),
          );
      _code.clear();
      _staff.clear();
      _department.clear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Staff enrolled on scheme')));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Enrol failed: $e')));
    }
  }

  Future<void> _toggleMember(Map<String, dynamic> member) async {
    final id = _idOf(member);
    if (id == 0) return;
    final active = member['status']?.toString() == 'active';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().updateCorporateMember(
            id,
            active ? 'suspended' : 'active',
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(active ? 'Cover suspended' : 'Cover activated')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final title = _corp['name']?.toString().isNotEmpty == true
        ? _corp['name'].toString()
        : 'Corporate scheme';
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: title,
        subtitle: 'Roster · utilisation · cover — no clinical notes',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: _loading && _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!, style: const TextStyle(fontSize: 12)),
                    actions: [
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                TabBar(
                  controller: _tabs,
                  labelColor: digiForest,
                  unselectedLabelColor: digiSlate,
                  indicatorColor: digiGold,
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Roster'),
                    Tab(text: 'Utilisation'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _OverviewTab(
                        corp: _corp,
                        stats: _stats,
                        byDepartment: _list('by_department'),
                        note: _data['note']?.toString(),
                        onOpenRoster: () => _tabs.animateTo(1),
                        onOpenUtilisation: () => _tabs.animateTo(2),
                      ),
                      _RosterTab(
                        members: _list('members'),
                        code: _code,
                        staff: _staff,
                        department: _department,
                        onEnrol: _enroll,
                        onToggle: _toggleMember,
                      ),
                      _UtilisationTab(
                        rows: _filteredUtilisation,
                        filter: _utilFilter,
                        onFilter: (f) => setState(() => _utilFilter = f),
                        onRefresh: _load,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.corp,
    required this.stats,
    required this.byDepartment,
    required this.onOpenRoster,
    required this.onOpenUtilisation,
    this.note,
  });

  final Map<String, dynamic> corp;
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> byDepartment;
  final String? note;
  final VoidCallback onOpenRoster;
  final VoidCallback onOpenUtilisation;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Staff medical scheme',
          style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 4),
        Text(
          '${corp['industry'] ?? 'Employer'} · ${corp['town'] ?? corp['region'] ?? 'Ghana'} · '
          'copay GHS ${corp['copay_amount'] ?? 20} · covered ${corp['coverage_percent'] ?? 60}%',
          style: GoogleFonts.dmSans(color: digiSlate),
        ),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(note!, style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4)),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 150,
              child: StatTile(label: 'Active staff', value: '${stats['members_active'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Suspended', value: '${stats['members_suspended'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(
                label: 'Billed YTD',
                value: 'GHS ${stats['billed_ytd'] ?? 0}',
                accent: digiGold,
              ),
            ),
            SizedBox(
              width: 150,
              child: StatTile(
                label: 'Limit left',
                value: 'GHS ${stats['limit_remaining'] ?? 0}',
              ),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Annual limit', value: 'GHS ${stats['annual_limit'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Open claims', value: '${stats['claims_open'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Approved', value: '${stats['claims_approved'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Paid claims', value: '${stats['claims_paid'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Staff copay', value: 'GHS ${stats['copay_collected'] ?? 0}'),
            ),
          ],
        ),
        if (byDepartment.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Spend by department (YTD)',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
          ),
          const SizedBox(height: 8),
          ...byDepartment.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${d['department'] ?? 'Unassigned'} · ${d['visits'] ?? 0} visits',
                      style: GoogleFonts.dmSans(color: digiSlate),
                    ),
                  ),
                  Text(
                    'GHS ${d['billed'] ?? 0}',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiForest),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: digiForest),
              onPressed: onOpenRoster,
              child: const Text('Manage roster'),
            ),
            OutlinedButton(
              onPressed: onOpenUtilisation,
              child: const Text('View utilisation'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RosterTab extends StatelessWidget {
  const _RosterTab({
    required this.members,
    required this.code,
    required this.staff,
    required this.department,
    required this.onEnrol,
    required this.onToggle,
  });

  final List<Map<String, dynamic>> members;
  final TextEditingController code;
  final TextEditingController staff;
  final TextEditingController department;
  final VoidCallback onEnrol;
  final void Function(Map<String, dynamic>) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Enrol staff',
          style: GoogleFonts.sourceSerif4(fontSize: 20, fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 4),
        Text(
          'Link a patient ID to this scheme. Suspend cover without deleting the membership.',
          style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: code,
          decoration: const InputDecoration(
            labelText: 'Patient ID (DH-100001)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: staff,
          decoration: const InputDecoration(
            labelText: 'Staff ID (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: department,
          decoration: const InputDecoration(
            labelText: 'Department (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: digiForest),
          onPressed: onEnrol,
          child: const Text('Add member'),
        ),
        const SizedBox(height: 20),
        Text(
          'Members (${members.length})',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Text('No staff enrolled yet.', style: GoogleFonts.dmSans(color: digiSlate))
        else
          ...members.map((m) {
            final active = m['status']?.toString() == 'active';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: digiLine),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['full_name']?.toString() ?? 'Staff',
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${m['patient_code'] ?? ''} · ${m['staff_id'] ?? '—'} · ${m['department'] ?? '—'}',
                          style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          active ? 'Cover active' : 'Cover suspended',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? digiForest : digiSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => onToggle(m),
                    child: Text(active ? 'Suspend' : 'Activate'),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _UtilisationTab extends StatelessWidget {
  const _UtilisationTab({
    required this.rows,
    required this.filter,
    required this.onFilter,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> rows;
  final String filter;
  final ValueChanged<String> onFilter;
  final VoidCallback onRefresh;

  String _money(dynamic v) {
    final n = double.tryParse('$v');
    if (n == null) return '$v';
    return n == n.roundToDouble() ? '${n.toInt()}' : n.toStringAsFixed(2);
  }

  String _when(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('all', 'All'),
      ('open', 'Open'),
      ('approved', 'Approved'),
      ('paid', 'Paid'),
      ('rejected', 'Denied'),
    ];
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: filter == f.$1,
                    onSelected: (_) => onFilter(f.$1),
                    selectedColor: digiForest.withValues(alpha: 0.15),
                    labelStyle: GoogleFonts.dmSans(
                      color: filter == f.$1 ? digiForest : digiSlate,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: rows.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(
                          'No utilisation rows for this filter.',
                          style: GoogleFonts.dmSans(color: digiSlate),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final u = rows[i];
                      final covered = u['covered_amount'] ?? u['amount'] ?? 0;
                      final copay = u['copay_amount'];
                      return Container(
                        padding: const EdgeInsets.all(14),
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
                                Expanded(
                                  child: Text(
                                    u['full_name']?.toString() ?? 'Staff member',
                                    style: GoogleFonts.dmSans(
                                      fontWeight: FontWeight.w700,
                                      color: digiInk,
                                    ),
                                  ),
                                ),
                                Text(
                                  (u['status']?.toString() ?? 'submitted').toUpperCase(),
                                  style: GoogleFonts.dmSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: digiForest,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                u['claim_code']?.toString(),
                                u['staff_id']?.toString(),
                                u['department']?.toString(),
                                u['apt_code']?.toString(),
                              ].where((e) => e != null && e.isNotEmpty).join(' · '),
                              style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Covered GHS ${_money(covered)}'
                              '${copay != null ? ' · copay GHS ${_money(copay)}' : ''}'
                              '${_when(u['submitted_at']).isNotEmpty ? ' · ${_when(u['submitted_at'])}' : ''}',
                              style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600,
                                color: digiInk,
                              ),
                            ),
                            if (u['notes']?.toString().isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(
                                u['notes'].toString(),
                                style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate, height: 1.35),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
