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
                      'Specialist referrals from Digi Health clinicians arrive here.',
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
                    (r) => Padding(
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
                              '${r['full_name'] ?? ''} · ${r['patient_code'] ?? ''} · ${r['specialty'] ?? ''}',
                              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${r['urgency'] ?? 'routine'} · ${r['status'] ?? ''}\n${r['reason'] ?? r['clinical_summary'] ?? ''}',
                              style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
