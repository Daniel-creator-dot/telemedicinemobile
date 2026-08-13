import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../patient/care_repository.dart';

class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({super.key});

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().financeDashboard();
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
    final stats = _data['stats'] as Map<String, dynamic>? ?? {};
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Finance', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Collections & settlement', style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _stat('Copay collected', stats['copay_collected']),
                    _stat('Covered billed', stats['covered_billed']),
                    _stat('Doctor pay due', stats['doctor_pay_due']),
                    _stat('Doctor settled', stats['doctor_pay_settled']),
                    _stat('Partner pay due', stats['partner_pay_due']),
                    _stat('Open claims', stats['open_claims']),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await context.read<CareRepository>().runSettlements();
                    _load();
                  },
                  child: const Text('Run partner / clinician settlements'),
                ),
                const SizedBox(height: 16),
                Text('Settlements', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16)),
                ..._list('settlements').map((s) {
                  final status = s['status']?.toString() ?? 'pending';
                  return Card(
                    child: ListTile(
                      title: Text('${s['settlement_code']} · ${s['payee_name']}'),
                      subtitle: Text('${s['payee_type']} · GHS ${s['amount']} · $status'),
                      trailing: status == 'pending'
                          ? FilledButton(
                              onPressed: () async {
                                await context.read<CareRepository>().updateSettlement(s['id'] as int, 'paid');
                                _load();
                              },
                              child: const Text('Pay'),
                            )
                          : const Icon(Icons.check_circle, color: Colors.green),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text('Clinician earnings', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16)),
                ..._list('earnings').map(
                  (e) => ListTile(
                    title: Text('${e['doctor_name']} · GHS ${e['amount']}'),
                    subtitle: Text('${e['apt_code'] ?? ''} · ${e['status']}'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _stat(String label, dynamic value) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value?.toString() ?? '0', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 18)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
