import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class FamilyChartScreen extends StatefulWidget {
  const FamilyChartScreen({super.key, required this.patientId, this.name});

  final int patientId;
  final String? name;

  @override
  State<FamilyChartScreen> createState() => _FamilyChartScreenState();
}

class _FamilyChartScreenState extends State<FamilyChartScreen> {
  Map<String, dynamic> _chart = {};
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
      final chart = await context.read<CareRepository>().familyChart(widget.patientId);
      if (!mounted) return;
      setState(() {
        _chart = chart;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this dependent chart.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = (_chart['patient'] as Map?)?.cast<String, dynamic>() ?? {};
    final apts = ((_chart['appointments'] as List?) ?? []).whereType<Map>().toList();
    final programs = ((_chart['programs'] as List?) ?? []).whereType<Map>().toList();
    final docs = ((_chart['documents'] as List?) ?? []).whereType<Map>().toList();
    final alerts = ((_chart['alerts'] as List?) ?? []).whereType<Map>().toList();

    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text(widget.name ?? patient['full_name']?.toString() ?? 'Dependent chart',
            style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${patient['full_name'] ?? ''} · ${patient['patient_code'] ?? ''}',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    Text(
                      '${patient['sex'] ?? ''} · ${patient['date_of_birth'] ?? 'DOB not set'}',
                      style: GoogleFonts.roboto(color: digiSlate),
                    ),
                    const SizedBox(height: 16),
                    _section('Visits', apts, (e) => '${e['appointment_date'] ?? ''} · ${e['status'] ?? ''} · ${e['reason'] ?? e['consult_type'] ?? ''}'),
                    _section('Care programs', programs, (e) => '${e['condition'] ?? ''} · ${e['status'] ?? ''}'),
                    _section('Vault', docs, (e) => '${e['title'] ?? ''} · ${e['kind'] ?? ''}'),
                    _section('Alerts', alerts, (e) => '${e['severity'] ?? ''} · ${e['title'] ?? ''}'),
                  ],
                ),
    );
  }

  Widget _section(String title, List<Map> rows, String Function(Map) line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Text('None yet', style: GoogleFonts.roboto(color: digiSlate, fontSize: 13))
          else
            ...rows.take(12).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(line(e), style: GoogleFonts.roboto(fontSize: 13, height: 1.35)),
                  ),
                ),
        ],
      ),
    );
  }
}
