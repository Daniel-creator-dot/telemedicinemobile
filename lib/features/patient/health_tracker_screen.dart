import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class HealthTrackerScreen extends StatefulWidget {
  const HealthTrackerScreen({super.key});

  @override
  State<HealthTrackerScreen> createState() => _HealthTrackerScreenState();
}

class _HealthTrackerScreenState extends State<HealthTrackerScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await context.read<CareRepository>().getTracker();
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final kind = ValueNotifier('blood_pressure');
    final primary = TextEditingController();
    final secondary = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record a measurement', style: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ValueListenableBuilder(
                valueListenable: kind,
                builder: (_, value, __) => DropdownButtonFormField<String>(
                  value: value,
                  items: const [
                    DropdownMenuItem(value: 'blood_pressure', child: Text('Blood pressure')),
                    DropdownMenuItem(value: 'blood_glucose', child: Text('Blood glucose')),
                    DropdownMenuItem(value: 'weight', child: Text('Weight')),
                    DropdownMenuItem(value: 'temperature', child: Text('Temperature')),
                    DropdownMenuItem(value: 'pulse', child: Text('Pulse')),
                    DropdownMenuItem(value: 'spo2', child: Text('Oxygen saturation')),
                  ],
                  onChanged: (v) => kind.value = v ?? 'blood_pressure',
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
              ),
              TextField(controller: primary, decoration: const InputDecoration(labelText: 'Value (e.g. 120 or 5.6)')),
              TextField(controller: secondary, decoration: const InputDecoration(labelText: 'Second value (e.g. diastolic)')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    final units = {
      'blood_pressure': 'mmHg',
      'blood_glucose': 'mmol/L',
      'weight': 'kg',
      'temperature': '°C',
      'pulse': 'bpm',
      'spo2': '%',
    };
    await context.read<CareRepository>().addTracker({
      'kind': kind.value,
      'value_primary': primary.text.trim(),
      if (secondary.text.trim().isNotEmpty) 'value_secondary': secondary.text.trim(),
      'unit': units[kind.value],
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Health tracker', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: digiInk,
        label: const Text('Add reading'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const ClinicalEmptyState(
                  icon: Icons.monitor_heart_outlined,
                  title: 'No readings yet',
                  message: 'Record blood pressure, glucose, weight, temperature, pulse or oxygen saturation.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      final second = r['value_secondary'] != null ? '/${r['value_secondary']}' : '';
                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        title: Text(
                          '${r['kind']}'.replaceAll('_', ' '),
                          style: GoogleFonts.roboto(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${r['recorded_at'] ?? ''}'),
                        trailing: Text(
                          '${r['value_primary']}$second ${r['unit'] ?? ''}',
                          style: GoogleFonts.roboto(fontWeight: FontWeight.w800, color: digiMint),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
