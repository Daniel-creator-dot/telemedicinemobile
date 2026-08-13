import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../patient/care_repository.dart';

class InsuranceHomeScreen extends StatefulWidget {
  const InsuranceHomeScreen({super.key});

  @override
  State<InsuranceHomeScreen> createState() => _InsuranceHomeScreenState();
}

class _InsuranceHomeScreenState extends State<InsuranceHomeScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().insuranceWorkbench();
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data[key] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final insurer = _data['insurer'] as Map<String, dynamic>? ?? {};
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(insurer['name']?.toString() ?? 'Insurance', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () async {
              await session.clear();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${insurer['plan_name'] ?? 'Plan'} · ${insurer['coverage_percent'] ?? 80}% cover · copay GHS ${insurer['copay_amount'] ?? 10}',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Preauths')),
                    ButtonSegment(value: 1, label: Text('Claims')),
                    ButtonSegment(value: 2, label: Text('Policies')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
                const SizedBox(height: 8),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  Widget _body() {
    if (_tab == 2) {
      final policies = _list('policies');
      return ListView(
        padding: const EdgeInsets.all(16),
        children: policies
            .map(
              (p) => Card(
                child: ListTile(
                  title: Text('${p['full_name']} · ${p['policy_number']}'),
                  subtitle: Text('${p['patient_code'] ?? ''} · ${p['status']}'),
                ),
              ),
            )
            .toList(),
      );
    }
    if (_tab == 0) {
      final rows = _list('preauths');
      return ListView(
        padding: const EdgeInsets.all(16),
        children: rows.map((r) {
          final status = r['status']?.toString() ?? 'pending';
          return Card(
            child: ListTile(
              title: Text('${r['preauth_code']} · ${r['full_name']}'),
              subtitle: Text('${r['service'] ?? 'consult'} · GHS ${r['requested_amount']} · $status'),
              trailing: status == 'pending'
                  ? FilledButton(
                      onPressed: () async {
                        await context.read<CareRepository>().updatePreauth(r['id'] as int, {
                          'status': 'approved',
                          'approved_amount': r['requested_amount'],
                        });
                        _load();
                      },
                      child: const Text('Approve'),
                    )
                  : Text(status),
            ),
          );
        }).toList(),
      );
    }
    final claims = _list('claims');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: claims.map((c) {
        final status = c['status']?.toString() ?? 'submitted';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['claim_code']} · ${c['full_name']}', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                Text('${c['source']} · GHS ${c['amount']} · $status'),
                if (status == 'submitted' || status == 'approved')
                  Wrap(
                    spacing: 8,
                    children: [
                      if (status == 'submitted')
                        FilledButton(
                          onPressed: () async {
                            await context.read<CareRepository>().updateClaim(c['id'] as int, {'status': 'approved'});
                            _load();
                          },
                          child: const Text('Approve'),
                        ),
                      FilledButton(
                        onPressed: () async {
                          await context.read<CareRepository>().updateClaim(c['id'] as int, {'status': 'paid'});
                          _load();
                        },
                        child: const Text('Mark paid'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await context.read<CareRepository>().updateClaim(c['id'] as int, {'status': 'rejected'});
                          _load();
                        },
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
