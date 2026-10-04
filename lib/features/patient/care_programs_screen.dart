import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class CareProgramsScreen extends StatefulWidget {
  const CareProgramsScreen({super.key});

  @override
  State<CareProgramsScreen> createState() => _CareProgramsScreenState();
}

class _CareProgramsScreenState extends State<CareProgramsScreen> {
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _mine = [];
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
      final repo = context.read<CareRepository>();
      final results = await Future.wait([
        repo.chronicCatalog(),
        repo.chronicPrograms(),
      ]);
      setState(() {
        _catalog = results[0];
        _mine = results[1];
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Care programs could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<void> _enroll(String key) async {
    try {
      await context.read<CareRepository>().enrollChronic({'program_key': key});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrolled. Reminders will appear in your inbox.')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not enroll: $e')));
      }
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> program, Map<String, dynamic> task) async {
    final next = task['status'] == 'done' ? 'pending' : 'done';
    await context.read<CareRepository>().updateChronicTask(
      program['id'] as int,
      task['id'] as int,
      {'status': next},
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Care programs', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
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
                      'These programs are reminders and check-ins. They are not a diagnosis.',
                      style: GoogleFonts.roboto(color: digiSlate),
                    ),
                    const SizedBox(height: 16),
                    Text('Your programs', style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    if (_mine.isEmpty)
                      const ClinicalEmptyState(
                        icon: Icons.favorite_outline,
                        title: 'Not enrolled yet',
                        message: 'Choose a program below to get daily tasks and review reminders.',
                      )
                    else
                      ..._mine.map(_programCard),
                    const SizedBox(height: 20),
                    Text('Available programs', style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    ..._catalog.map((c) {
                      final enrolled = _mine.any((p) => p['program_key'] == c['key'] && p['status'] == 'active');
                      return Card(
                        child: ListTile(
                          title: Text(c['name']?.toString() ?? '', style: GoogleFonts.roboto(fontWeight: FontWeight.w700)),
                          subtitle: Text(c['summary']?.toString() ?? ''),
                          trailing: enrolled
                              ? const Text('Enrolled')
                              : FilledButton(onPressed: () => _enroll(c['key'].toString()), child: const Text('Enroll')),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }

  Widget _programCard(Map<String, dynamic> program) {
    final tasks = ((program['tasks'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final pct = program['adherence']?['percent'] ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(program['condition']?.toString() ?? 'Program', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
            Text('Adherence $pct% · next review ${program['next_review'] ?? 'not set'}', style: GoogleFonts.roboto(color: digiSlate, fontSize: 12)),
            const SizedBox(height: 8),
            ...tasks.map((t) {
              final done = t['status'] == 'done';
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: done,
                onChanged: (_) => _toggleTask(program, t),
                title: Text(t['title']?.toString() ?? 'Task'),
                subtitle: Text('${t['cadence'] ?? ''} · due ${t['due_on'] ?? ''}'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
