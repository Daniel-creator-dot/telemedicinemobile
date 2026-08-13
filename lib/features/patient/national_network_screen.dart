import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class NationalNetworkScreen extends StatefulWidget {
  const NationalNetworkScreen({super.key});

  @override
  State<NationalNetworkScreen> createState() => _NationalNetworkScreenState();
}

class _NationalNetworkScreenState extends State<NationalNetworkScreen> {
  Map<String, dynamic> _coverage = {};
  List<Map<String, dynamic>> _nearby = [];
  List<Map<String, dynamic>> _alerts = [];
  String _type = 'pharmacy';
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
      final care = context.read<CareRepository>();
      final coverage = await care.networkCoverage();
      final nearby = await care.nationalNearby(type: _type);
      List<Map<String, dynamic>> alerts = [];
      try {
        await care.scanRiskAlerts();
        alerts = await care.riskAlerts();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _coverage = coverage;
        _nearby = nearby;
        _alerts = alerts.where((a) => a['status']?.toString() != 'closed').toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the national network.';
        _loading = false;
      });
    }
  }

  Future<void> _setType(String type) async {
    setState(() => _type = type);
    try {
      final nearby = await context.read<CareRepository>().nationalNearby(type: type);
      if (mounted) setState(() => _nearby = nearby);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final totals = (_coverage['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final regions = ((_coverage['regions'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Ghana care network', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'One patient. One journey. Partners in every region.',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 20, color: digiInk),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${totals['partners'] ?? 0} active partners across ${totals['regions_with_partners'] ?? 0} of ${totals['regions'] ?? 16} regions. Nearby matches use your profile region (or device coordinates if you pass them).',
                      style: GoogleFonts.roboto(color: digiSlate, height: 1.4),
                    ),
                    if (_alerts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ..._alerts.take(3).map(
                            (a) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${a['title'] ?? 'Alert'}\n${a['detail'] ?? ''}',
                                style: GoogleFonts.roboto(fontSize: 13, color: const Color(0xFF92400E)),
                              ),
                            ),
                          ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final t in const ['pharmacy', 'laboratory', 'imaging', 'hospital'])
                          ChoiceChip(
                            label: Text(t),
                            selected: _type == t,
                            onSelected: (_) => _setType(t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Nearest $_type', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (_nearby.isEmpty)
                      Text('No geo-tagged $_type yet. Coverage by region is below.', style: GoogleFonts.roboto(color: digiSlate)),
                    ..._nearby.take(8).map((p) {
                      final km = p['distance_km'];
                      return Card(
                        child: ListTile(
                          title: Text(p['name']?.toString() ?? 'Partner', style: GoogleFonts.roboto(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${p['town'] ?? ''} · ${p['region'] ?? ''}${km != null ? ' · $km km' : ''}\n${p['hours'] ?? ''} · ${p['services'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: p['phone'] == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.call_outlined),
                                  onPressed: () => launchUrl(Uri.parse('tel:${p['phone']}')),
                                ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    Text('Coverage by region', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ...regions.map((r) {
                      final n = (r['partners'] as num?)?.toInt() ?? 0;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(r['name']?.toString() ?? '', style: GoogleFonts.roboto(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          'Pharmacy ${r['pharmacy'] ?? 0} · Lab ${r['laboratory'] ?? 0} · Imaging ${r['imaging'] ?? 0} · Hospital ${r['hospital'] ?? 0}',
                          style: GoogleFonts.roboto(fontSize: 12, color: digiSlate),
                        ),
                        trailing: Text('$n', style: GoogleFonts.roboto(fontWeight: FontWeight.w800, color: digiViolet)),
                      );
                    }),
                  ],
                ),
    );
  }
}
