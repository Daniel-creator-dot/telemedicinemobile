import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/doctor_profile.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/book_appointment_dialog.dart';
import 'care_repository.dart';

class DoctorDirectoryScreen extends StatefulWidget {
  const DoctorDirectoryScreen({super.key});

  @override
  State<DoctorDirectoryScreen> createState() => _DoctorDirectoryScreenState();
}

class _DoctorDirectoryScreenState extends State<DoctorDirectoryScreen> {
  List<DoctorProfile> _doctors = [];
  bool _loading = true;
  final _search = TextEditingController();
  String? _specialty;
  String? _language;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<CareRepository>().getDirectory(
        q: _search.text.trim(),
        specialty: _specialty,
        language: _language,
      );
      setState(() {
        _doctors = list;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: AppBar(
        title: Text('Doctors & specialists', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFF6F3EE),
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Name, specialty, language, or clinic',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE8E4DC))),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                for (final lang in const ['English', 'Twi', 'Ga', 'Ewe', 'Hausa'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(lang),
                      selected: _language == lang,
                      onSelected: (on) {
                        setState(() => _language = on ? lang : null);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _doctors.isEmpty
                    ? const ClinicalEmptyState(
                        icon: Icons.medical_services_outlined,
                        title: 'No matching clinicians',
                        message: 'Try another language or clear the search. Availability is shown in real time.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _doctors.length,
                        itemBuilder: (_, i) {
                          final d = _doctors[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DigiCard(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => BookAppointmentDialog(
                                    preselectedDoctorId: d.id,
                                    preselectedDoctorName: '${d.title ?? 'Dr'} ${d.name}',
                                    preselectedSpecialty: d.specialization,
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${d.title ?? 'Dr'} ${d.name}', style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            d.specialization ?? 'General physician',
                                            d.facility,
                                            if (d.yearsExperience != null) '${d.yearsExperience} yrs',
                                            d.languages,
                                            if (d.consultationFee != null) 'GHS ${d.consultationFee!.toStringAsFixed(0)}',
                                          ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                                          style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.35),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      Icon(Icons.circle, size: 10, color: d.isOnline ? const Color(0xFF1F4A3A) : const Color(0xFFC4BEB4)),
                                      Text(d.isOnline ? 'Online' : 'Off', style: GoogleFonts.dmSans(fontSize: 10, color: digiSlate)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
