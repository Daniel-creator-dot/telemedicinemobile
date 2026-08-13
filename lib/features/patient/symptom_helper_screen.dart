import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class SymptomHelperScreen extends StatefulWidget {
  const SymptomHelperScreen({super.key});

  @override
  State<SymptomHelperScreen> createState() => _SymptomHelperScreenState();
}

class _SymptomHelperScreenState extends State<SymptomHelperScreen> {
  final _complaint = TextEditingController();
  final _symptoms = TextEditingController();
  Map<String, dynamic>? _result;
  bool _loading = false;

  @override
  void dispose() {
    _complaint.dispose();
    _symptoms.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_complaint.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().aiAssist({
        'mode': 'symptoms',
        'complaint': _complaint.text.trim(),
        'symptoms': _symptoms.text.trim(),
      });
      setState(() => _result = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Helper unavailable: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = ((_result?['questions'] as List?) ?? []).map((e) => e.toString()).toList();
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Symptom helper', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _result?['disclaimer']?.toString() ??
                  'Assistive only. Not a diagnosis and not medical advice. Seek emergency care for chest pain, severe breathing difficulty, stroke signs, or heavy bleeding.',
              style: GoogleFonts.roboto(fontSize: 13, color: const Color(0xFF92400E)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _complaint,
            decoration: const InputDecoration(labelText: 'What is bothering you?', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _symptoms,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Other symptoms (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _run,
            child: Text(_loading ? 'Preparing…' : 'Prepare questions for my visit'),
          ),
          if (questions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Bring these to your clinician', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...questions.map((q) => ListTile(leading: const Icon(Icons.help_outline), title: Text(q))),
            if (_result?['next_step'] != null)
              Text(_result!['next_step'].toString(), style: GoogleFonts.roboto(color: digiSlate)),
            if (_result?['llm_text'] != null) ...[
              const SizedBox(height: 12),
              Text(_result!['llm_text'].toString(), style: GoogleFonts.roboto(fontSize: 13)),
            ],
          ],
        ],
      ),
    );
  }
}
