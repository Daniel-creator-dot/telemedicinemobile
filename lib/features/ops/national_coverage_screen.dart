import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class NationalCoverageScreen extends StatefulWidget {
  const NationalCoverageScreen({super.key});

  @override
  State<NationalCoverageScreen> createState() => _NationalCoverageScreenState();
}

class _NationalCoverageScreenState extends State<NationalCoverageScreen> {
  Map<String, dynamic> _national = {};
  Map<String, dynamic> _coverage = {};
  List<Map<String, dynamic>> _audit = [];
  List<Map<String, dynamic>> _alerts = [];
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
      final national = await care.nationalOps();
      final coverage = await care.networkCoverage();
      final audit = await care.auditLog();
      final alerts = await care.riskAlerts();
      if (!mounted) return;
      setState(() {
        _national = national;
        _coverage = coverage;
        _audit = audit;
        _alerts = alerts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'National ops data is available to medical operations and admin only.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = (_coverage['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final regions = ((_coverage['regions'] as List?) ?? []).whereType<Map>().toList();

    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('National network', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
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
                      '${totals['partners'] ?? 0} partners · ${totals['regions_with_partners'] ?? 0}/${totals['regions'] ?? 16} regions · ${_national['audit_last_24h'] ?? 0} audited writes (24h)',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w700, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Text('Open risk alerts', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (_alerts.isEmpty)
                      Text('No open alerts', style: GoogleFonts.roboto(color: digiSlate))
                    else
                      ..._alerts.take(12).map(
                            (a) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(a['title']?.toString() ?? 'Alert', style: GoogleFonts.roboto(fontWeight: FontWeight.w600)),
                              subtitle: Text('${a['full_name'] ?? a['patient_code'] ?? ''} · ${a['severity'] ?? ''}'),
                            ),
                          ),
                    const SizedBox(height: 16),
                    Text('Regional footprint', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
                    ...regions.map(
                      (r) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(r['name']?.toString() ?? ''),
                        trailing: Text('${r['partners'] ?? 0}'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Recent audit (append-only)', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ..._audit.take(20).map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${a['created_at'] ?? ''} · ${a['username'] ?? a['role'] ?? ''} · ${a['action'] ?? ''}',
                              style: GoogleFonts.roboto(fontSize: 12, color: digiSlate),
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}
