import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';
import 'pay_visit.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  Map<String, dynamic> _data = {};
  Map<String, dynamic> _eligibility = {};
  bool _loading = true;
  String? _error;
  int? _payingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final care = context.read<CareRepository>();
      final billing = await care.myBilling();
      final elig = await care.eligibility();
      if (!mounted) return;
      setState(() {
        _data = billing;
        _eligibility = billing['eligibility'] is Map
            ? Map<String, dynamic>.from(billing['eligibility'] as Map)
            : elig;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load billing.';
        _loading = false;
      });
    }
  }

  Future<void> _pay(int appointmentId) async {
    setState(() => _payingId = appointmentId);
    final result = await payVisitWithPaystack(context, appointmentId: appointmentId);
    if (!mounted) return;
    setState(() => _payingId = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) _load();
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ((_data['receipts'] as List?) ?? []).whereType<Map>().toList();
    final outstanding = ((_data['outstanding'] as List?) ?? []).whereType<Map>().toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: AppBar(
        title: Text('Payments & cover', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFF6F3EE),
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SectionLabel('How this visit is paid'),
                    const SizedBox(height: 8),
                    Text(
                      _data['disclaimer']?.toString() ??
                          'Visit copay uses Paystack (card, MoMo, or bank) when keys are configured. Without keys, the app confirms a demo payment so booking and Consult Now still complete.',
                      style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
                    ),
                    const SizedBox(height: 16),
                    DigiCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Coverage', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(
                            '${_eligibility['source'] ?? 'self_pay'} · copay GHS ${_eligibility['copay'] ?? _eligibility['copay_amount'] ?? 50}',
                            style: GoogleFonts.dmSans(color: digiSlate),
                          ),
                          if (_eligibility['plan_name'] != null)
                            Text(_eligibility['plan_name'].toString(), style: GoogleFonts.dmSans(color: digiSlate)),
                          if (_eligibility['payer_name'] != null)
                            Text(_eligibility['payer_name'].toString(), style: GoogleFonts.dmSans(color: digiSlate)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => context.push('/patient/coverage'),
                            icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                            label: const Text('Check insurance / corporate cover'),
                            style: FilledButton.styleFrom(
                              backgroundColor: digiForest,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => context.push('/patient/membership'),
                            child: const Text('Classic · Premium · Gold · Diamond'),
                          ),
                        ],
                      ),
                    ),
                    if (outstanding.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SectionLabel('Due now'),
                      const SizedBox(height: 8),
                      ...outstanding.map(
                        (o) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DigiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o['service']?.toString() ?? 'Consultation',
                                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${o['date'] ?? ''} ${o['time'] ?? ''} · ${o['status'] ?? ''}',
                                  style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'GHS ${o['copay'] ?? _eligibility['copay'] ?? 50}',
                                  style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: o['id'] == null || _payingId == o['id']
                                      ? null
                                      : () => _pay(int.parse(o['id'].toString())),
                                  icon: const Icon(Icons.payment, size: 16),
                                  label: Text(_payingId == o['id'] ? 'Confirming…' : 'Pay visit copay'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1F4A3A),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SectionLabel('Receipts'),
                    const SizedBox(height: 8),
                    if (receipts.isEmpty)
                      Text('No paid visits yet.', style: GoogleFonts.dmSans(color: digiSlate))
                    else
                      ...receipts.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DigiCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['receipt_no']?.toString() ?? 'Receipt',
                                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w800)),
                                Text(
                                  '${r['service'] ?? 'Consultation'} · ${r['date'] ?? ''} ${r['time'] ?? ''}',
                                  style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'GHS ${r['amount'] ?? 50} · ${r['gateway'] ?? 'paystack'}',
                                  style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(r['note']?.toString() ?? '', style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
