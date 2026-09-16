import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({super.key});

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String _receiptFilter = 'unreconciled';
  Timer? _poll;
  late final TabController _tabs;

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
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().financeDashboard();
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

  List<Map<String, dynamic>> get _filteredReceipts {
    final all = _list('payments');
    switch (_receiptFilter) {
      case 'unreconciled':
        return all
            .where((p) => p['status']?.toString() == 'paid' && p['reconciled_at'] == null)
            .toList();
      case 'reconciled':
        return all
            .where((p) => p['status']?.toString() == 'paid' && p['reconciled_at'] != null)
            .toList();
      case 'demo':
        return all.where((p) => p['gateway']?.toString() == 'demo').toList();
      case 'paystack':
        return all.where((p) => p['gateway']?.toString() == 'paystack').toList();
      case 'refunded':
        return all.where((p) => p['status']?.toString() == 'refunded').toList();
      default:
        return all;
    }
  }

  Future<void> _actPayment(Map<String, dynamic> row, String action, {String? notes}) async {
    final id = _idOf(row);
    if (id == 0) return;
    final care = context.read<CareRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await care.updateFinancePayment(id, action, notes: notes);
      if (!mounted) return;
      final label = switch (action) {
        'reconcile' => 'marked reconciled',
        'unreconcile' => 'returned to open queue',
        'refund' => 'refunded',
        _ => 'updated',
      };
      messenger.showSnackBar(
        SnackBar(content: Text('${row['reference'] ?? 'Receipt'} $label')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Payment update failed: $e')));
    }
  }

  Future<void> _refundPayment(Map<String, dynamic> row) async {
    final notes = TextEditingController(
      text: row['refund_notes']?.toString().isNotEmpty == true
          ? row['refund_notes'].toString()
          : 'Patient requested refund before consult.',
    );
    final gateway = row['gateway']?.toString() ?? 'unknown';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gateway == 'paystack'
                  ? 'Live Paystack charges attempt a Paystack refund; demo / seed refs stay local.'
                  : 'Demo gateway refunds are recorded locally (no Paystack call).',
              style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Refund reason',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Refund')),
        ],
      ),
    );
    final text = notes.text;
    notes.dispose();
    if (ok != true || !mounted) return;
    await _actPayment(row, 'refund', notes: text);
  }

  Future<void> _runSettlements() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await context.read<CareRepository>().runSettlements();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(created.isEmpty ? 'No new settlements' : 'Created ${created.length} settlement(s)')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Settlements failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: 'Finance',
        subtitle: 'Receipts · reconcile · settlements',
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
                    Tab(text: 'Receipts'),
                    Tab(text: 'Settlements'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _OverviewTab(
                        stats: _stats,
                        note: _data['note']?.toString(),
                        onOpenReceipts: () => _tabs.animateTo(1),
                        onOpenSettlements: () => _tabs.animateTo(2),
                        onRunSettlements: _runSettlements,
                      ),
                      _ReceiptsTab(
                        receipts: _filteredReceipts,
                        filter: _receiptFilter,
                        onFilter: (f) => setState(() => _receiptFilter = f),
                        onReconcile: (r) => _actPayment(r, 'reconcile'),
                        onUnreconcile: (r) => _actPayment(r, 'unreconcile'),
                        onRefund: _refundPayment,
                        onRefresh: _load,
                      ),
                      _SettlementsTab(
                        settlements: _list('settlements'),
                        earnings: _list('earnings'),
                        onRun: _runSettlements,
                        onPay: (s) async {
                          final id = _idOf(s);
                          if (id == 0) return;
                          await context.read<CareRepository>().updateSettlement(id, 'paid');
                          await _load(silent: true);
                        },
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
    required this.onOpenReceipts,
    required this.onOpenSettlements,
    required this.onRunSettlements,
    this.note,
  });

  final Map<String, dynamic> stats;
  final String? note;
  final VoidCallback onOpenReceipts;
  final VoidCallback onOpenSettlements;
  final VoidCallback onRunSettlements;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Collections desk',
          style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 4),
        Text(
          'Paid visit receipts · demo + Paystack · partner settlements',
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
              child: StatTile(label: 'Copay collected', value: 'GHS ${stats['copay_collected'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Covered billed', value: 'GHS ${stats['covered_billed'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(
                label: 'Unreconciled',
                value: '${stats['unreconciled_receipts'] ?? 0}',
                accent: digiGold,
              ),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Reconciled', value: '${stats['reconciled_receipts'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Refunded', value: '${stats['refunded_receipts'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Demo collected', value: 'GHS ${stats['demo_collected'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Paystack collected', value: 'GHS ${stats['paystack_collected'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Doctor pay due', value: 'GHS ${stats['doctor_pay_due'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Partner pay due', value: 'GHS ${stats['partner_pay_due'] ?? 0}'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: digiForest),
              onPressed: onOpenReceipts,
              child: const Text('Open receipts'),
            ),
            OutlinedButton(
              onPressed: onOpenSettlements,
              child: const Text('Settlements'),
            ),
            OutlinedButton(
              onPressed: onRunSettlements,
              child: const Text('Run settlements'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceiptsTab extends StatelessWidget {
  const _ReceiptsTab({
    required this.receipts,
    required this.filter,
    required this.onFilter,
    required this.onReconcile,
    required this.onUnreconcile,
    required this.onRefund,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> receipts;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<Map<String, dynamic>> onReconcile;
  final ValueChanged<Map<String, dynamic>> onUnreconcile;
  final ValueChanged<Map<String, dynamic>> onRefund;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              for (final entry in const [
                ('unreconciled', 'Open'),
                ('reconciled', 'Reconciled'),
                ('demo', 'Demo'),
                ('paystack', 'Paystack'),
                ('refunded', 'Refunded'),
                ('all', 'All'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: filter == entry.$1,
                    onSelected: (_) => onFilter(entry.$1),
                    selectedColor: digiGold.withValues(alpha: 0.35),
                    labelStyle: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      color: digiInk,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onRefresh(),
            child: receipts.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(
                          'No receipts in this filter',
                          style: GoogleFonts.dmSans(color: digiSlate),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: receipts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = receipts[i];
                      final status = p['status']?.toString() ?? 'paid';
                      final gateway = p['gateway']?.toString() ?? 'unknown';
                      final reconciled = p['reconciled_at'] != null;
                      final amount = p['copay_amount'] ?? p['amount'] ?? 0;
                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: digiForest.withValues(alpha: 0.08)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p['patient_name']?.toString() ?? 'Patient',
                                      style: GoogleFonts.dmSans(
                                        fontWeight: FontWeight.w700,
                                        color: digiInk,
                                      ),
                                    ),
                                  ),
                                  _GatewayChip(gateway: gateway),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${p['apt_code'] ?? 'Visit'} · GHS $amount · ${p['reference'] ?? ''}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                              ),
                              if (p['coverage_source'] != null)
                                Text(
                                  'Cover ${p['coverage_source']} · covered GHS ${p['covered_amount'] ?? 0}',
                                  style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                                ),
                              Text(
                                status == 'refunded'
                                    ? 'Refunded${p['refund_notes'] != null ? ' · ${p['refund_notes']}' : ''}'
                                    : reconciled
                                        ? 'Reconciled${p['reconciled_by_name'] != null ? ' by ${p['reconciled_by_name']}' : ''}'
                                        : 'Awaiting reconciliation',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: status == 'refunded'
                                      ? Colors.red.shade700
                                      : reconciled
                                          ? digiForest
                                          : digiGold,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (status == 'paid' && !reconciled)
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: digiForest,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => onReconcile(p),
                                      child: const Text('Reconcile'),
                                    ),
                                  if (status == 'paid' && reconciled)
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                      onPressed: () => onUnreconcile(p),
                                      child: const Text('Unreconcile'),
                                    ),
                                  if (status == 'paid')
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => onRefund(p),
                                      child: const Text('Refund'),
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

class _GatewayChip extends StatelessWidget {
  const _GatewayChip({required this.gateway});

  final String gateway;

  @override
  Widget build(BuildContext context) {
    final label = switch (gateway) {
      'demo' => 'Demo',
      'paystack' => 'Paystack',
      'coverage' => 'Cover',
      _ => gateway,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: gateway == 'demo' ? digiGold.withValues(alpha: 0.25) : digiForest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: digiInk),
      ),
    );
  }
}

class _SettlementsTab extends StatelessWidget {
  const _SettlementsTab({
    required this.settlements,
    required this.earnings,
    required this.onRun,
    required this.onPay,
  });

  final List<Map<String, dynamic>> settlements;
  final List<Map<String, dynamic>> earnings;
  final VoidCallback onRun;
  final ValueChanged<Map<String, dynamic>> onPay;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: digiForest),
          onPressed: onRun,
          child: const Text('Run partner / clinician settlements'),
        ),
        const SizedBox(height: 16),
        Text(
          'Settlements',
          style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700, fontSize: 18, color: digiInk),
        ),
        const SizedBox(height: 8),
        if (settlements.isEmpty)
          Text('No settlements yet', style: GoogleFonts.dmSans(color: digiSlate)),
        ...settlements.map((s) {
          final status = s['status']?.toString() ?? 'pending';
          return Card(
            elevation: 0,
            color: Colors.white,
            child: ListTile(
              title: Text('${s['settlement_code']} · ${s['payee_name']}'),
              subtitle: Text('${s['payee_type']} · GHS ${s['amount']} · $status'),
              trailing: status == 'pending'
                  ? FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: digiForest),
                      onPressed: () => onPay(s),
                      child: const Text('Pay'),
                    )
                  : const Icon(Icons.check_circle, color: Colors.green),
            ),
          );
        }),
        const SizedBox(height: 16),
        Text(
          'Clinician earnings',
          style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700, fontSize: 18, color: digiInk),
        ),
        ...earnings.map(
          (e) => ListTile(
            title: Text('${e['doctor_name']} · GHS ${e['amount']}'),
            subtitle: Text('${e['apt_code'] ?? ''} · ${e['status']}'),
          ),
        ),
      ],
    );
  }
}
