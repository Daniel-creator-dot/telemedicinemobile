import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../nurse/nurse_home_screen.dart';
import '../patient/care_repository.dart';

class OpsHomeScreen extends StatefulWidget {
  const OpsHomeScreen({super.key});

  @override
  State<OpsHomeScreen> createState() => _OpsHomeScreenState();
}

class _OpsHomeScreenState extends State<OpsHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic> _board = {};
  bool _loading = true;
  String? _error;
  Timer? _poll;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final board = await context.read<CareRepository>().opsBoard();
      if (!mounted) return;
      setState(() {
        _board = board;
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

  Map<String, dynamic> get _stats =>
      (_board['stats'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> _list(String key) {
    final raw = _board[key];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, List<Map<String, dynamic>>> get _partners {
    final raw = _board['partners'];
    if (raw is! Map) return {};
    final out = <String, List<Map<String, dynamic>>>{};
    for (final entry in raw.entries) {
      final list = entry.value;
      if (list is List) {
        out[entry.key.toString()] = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return out;
  }

  Future<void> _assignDoctor(Map<String, dynamic> row) async {
    final doctors = _list('doctors');
    if (doctors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active doctors in the directory')),
      );
      return;
    }
    int? selected = doctors.firstWhere(
      (d) => d['is_online'] == true,
      orElse: () => doctors.first,
    )['id'] as int?;
    final aptId = row['id'] is int ? row['id'] as int : int.tryParse('${row['id']}');
    if (aptId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Assign clinician'),
          content: DropdownButtonFormField<int>(
            value: selected,
            decoration: const InputDecoration(labelText: 'Doctor', border: OutlineInputBorder()),
            items: doctors
                .map(
                  (d) => DropdownMenuItem(
                    value: d['id'] is int ? d['id'] as int : int.tryParse('${d['id']}'),
                    child: Text(
                      '${d['name']}${d['is_online'] == true ? ' · online' : ''} · ${d['open_cases'] ?? 0} open',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .where((e) => e.value != null)
                .toList(),
            onChanged: (v) => setLocal(() => selected = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
          ],
        ),
      ),
    );
    if (ok != true || selected == null || !mounted) return;
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await care.assignQueue(aptId, {
        'doctor_id': selected,
        'status': 'approved',
        'urgency': 'Medium',
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Assigned ${row['full_name'] ?? 'patient'} to clinician')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Assign failed: $e')));
    }
  }

  Future<void> _assignPartner({
    required String kind,
    required Map<String, dynamic> row,
    required String partnerType,
  }) async {
    final partners = _partners[partnerType] ?? const [];
    if (partners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No $partnerType partners on the network')),
      );
      return;
    }
    final id = row['id'] is int ? row['id'] as int : int.tryParse('${row['id']}');
    if (id == null) return;
    int? selected = partners.first['id'] is int
        ? partners.first['id'] as int
        : int.tryParse('${partners.first['id']}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(row['partner_name'] == null && row['pharmacy_name'] == null && row['org_name'] == null
              ? 'Assign partner'
              : 'Re-route partner'),
          content: DropdownButtonFormField<int>(
            value: selected,
            decoration: const InputDecoration(labelText: 'Facility', border: OutlineInputBorder()),
            items: partners
                .map(
                  (p) => DropdownMenuItem(
                    value: p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}'),
                    child: Text(
                      '${p['name']}${p['town'] != null ? ' · ${p['town']}' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .where((e) => e.value != null)
                .toList(),
            onChanged: (v) => setLocal(() => selected = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Route')),
          ],
        ),
      ),
    );
    if (ok != true || selected == null || !mounted) return;
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await care.opsAssignPartner(
        kind: kind,
        id: id,
        partnerId: selected!,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Partner routed — patient & facility notified')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Route failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: 'Medical operations',
        subtitle: 'Queue assign · closed-loop network',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: _loading && _board.isEmpty
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
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Queue'),
                    Tab(text: 'Network'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _OverviewTab(
                        stats: _stats,
                        note: _board['note']?.toString(),
                        onOpenTriage: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const NurseHomeScreen()),
                          );
                        },
                        onOpenNetwork: () => context.push('/ops/network'),
                        onOpenSupport: () => context.push('/ops/support'),
                        onOpenPrograms: () => context.push('/ops/programs'),
                      ),
                      _QueueTab(
                        queue: _list('queue'),
                        onAssign: _assignDoctor,
                        onRefresh: _load,
                      ),
                      _NetworkTab(
                        labs: _list('labs'),
                        scans: _list('scans'),
                        pharmacy: _list('pharmacy'),
                        referrals: _list('referrals'),
                        onAssignLab: (r) => _assignPartner(kind: 'lab', row: r, partnerType: 'laboratory'),
                        onAssignScan: (r) => _assignPartner(kind: 'scan', row: r, partnerType: 'imaging'),
                        onAssignRx: (r) => _assignPartner(kind: 'pharmacy', row: r, partnerType: 'pharmacy'),
                        onAssignRef: (r) => _assignPartner(kind: 'referral', row: r, partnerType: 'hospital'),
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
    required this.stats,
    required this.onOpenTriage,
    required this.onOpenNetwork,
    required this.onOpenSupport,
    required this.onOpenPrograms,
    this.note,
  });

  final Map<String, dynamic> stats;
  final String? note;
  final VoidCallback onOpenTriage;
  final VoidCallback onOpenNetwork;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenPrograms;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Command centre',
          style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 6),
        Text(
          note ??
              'Assign waiting Consult Now patients and route open labs, imaging, pharmacy and referrals. Clinical documentation stays with the treating doctor.',
          style: GoogleFonts.dmSans(color: digiSlate, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _stat('Doctors online', stats['doctors_online']),
            _stat('Waiting', stats['patients_waiting']),
            _stat('Consulting', stats['consulting_now']),
            _stat('Open labs', stats['pending_labs']),
            _stat('Open scans', stats['pending_scans']),
            _stat('Pharmacy', stats['pending_pharmacy']),
            _stat('Referrals', stats['open_referrals']),
            _stat('Unassigned labs', stats['unassigned_labs']),
            _stat('Unassigned Rx', stats['unassigned_rx']),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onOpenTriage,
          icon: const Icon(Icons.monitor_heart_outlined),
          label: const Text('Open nurse triage (vitals & urgency)'),
          style: FilledButton.styleFrom(backgroundColor: digiForest),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onOpenNetwork,
          icon: const Icon(Icons.public),
          label: const Text('National coverage & alerts'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onOpenSupport,
          icon: const Icon(Icons.support_agent_outlined),
          label: const Text('Support desk'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onOpenPrograms,
          icon: const Icon(Icons.favorite_outline),
          label: const Text('Care programs roster'),
        ),
      ],
    );
  }

  Widget _stat(String label, dynamic value) {
    String text = value?.toString() ?? '0';
    if (value is num && value is! int) text = value.toStringAsFixed(0);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: digiLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.bold, color: digiForest)),
          Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
        ],
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.onAssign,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> queue;
  final Future<void> Function(Map<String, dynamic>) onAssign;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            ClinicalEmptyState(
              icon: Icons.queue_outlined,
              title: 'Live queue is clear',
              message: 'Consult Now patients waiting for a clinician will appear here for Medical Ops assign.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: queue.length,
        itemBuilder: (_, i) {
          final row = queue[i];
          final needsDoctor = row['doctor_id'] == null;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row['full_name']?.toString() ?? 'Patient',
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('#${row['queue_number'] ?? '—'}', style: const TextStyle(color: digiForest)),
                    ],
                  ),
                  Text(
                    '${row['status'] ?? 'queued'} · ${row['urgency'] ?? row['priority'] ?? 'routine'}'
                    '${row['patient_code'] != null ? ' · ${row['patient_code']}' : ''}',
                    style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                  ),
                  if ((row['complaint'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(row['complaint'].toString(), style: GoogleFonts.dmSans(fontSize: 13)),
                    ),
                  Text(
                    row['doctor_name'] != null
                        ? 'Doctor: ${row['doctor_name']}${row['doctor_online'] == true ? ' · online' : ''}'
                        : 'No clinician assigned',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: needsDoctor ? const Color(0xFFB45309) : digiForest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => onAssign(row),
                      child: Text(needsDoctor ? 'Assign doctor' : 'Reassign'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NetworkTab extends StatelessWidget {
  const _NetworkTab({
    required this.labs,
    required this.scans,
    required this.pharmacy,
    required this.referrals,
    required this.onAssignLab,
    required this.onAssignScan,
    required this.onAssignRx,
    required this.onAssignRef,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> labs;
  final List<Map<String, dynamic>> scans;
  final List<Map<String, dynamic>> pharmacy;
  final List<Map<String, dynamic>> referrals;
  final Future<void> Function(Map<String, dynamic>) onAssignLab;
  final Future<void> Function(Map<String, dynamic>) onAssignScan;
  final Future<void> Function(Map<String, dynamic>) onAssignRx;
  final Future<void> Function(Map<String, dynamic>) onAssignRef;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final empty = labs.isEmpty && scans.isEmpty && pharmacy.isEmpty && referrals.isEmpty;
    if (empty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            ClinicalEmptyState(
              icon: Icons.hub_outlined,
              title: 'No open network loops',
              message: 'Pending labs, imaging, prescriptions and referrals will show here for partner routing.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Labs', labs, (r) => r['test_name']?.toString() ?? 'Lab', (r) => r['partner_name']?.toString(), onAssignLab),
          _section('Imaging', scans, (r) => r['scan_type']?.toString() ?? 'Scan', (r) => r['partner_name']?.toString(), onAssignScan),
          _section('Pharmacy', pharmacy, (r) => r['medication_name']?.toString() ?? 'Rx', (r) => r['pharmacy_name']?.toString(), onAssignRx),
          _section('Referrals', referrals, (r) => r['referral_code']?.toString() ?? 'Referral', (r) => r['org_name']?.toString(), onAssignRef),
        ],
      ),
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic>) headline,
    String? Function(Map<String, dynamic>) partner,
    Future<void> Function(Map<String, dynamic>) onAssign,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(title, style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        ...rows.map((r) {
          final partnerName = partner(r);
          final unassigned = partnerName == null || partnerName.isEmpty;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(headline(r), style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${r['patient_name'] ?? 'Patient'} · ${r['status'] ?? r['dispense_status'] ?? 'open'}'
                '${unassigned ? ' · needs facility' : ' · $partnerName'}',
                style: GoogleFonts.dmSans(fontSize: 12, color: unassigned ? const Color(0xFFB45309) : digiSlate),
              ),
              trailing: TextButton(
                onPressed: () => onAssign(r),
                child: Text(unassigned ? 'Assign' : 'Re-route'),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}
