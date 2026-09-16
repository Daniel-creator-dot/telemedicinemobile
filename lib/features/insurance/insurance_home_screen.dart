import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class InsuranceHomeScreen extends StatefulWidget {
  const InsuranceHomeScreen({super.key});

  @override
  State<InsuranceHomeScreen> createState() => _InsuranceHomeScreenState();
}

class _InsuranceHomeScreenState extends State<InsuranceHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String _claimFilter = 'open';
  Timer? _poll;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 25), (_) {
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
      final data = await context.read<CareRepository>().insuranceWorkbench();
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

  Future<void> _actClaim(Map<String, dynamic> claim, String status, {String? notes}) async {
    final id = _idOf(claim);
    if (id == 0) return;
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await care.updateClaim(id, {
        'status': status,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      if (!mounted) return;
      final label = switch (status) {
        'approved' => 'approved — patient notified',
        'rejected' => 'denied — patient notified',
        'queried' => 'queried — patient notified',
        'paid' => 'marked paid — patient notified',
        'submitted' => 'returned to open queue',
        _ => 'updated',
      };
      messenger.showSnackBar(SnackBar(content: Text('${claim['claim_code']} $label')));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Claim update failed: $e')));
    }
  }

  Future<void> _queryClaim(Map<String, dynamic> claim) async {
    final notes = TextEditingController(
      text: claim['notes']?.toString().isNotEmpty == true
          ? claim['notes'].toString()
          : 'Please upload the consultation receipt or referral letter.',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Query patient'),
        content: TextField(
          controller: notes,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'What do you need from the member?',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send query')),
        ],
      ),
    );
    final text = notes.text;
    notes.dispose();
    if (ok != true || !mounted) return;
    await _actClaim(claim, 'queried', notes: text);
  }

  Future<void> _denyClaim(Map<String, dynamic> claim) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny claim'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Denial reason (shared with patient)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deny')),
        ],
      ),
    );
    final text = notes.text;
    notes.dispose();
    if (ok != true || !mounted) return;
    await _actClaim(claim, 'rejected', notes: text.isEmpty ? 'Claim denied by insurer.' : text);
  }

  Future<void> _actPreauth(Map<String, dynamic> row, String status) async {
    final id = _idOf(row);
    if (id == 0) return;
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await care.updatePreauth(id, {
        'status': status,
        if (status == 'approved') 'approved_amount': row['requested_amount'],
        if (status == 'denied') 'notes': 'Preauth denied by insurer desk.',
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${row['preauth_code']} ${status == 'approved' ? 'approved' : 'denied'} — patient notified',
          ),
        ),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Preauth update failed: $e')));
    }
  }

  List<Map<String, dynamic>> get _filteredClaims {
    final all = _list('claims');
    switch (_claimFilter) {
      case 'open':
        return all.where((c) => c['status']?.toString() == 'submitted').toList();
      case 'queried':
        return all.where((c) => c['status']?.toString() == 'queried').toList();
      case 'approved':
        return all.where((c) => c['status']?.toString() == 'approved').toList();
      case 'closed':
        return all
            .where((c) => ['paid', 'rejected'].contains(c['status']?.toString()))
            .toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final insurer = (_data['insurer'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: insurer['name']?.toString() ?? 'Insurance desk',
        subtitle: 'Claims · preauth · policies',
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
                    Tab(text: 'Claims'),
                    Tab(text: 'Preauths'),
                    Tab(text: 'Policies'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _OverviewTab(
                        insurer: insurer,
                        stats: _stats,
                        note: _data['note']?.toString(),
                        onOpenClaims: () => _tabs.animateTo(1),
                        onOpenPreauths: () => _tabs.animateTo(2),
                      ),
                      _ClaimsTab(
                        claims: _filteredClaims,
                        filter: _claimFilter,
                        onFilter: (f) => setState(() => _claimFilter = f),
                        onApprove: (c) => _actClaim(c, 'approved'),
                        onQuery: _queryClaim,
                        onDeny: _denyClaim,
                        onPay: (c) => _actClaim(c, 'paid'),
                        onReopen: (c) => _actClaim(c, 'submitted'),
                        onRefresh: _load,
                      ),
                      _PreauthsTab(
                        rows: _list('preauths'),
                        onApprove: (r) => _actPreauth(r, 'approved'),
                        onDeny: (r) => _actPreauth(r, 'denied'),
                        onRefresh: _load,
                      ),
                      _PoliciesTab(policies: _list('policies')),
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
    required this.insurer,
    required this.stats,
    required this.onOpenClaims,
    required this.onOpenPreauths,
    this.note,
  });

  final Map<String, dynamic> insurer;
  final Map<String, dynamic> stats;
  final String? note;
  final VoidCallback onOpenClaims;
  final VoidCallback onOpenPreauths;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Claims desk',
          style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 4),
        Text(
          '${insurer['plan_name'] ?? 'Plan'} · ${insurer['coverage_percent'] ?? 80}% cover · copay GHS ${insurer['copay_amount'] ?? 10}',
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
              child: StatTile(label: 'Open claims', value: '${stats['open_claims'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Queried', value: '${stats['queried_claims'] ?? 0}', accent: digiGold),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Approved', value: '${stats['approved_claims'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Paid', value: '${stats['paid_claims'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Denied', value: '${stats['rejected_claims'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Pending preauth', value: '${stats['pending_preauths'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Active policies', value: '${stats['policies_active'] ?? 0}'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onOpenClaims,
          icon: const Icon(Icons.fact_check_outlined),
          style: FilledButton.styleFrom(backgroundColor: digiForest),
          label: const Text('Work open claims'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onOpenPreauths,
          icon: const Icon(Icons.pending_actions_outlined),
          label: const Text('Review preauths'),
        ),
      ],
    );
  }
}

class _ClaimsTab extends StatelessWidget {
  const _ClaimsTab({
    required this.claims,
    required this.filter,
    required this.onFilter,
    required this.onApprove,
    required this.onQuery,
    required this.onDeny,
    required this.onPay,
    required this.onReopen,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> claims;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onQuery;
  final ValueChanged<Map<String, dynamic>> onDeny;
  final ValueChanged<Map<String, dynamic>> onPay;
  final ValueChanged<Map<String, dynamic>> onReopen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              for (final entry in const [
                ('open', 'Open'),
                ('queried', 'Queried'),
                ('approved', 'Approved'),
                ('closed', 'Closed'),
                ('all', 'All'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: filter == entry.$1,
                    onSelected: (_) => onFilter(entry.$1),
                    selectedColor: digiForest.withValues(alpha: 0.15),
                    labelStyle: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      color: filter == entry.$1 ? digiForest : digiSlate,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: claims.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Icon(Icons.inbox_outlined, size: 48, color: digiSlate.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'No claims in this filter',
                          style: GoogleFonts.dmSans(color: digiSlate),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: claims.length,
                    itemBuilder: (context, i) {
                      final c = claims[i];
                      final status = c['status']?.toString() ?? 'submitted';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: digiForest.withValues(alpha: 0.08)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${c['claim_code']} · ${c['full_name'] ?? ''}',
                                      style: GoogleFonts.sourceSerif4(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: digiInk,
                                      ),
                                    ),
                                  ),
                                  _StatusPill(status: status),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (c['policy_number'] != null) 'Policy ${c['policy_number']}',
                                  if (c['apt_code'] != null) 'Visit ${c['apt_code']}',
                                  'GHS ${c['amount']}',
                                  if (c['phone_number'] != null) '${c['phone_number']}',
                                ].join(' · '),
                                style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                              ),
                              if (c['notes'] != null && '${c['notes']}'.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${c['notes']}',
                                  style: GoogleFonts.dmSans(fontSize: 13, color: digiInk, height: 1.35),
                                ),
                              ],
                              if (c['adjudicator_name'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'By ${c['adjudicator_name']}',
                                  style: GoogleFonts.dmSans(fontSize: 11, color: digiSlate),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (status == 'submitted' || status == 'queried') ...[
                                    FilledButton(
                                      onPressed: () => onApprove(c),
                                      style: FilledButton.styleFrom(backgroundColor: digiForest),
                                      child: const Text('Approve'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => onQuery(c),
                                      child: const Text('Query'),
                                    ),
                                    TextButton(
                                      onPressed: () => onDeny(c),
                                      child: const Text('Deny'),
                                    ),
                                  ],
                                  if (status == 'approved')
                                    FilledButton(
                                      onPressed: () => onPay(c),
                                      style: FilledButton.styleFrom(backgroundColor: digiForest),
                                      child: const Text('Mark paid'),
                                    ),
                                  if (status == 'queried')
                                    TextButton(
                                      onPressed: () => onReopen(c),
                                      child: const Text('Clear query'),
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
        ),
      ],
    );
  }
}

class _PreauthsTab extends StatelessWidget {
  const _PreauthsTab({
    required this.rows,
    required this.onApprove,
    required this.onDeny,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onDeny;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: rows.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('No preauths', style: GoogleFonts.dmSans(color: digiSlate))),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final status = r['status']?.toString() ?? 'pending';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: digiForest.withValues(alpha: 0.08)),
                  ),
                  child: ListTile(
                    title: Text(
                      '${r['preauth_code']} · ${r['full_name']}',
                      style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600, color: digiInk),
                    ),
                    subtitle: Text(
                      '${r['service'] ?? 'consult'} · GHS ${r['requested_amount']} · ${r['policy_number'] ?? ''} · $status',
                      style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                    ),
                    trailing: status == 'pending'
                        ? Wrap(
                            spacing: 4,
                            children: [
                              FilledButton(
                                onPressed: () => onApprove(r),
                                style: FilledButton.styleFrom(
                                  backgroundColor: digiForest,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Approve'),
                              ),
                              TextButton(onPressed: () => onDeny(r), child: const Text('Deny')),
                            ],
                          )
                        : _StatusPill(status: status),
                  ),
                );
              },
            ),
    );
  }
}

class _PoliciesTab extends StatelessWidget {
  const _PoliciesTab({required this.policies});

  final List<Map<String, dynamic>> policies;

  @override
  Widget build(BuildContext context) {
    if (policies.isEmpty) {
      return Center(child: Text('No policies on this book', style: GoogleFonts.dmSans(color: digiSlate)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: policies.length,
      itemBuilder: (context, i) {
        final p = policies[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: Colors.white,
          elevation: 0,
          child: ListTile(
            title: Text(
              '${p['full_name']} · ${p['policy_number']}',
              style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600, color: digiInk),
            ),
            subtitle: Text(
              '${p['patient_code'] ?? ''} · ${p['status']}',
              style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'submitted' || 'pending' => digiGold,
      'queried' => const Color(0xFFB45309),
      'approved' => digiForest,
      'paid' => digiForest,
      'rejected' || 'denied' => const Color(0xFF9B2C2C),
      _ => digiSlate,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
