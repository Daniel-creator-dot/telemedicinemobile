import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../patient/care_repository.dart';

class CorporateHomeScreen extends StatefulWidget {
  const CorporateHomeScreen({super.key});

  @override
  State<CorporateHomeScreen> createState() => _CorporateHomeScreenState();
}

class _CorporateHomeScreenState extends State<CorporateHomeScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  final _code = TextEditingController();
  final _staff = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _staff.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().corporateDashboard();
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _enroll() async {
    if (_code.text.trim().isEmpty) return;
    await context.read<CareRepository>().addCorporateMember(
          patientCode: _code.text.trim(),
          staffId: _staff.text.trim().isEmpty ? null : _staff.text.trim(),
        );
    _code.clear();
    _staff.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final corp = _data['corporate'] as Map<String, dynamic>? ?? {};
    final members = ((_data['members'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final billed = _data['billed'] as Map<String, dynamic>? ?? {};
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(corp['name']?.toString() ?? 'Corporate scheme', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () async {
              await session.clear();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Staff medical scheme', style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    _chip('${members.length} members'),
                    _chip('Copay GHS ${corp['copay_amount'] ?? 20}'),
                    _chip('Covered ${corp['coverage_percent'] ?? 60}%'),
                    _chip('Billed GHS ${billed['billed'] ?? 0}'),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Enrol staff', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                        TextField(controller: _code, decoration: const InputDecoration(labelText: 'Patient ID (DH-100001)')),
                        TextField(controller: _staff, decoration: const InputDecoration(labelText: 'Staff ID')),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _enroll, child: const Text('Add member')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...members.map((m) {
                  final active = m['status']?.toString() == 'active';
                  return Card(
                    child: ListTile(
                      title: Text(m['full_name']?.toString() ?? '', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                      subtitle: Text('${m['patient_code'] ?? ''} · ${m['staff_id'] ?? ''} · ${m['department'] ?? ''}'),
                      trailing: TextButton(
                        onPressed: () async {
                          await context.read<CareRepository>().updateCorporateMember(
                                m['id'] as int,
                                active ? 'suspended' : 'active',
                              );
                          _load();
                        },
                        child: Text(active ? 'Suspend' : 'Activate'),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _chip(String label) => Chip(label: Text(label));
}
