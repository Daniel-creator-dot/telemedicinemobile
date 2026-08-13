import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'book_appointment_dialog.dart';
import 'care_repository.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<Map<String, dynamic>> _members = [];
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
      final rows = await context.read<CareRepository>().getFamily();
      setState(() {
        _members = rows;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not load your family list.';
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final relationship = TextEditingController(text: 'child');
    final dob = TextEditingController();
    final sex = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add dependent'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              TextField(controller: relationship, decoration: const InputDecoration(labelText: 'Relationship (child, spouse, parent)')),
              TextField(controller: dob, decoration: const InputDecoration(labelText: 'Date of birth (YYYY-MM-DD)')),
              TextField(controller: sex, decoration: const InputDecoration(labelText: 'Sex (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (name.text.trim().isEmpty) return;
    try {
      await context.read<CareRepository>().addDependent({
        'full_name': name.text.trim(),
        'relationship': relationship.text.trim(),
        'date_of_birth': dob.text.trim().isEmpty ? null : dob.text.trim(),
        'sex': sex.text.trim().isEmpty ? null : sex.text.trim(),
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Family & dependents', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: digiViolet,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : _members.isEmpty
                  ? ClinicalEmptyState(
                      icon: Icons.family_restroom,
                      title: 'No dependents yet',
                      message: 'Add a child, spouse, or parent so you can book or consult on their behalf.',
                      actionLabel: 'Add dependent',
                      onAction: _add,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = _members[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['full_name']?.toString() ?? 'Dependent', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
                                Text(
                                  '${m['relationship'] ?? ''} · ${m['patient_code'] ?? ''} · ${m['date_of_birth'] ?? 'DOB not set'}',
                                  style: GoogleFonts.roboto(color: digiSlate, fontSize: 12),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => BookAppointmentDialog(
                                            dependentPatientId: (m['patient_id'] as num?)?.toInt(),
                                            dependentName: m['full_name']?.toString(),
                                          ),
                                        );
                                      },
                                      child: const Text('Book for them'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => context.push('/patient/consult-now', extra: (m['patient_id'] as num?)?.toInt()),
                                      child: const Text('Consult Now'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () {
                                        final id = (m['patient_id'] as num?)?.toInt();
                                        if (id == null) return;
                                        final name = Uri.encodeQueryComponent(m['full_name']?.toString() ?? '');
                                        context.push('/patient/family/$id?name=$name');
                                      },
                                      child: const Text('Open chart'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        await context.read<CareRepository>().removeDependent(m['id'] as int);
                                        _load();
                                      },
                                      child: const Text('Unlink'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
