import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class ConsentsScreen extends StatefulWidget {
  const ConsentsScreen({super.key});

  @override
  State<ConsentsScreen> createState() => _ConsentsScreenState();
}

class _ConsentsScreenState extends State<ConsentsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  static const _catalog = [
    ('telemedicine', 'Telemedicine care', 'Receive clinical services by video or chat.'),
    ('data_processing', 'Health data processing', 'Store and use your record to deliver care.'),
    ('communication', 'Messages', 'SMS, email, and push about visits and results.'),
    ('sharing', 'Care-team sharing', 'Share relevant notes with labs, pharmacy, and specialists on the network.'),
    ('ai_assist', 'Assistive AI drafts', 'Allow template or optional LLM drafts. Never a diagnosis.'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await context.read<CareRepository>().myConsents();
      if (mounted) setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _accepted(String type) {
    final matches = _rows.where((r) => r['consent_type']?.toString() == type);
    if (matches.isEmpty) return false;
    return matches.first['accepted'] == true;
  }

  Future<void> _set(String type, bool value) async {
    await context.read<CareRepository>().saveConsent(type, accepted: value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: AppBar(
        title: Text('Consents', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFF6F3EE),
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'You can change these at any time. They are timestamped on your record.',
                  style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
                ),
                const SizedBox(height: 16),
                ..._catalog.map((c) {
                  final on = _accepted(c.$1);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DigiCard(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: on,
                        onChanged: (v) => _set(c.$1, v),
                        title: Text(c.$2, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
                        subtitle: Text(c.$3, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate, height: 1.35)),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
