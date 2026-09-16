import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class HospitalHomeScreen extends StatefulWidget {
  const HospitalHomeScreen({super.key});

  @override
  State<HospitalHomeScreen> createState() => _HospitalHomeScreenState();
}

class _HospitalHomeScreenState extends State<HospitalHomeScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().hospitalDesk();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _update(Map r, String status, {String? notes}) async {
    final id = r['id'] as int?;
    if (id == null) return;
    try {
      await context.read<CareRepository>().updateReferral(id, {
        'status': status,
        if (notes != null) 'result_notes': notes,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Referral marked $status')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _complete(Map r) async {
    final notes = TextEditingController(text: r['result_notes']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return referral outcome'),
        content: TextField(
          controller: notes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Specialist / facility notes'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (ok != true) return;
    await _update(r, 'completed', notes: notes.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final hospital = (_data['hospital'] as Map?)?.cast<String, dynamic>() ?? {};
    final refs = ((_data['referrals'] as List?) ?? []).whereType<Map>().toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: RoleChrome(
        title: hospital['name']?.toString() ?? 'Hospital desk',
        subtitle: hospital['region']?.toString() ?? 'Inbound network referrals',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SectionLabel('Referral intake'),
                const SizedBox(height: 8),
                Text(
                  _data['note']?.toString() ??
                      'Specialist referrals from Medilynks clinicians arrive here.',
                  style: GoogleFonts.dmSans(color: digiSlate, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (refs.isEmpty)
                  const ClinicalEmptyState(
                    icon: Icons.local_hospital_outlined,
                    title: 'No inbound referrals',
                    message: 'When a clinician refers a patient to this facility, the case will appear here.',
                  )
                else
                  ...refs.map(
                    (r) {
                      final status = r['status']?.toString() ?? 'pending';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DigiCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['referral_code']?.toString() ?? 'Referral',
                                style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: const Color(0xFF1F4A3A)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${r['full_name'] ?? r['patient_name'] ?? ''} · ${r['patient_code'] ?? ''} · ${r['specialty'] ?? ''}',
                                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${r['urgency'] ?? 'routine'} · $status\n${r['reason'] ?? r['clinical_summary'] ?? ''}',
                                style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.4),
                              ),
                              if ((r['result_notes'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Outcome: ${r['result_notes']}', style: GoogleFonts.dmSans(fontSize: 12)),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (status == 'pending')
                                    FilledButton(
                                      onPressed: () => _update(r, 'accepted'),
                                      child: const Text('Accept'),
                                    ),
                                  if (status == 'accepted' || status == 'pending')
                                    FilledButton.tonal(
                                      onPressed: () => _update(r, 'in_progress'),
                                      child: const Text('In progress'),
                                    ),
                                  if (status != 'completed' && status != 'declined')
                                    FilledButton(
                                      onPressed: () => _complete(r),
                                      child: const Text('Complete'),
                                    ),
                                  if (status == 'pending')
                                    TextButton(
                                      onPressed: () => _update(r, 'declined'),
                                      child: const Text('Decline'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
