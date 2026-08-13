import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/doctor_profile.dart';
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Doctors & Specialists', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search name or specialty',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _doctors.isEmpty
                    ? const Center(child: Text('No doctors available.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _doctors.length,
                        itemBuilder: (_, i) {
                          final d = _doctors[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text('${d.title ?? 'Dr'} ${d.name}', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                              subtitle: Text([
                                d.specialization ?? 'General Physician',
                                d.facility,
                                if (d.yearsExperience != null) '${d.yearsExperience} yrs',
                                d.languages,
                                if (d.consultationFee != null) 'GHS ${d.consultationFee!.toStringAsFixed(0)}',
                              ].whereType<String>().join(' · ')),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.circle, size: 10, color: d.isOnline ? const Color(0xFF22C55E) : Colors.grey),
                                  Text(d.isOnline ? 'Online' : 'Offline', style: const TextStyle(fontSize: 10)),
                                ],
                              ),
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
