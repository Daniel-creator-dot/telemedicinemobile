import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class PhasesScreen extends StatefulWidget {
  const PhasesScreen({super.key});

  @override
  State<PhasesScreen> createState() => _PhasesScreenState();
}

class _PhasesScreenState extends State<PhasesScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;

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
      final data = await context.read<CareRepository>().phasesMe();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your care phases.';
        _loading = false;
      });
    }
  }

  Future<void> _scanAlerts() async {
    try {
      await context.read<CareRepository>().scanRiskAlerts();
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final phases = ((_data['phases'] as List?) ?? []).whereType<Map>().toList();
    final loop = (_data['loop'] as Map?) ?? {};
    final alerts = ((_data['alerts'] as List?) ?? []).whereType<Map>().toList();
    final elig = (_data['eligibility'] as Map?) ?? {};

    return Scaffold(
      backgroundColor: digiPaper,
      appBar: AppBar(
        title: Text('Care phases', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: digiPaper,
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: digiForest))
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      Text(
                        'One record. Five phases.',
                        style: GoogleFonts.sourceSerif4(fontSize: 30, fontWeight: FontWeight.w600, height: 1.15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Consult, network, cover, household, nation — the same journey the platform was built to keep closed.',
                        style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
                      ),
                      const SizedBox(height: 20),
                      ...phases.map((p) => _phaseCard(p)),
                      const SizedBox(height: 12),
                      SectionLabel('Closed loop'),
                      const SizedBox(height: 8),
                      Text(
                        'Prescriptions, labs, imaging and referrals stay on this chart until they return.',
                        style: GoogleFonts.dmSans(color: digiSlate, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      _loopSection('Pharmacy', Icons.local_pharmacy_outlined, (loop['prescriptions'] as List?) ?? [],
                          (r) => r['medication_name'] ?? 'Prescription',
                          (r) {
                            final bits = <String>[
                              if ((r['pharmacy_name'] ?? '').toString().isNotEmpty) r['pharmacy_name'].toString(),
                              if ((r['dispense_status'] ?? r['status'] ?? '').toString().isNotEmpty)
                                (r['dispense_status'] ?? r['status']).toString(),
                            ];
                            return bits.isEmpty ? null : bits.join(' · ');
                          }),
                      _loopSection('Laboratory', Icons.biotech_outlined, (loop['labs'] as List?) ?? [],
                          (r) => r['test_name'] ?? 'Lab request',
                          (r) {
                            final bits = <String>[
                              if ((r['partner_name'] ?? '').toString().isNotEmpty) r['partner_name'].toString(),
                              if ((r['status'] ?? '').toString().isNotEmpty) r['status'].toString(),
                              if ((r['results'] ?? '').toString().isNotEmpty) 'result ready',
                            ];
                            return bits.isEmpty ? null : bits.join(' · ');
                          }),
                      _loopSection('Imaging', Icons.radar_outlined, (loop['scans'] as List?) ?? [],
                          (r) => r['scan_type'] ?? 'Scan',
                          (r) {
                            final bits = <String>[
                              if ((r['partner_name'] ?? '').toString().isNotEmpty) r['partner_name'].toString(),
                              if ((r['status'] ?? '').toString().isNotEmpty) r['status'].toString(),
                            ];
                            return bits.isEmpty ? null : bits.join(' · ');
                          }),
                      _loopSection('Referrals', Icons.assignment_ind_outlined, (loop['referrals'] as List?) ?? [],
                          (r) => r['specialty'] ?? r['referral_code'] ?? 'Referral',
                          (r) {
                            final bits = <String>[
                              if ((r['org_name'] ?? '').toString().isNotEmpty) r['org_name'].toString(),
                              if ((r['status'] ?? '').toString().isNotEmpty) r['status'].toString(),
                            ];
                            return bits.isEmpty ? null : bits.join(' · ');
                          }),
                      const SizedBox(height: 8),
                      SectionLabel('Risk alerts'),
                      const SizedBox(height: 8),
                      Text(
                        'Rule-based from tracker and overdue program tasks. Assistive only — not a diagnosis.',
                        style: GoogleFonts.dmSans(color: digiSlate, height: 1.4, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _scanAlerts,
                        child: const Text('Scan my chart'),
                      ),
                      const SizedBox(height: 10),
                      if (alerts.isEmpty)
                        Text('No alerts on this household chart.', style: GoogleFonts.dmSans(color: digiSlate))
                      else
                        ...alerts.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DigiCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a['title']?.toString() ?? a['kind']?.toString() ?? 'Alert',
                                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w800)),
                                  Text(
                                    '${a['severity'] ?? a['status'] ?? ''} · ${a['message'] ?? a['body'] ?? a['detail'] ?? ''}',
                                    style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (elig.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DigiCard(
                          onTap: () => context.push('/patient/coverage'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cover now: ${elig['source'] ?? 'self_pay'} · copay GHS ${elig['copay'] ?? 120}',
                                style: GoogleFonts.dmSans(color: digiSlate, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to check insurance or corporate eligibility',
                                style: GoogleFonts.dmSans(color: digiForest, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _phaseCard(Map p) {
    final status = p['status']?.toString() ?? 'ready';
    final live = status == 'live';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DigiCard(
        onTap: () {
          final route = p['route']?.toString();
          if (route != null && route.isNotEmpty && route != '/patient/phases') {
            context.push(route);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: live ? digiForest : const Color(0xFFF3EDE3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${p['id']}',
                style: GoogleFonts.sourceSerif4(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: live ? Colors.white : digiForest,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p['name']} · ${p['title']}',
                    style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(p['summary']?.toString() ?? '', style: GoogleFonts.dmSans(color: digiSlate, height: 1.4, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    live
                        ? '${p['open']} open now'
                        : status == 'active'
                            ? 'On your chart'
                            : 'Ready when you are',
                    style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: live ? digiForest : digiSlate),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loopSection(
    String title,
    IconData icon,
    List items,
    String Function(Map) headline,
    Object? Function(Map) subtitle,
  ) {
    final rows = items.whereType<Map>().toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DigiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: digiForest),
                const SizedBox(width: 8),
                Text(title, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text('None on the chart yet.', style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13))
            else
              ...rows.take(6).map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline(r), style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                      Text('${subtitle(r) ?? ''}', style: GoogleFonts.dmSans(color: digiSlate, fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
