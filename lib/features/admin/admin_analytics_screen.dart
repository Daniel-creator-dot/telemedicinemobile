import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../patient/care_repository.dart';
import 'admin_chrome.dart';

/// Phase 5 national admin analytics — visits, claims, partners, live queue.
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  Timer? _poll;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
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
      final data = await context.read<CareRepository>().adminNationalAnalytics();
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

  Map<String, dynamic> _map(String key) =>
      (_data[key] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> _list(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int _n(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return 'GHS ${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final visits = _map('visits');
    final claims = _map('claims');
    final partners = _map('partners');
    final queue = _map('queue');
    final last7 = (visits['last_7d'] as Map?)?.cast<String, dynamic>() ?? {};

    return Scaffold(
      backgroundColor: AdminPalette.bg,
      body: AdminMeshBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: AdminPalette.ink),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nation Pulse', style: adminSerif(size: 22)),
                          Text(
                            'Visits · claims · partners · queue',
                            style: adminSans(size: 12, color: AdminPalette.mute),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, color: AdminPalette.cyan),
                    ),
                    IconButton(
                      onPressed: () async {
                        await session.clear();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.logout_rounded, color: AdminPalette.mute),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: AdminGlass(
                    glow: AdminPalette.rose,
                    child: Text(
                      'Admin only. ${_error!}',
                      style: adminSans(size: 12, color: AdminPalette.rose),
                    ),
                  ),
                ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: AdminPalette.cyan,
                unselectedLabelColor: AdminPalette.mute,
                indicatorColor: AdminPalette.cyan,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Visits'),
                  Tab(text: 'Claims'),
                  Tab(text: 'Network'),
                ],
              ),
              Expanded(
                child: _loading && _data.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: AdminPalette.cyan))
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _OverviewTab(
                            last7: last7,
                            claims: claims,
                            partners: partners,
                            queue: queue,
                            programs: _n(_map('programs')['active']),
                            alertsOpen: _n(_map('alerts')['open']),
                            audit24h: _n(_data['audit_last_24h']),
                            note: _data['note']?.toString(),
                            money: _money,
                            n: _n,
                            onOpenVisits: () => _tabs.animateTo(1),
                            onOpenClaims: () => _tabs.animateTo(2),
                            onOpenNetwork: () => _tabs.animateTo(3),
                          ),
                          _VisitsTab(
                            today: _list(visits['today']),
                            last7: last7,
                            trend: _list(visits['trend_7d']),
                            byType: _list(visits['by_type']),
                            n: _n,
                          ),
                          _ClaimsTab(
                            claims: claims,
                            byStatus: _list(claims['by_status']),
                            bySource: _list(claims['by_source']),
                            money: _money,
                            n: _n,
                          ),
                          _NetworkTab(
                            partners: partners,
                            queue: queue,
                            byType: _list(partners['by_type']),
                            n: _n,
                            onCoverage: () => context.push('/admin/network'),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.last7,
    required this.claims,
    required this.partners,
    required this.queue,
    required this.programs,
    required this.alertsOpen,
    required this.audit24h,
    required this.note,
    required this.money,
    required this.n,
    required this.onOpenVisits,
    required this.onOpenClaims,
    required this.onOpenNetwork,
  });

  final Map<String, dynamic> last7;
  final Map<String, dynamic> claims;
  final Map<String, dynamic> partners;
  final Map<String, dynamic> queue;
  final int programs;
  final int alertsOpen;
  final int audit24h;
  final String? note;
  final String Function(dynamic) money;
  final int Function(dynamic) n;
  final VoidCallback onOpenVisits;
  final VoidCallback onOpenClaims;
  final VoidCallback onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 600;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        GridView.count(
          crossAxisCount: narrow ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            AdminKpiCard(
              label: 'Visits 7d',
              value: '${n(last7['total'])}',
              icon: Icons.event_available_rounded,
              color: AdminPalette.blue,
            ),
            AdminKpiCard(
              label: 'Claims open',
              value: '${n(claims['open'])}',
              icon: Icons.receipt_long_rounded,
              color: AdminPalette.gold,
            ),
            AdminKpiCard(
              label: 'Partners',
              value: '${n(partners['total'])}',
              icon: Icons.hub_rounded,
              color: AdminPalette.violet,
            ),
            AdminKpiCard(
              label: 'Waiting now',
              value: '${n(queue['patients_waiting'])}',
              icon: Icons.graphic_eq_rounded,
              color: AdminPalette.cyan,
            ),
          ],
        ).animate().fadeIn(duration: 400.ms),
        const SizedBox(height: 16),
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('National snapshot', style: adminSerif(size: 18)),
              const SizedBox(height: 10),
              _line('Completed (7d)', '${n(last7['completed'])}'),
              _line('Missed / cancelled', '${n(last7['missed'])} / ${n(last7['cancelled'])}'),
              _line('Claims paid (30d)', money(claims['paid_30d_amount'])),
              _line(
                'Regions covered',
                '${n(partners['regions_covered'])}/${n(partners['regions_total'])}',
              ),
              _line('Consulting now', '${n(queue['consulting_now'])}'),
              _line('Care programs active', '$programs'),
              _line('Open risk alerts', '$alertsOpen'),
              _line('Audit writes (24h)', '$audit24h'),
              if (note != null && note!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(note!, style: adminSans(size: 11, color: AdminPalette.mute, height: 1.4)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('Visits detail', onOpenVisits, AdminPalette.blue),
            _chip('Claims rollup', onOpenClaims, AdminPalette.gold),
            _chip('Network & queue', onOpenNetwork, AdminPalette.cyan),
          ],
        ),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: adminSans(size: 13, color: AdminPalette.mute))),
          Text(value, style: adminSans(size: 13, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap, Color color) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.14),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      label: Text(label, style: adminSans(size: 12, weight: FontWeight.w700, color: color)),
    );
  }
}

class _VisitsTab extends StatelessWidget {
  const _VisitsTab({
    required this.today,
    required this.last7,
    required this.trend,
    required this.byType,
    required this.n,
  });

  final List<Map<String, dynamic>> today;
  final Map<String, dynamic> last7;
  final List<Map<String, dynamic>> trend;
  final List<Map<String, dynamic>> byType;
  final int Function(dynamic) n;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Last 7 days', style: adminSerif(size: 18)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _mini('Total', '${n(last7['total'])}', AdminPalette.blue),
                  const SizedBox(width: 8),
                  _mini('Done', '${n(last7['completed'])}', AdminPalette.lime),
                  const SizedBox(width: 8),
                  _mini('Open', '${n(last7['open'])}', AdminPalette.gold),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily trend', style: adminSerif(size: 18)),
              const SizedBox(height: 8),
              if (trend.isEmpty)
                Text('No visits in window', style: adminSans(color: AdminPalette.mute))
              else
                ...trend.map(
                  (r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r['day']?.toString() ?? '', style: adminSans(weight: FontWeight.w600)),
                    trailing: Text(
                      '${n(r['completed'])}/${n(r['total'])} done',
                      style: adminSans(size: 12, color: AdminPalette.mute),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today by status', style: adminSerif(size: 18)),
              const SizedBox(height: 8),
              if (today.isEmpty)
                Text('No visits today', style: adminSans(color: AdminPalette.mute))
              else
                ...today.map(
                  (r) => _kv(r['status']?.toString() ?? '—', '${n(r['count'])}'),
                ),
              const SizedBox(height: 12),
              Text('Booking type (7d)', style: adminSans(weight: FontWeight.w800)),
              const SizedBox(height: 6),
              ...byType.map(
                (r) => _kv(r['booking_type']?.toString() ?? '—', '${n(r['count'])}'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mini(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: adminSans(size: 10, weight: FontWeight.w800, color: AdminPalette.mute)),
            const SizedBox(height: 4),
            Text(value, style: adminSerif(size: 22, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: adminSans(color: AdminPalette.mute))),
          Text(v, style: adminSans(weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ClaimsTab extends StatelessWidget {
  const _ClaimsTab({
    required this.claims,
    required this.byStatus,
    required this.bySource,
    required this.money,
    required this.n,
  });

  final Map<String, dynamic> claims;
  final List<Map<String, dynamic>> byStatus;
  final List<Map<String, dynamic>> bySource;
  final String Function(dynamic) money;
  final int Function(dynamic) n;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            AdminKpiCard(
              label: 'All claims',
              value: '${n(claims['total'])}',
              icon: Icons.folder_copy_rounded,
              color: AdminPalette.violet,
            ),
            AdminKpiCard(
              label: 'Open / queried',
              value: '${n(claims['open'])}',
              icon: Icons.pending_actions_rounded,
              color: AdminPalette.gold,
            ),
            AdminKpiCard(
              label: 'Paid count',
              value: '${n(claims['paid'])}',
              icon: Icons.verified_rounded,
              color: AdminPalette.lime,
            ),
            AdminKpiCard(
              label: 'Paid 30d GHS',
              value: '${(claims['paid_30d_amount'] is num ? (claims['paid_30d_amount'] as num).toInt() : n(claims['paid_30d_amount']))}',
              icon: Icons.payments_rounded,
              color: AdminPalette.cyan,
            ),
          ],
        ),
        const SizedBox(height: 14),
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By status', style: adminSerif(size: 18)),
              const SizedBox(height: 8),
              if (byStatus.isEmpty)
                Text('No claims yet', style: adminSans(color: AdminPalette.mute))
              else
                ...byStatus.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(r['status']?.toString() ?? '—',
                              style: adminSans(weight: FontWeight.w600)),
                        ),
                        Text('${n(r['count'])} · ${money(r['amount'])}',
                            style: adminSans(size: 12, color: AdminPalette.mute)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By source', style: adminSerif(size: 18)),
              const SizedBox(height: 8),
              ...bySource.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r['source']?.toString() ?? '—',
                            style: adminSans(weight: FontWeight.w600)),
                      ),
                      Text('${n(r['count'])} · ${money(r['amount'])}',
                          style: adminSans(size: 12, color: AdminPalette.mute)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cross-tenant rollup for admin only. Insurer and corporate desks stay org-scoped.',
                style: adminSans(size: 11, color: AdminPalette.mute, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NetworkTab extends StatelessWidget {
  const _NetworkTab({
    required this.partners,
    required this.queue,
    required this.byType,
    required this.n,
    required this.onCoverage,
  });

  final Map<String, dynamic> partners;
  final Map<String, dynamic> queue;
  final List<Map<String, dynamic>> byType;
  final int Function(dynamic) n;
  final VoidCallback onCoverage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Partner network', style: adminSerif(size: 18)),
              const SizedBox(height: 8),
              _kv('Total active', '${n(partners['total'])}'),
              _kv('Online / busy', '${n(partners['online'])} / ${n(partners['busy'])}'),
              _kv(
                'Regions',
                '${n(partners['regions_covered'])} of ${n(partners['regions_total'])}',
              ),
              const SizedBox(height: 8),
              ...byType.map(
                (r) => _kv(r['type']?.toString() ?? '—', '${n(r['count'])}'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onCoverage,
                icon: const Icon(Icons.public_rounded, size: 18),
                label: const Text('Open coverage map'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Live queue', style: adminSerif(size: 18)),
              const SizedBox(height: 8),
              _kv('Patients waiting', '${n(queue['patients_waiting'])}'),
              _kv('Consulting now', '${n(queue['consulting_now'])}'),
              _kv('Doctors online', '${n(queue['doctors_online'])}'),
              _kv('Avg wait (min)', '${n(queue['avg_wait'])}'),
              _kv('Completed today', '${n(queue['completed_today'])}'),
              _kv('Missed today', '${n(queue['missed_today'])}'),
              _kv('Pending labs', '${n(queue['pending_labs'])}'),
              _kv('Pending scans', '${n(queue['pending_scans'])}'),
              _kv('Pending pharmacy', '${n(queue['pending_pharmacy'])}'),
              _kv('Open referrals', '${n(queue['open_referrals'])}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: adminSans(color: AdminPalette.mute))),
          Text(v, style: adminSans(weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
