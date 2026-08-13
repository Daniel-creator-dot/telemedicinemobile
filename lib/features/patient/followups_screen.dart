import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'book_appointment_dialog.dart';
import 'care_repository.dart';

class FollowupsScreen extends StatefulWidget {
  const FollowupsScreen({super.key});

  @override
  State<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends State<FollowupsScreen> {
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await context.read<CareRepository>().myFollowups();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load follow-ups.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: AppBar(
        title: Text('Follow-up care', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFF6F3EE),
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? const ClinicalEmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No follow-ups scheduled',
                      message: 'When a clinician sets a review date, it will appear here so the journey stays closed-loop.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return DigiCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['follow_up_date']?.toString().split('T').first ?? 'Date TBC',
                                style: GoogleFonts.sourceSerif4(fontSize: 20, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${r['appointment_id'] ?? r['full_name'] ?? ''} · ${r['service'] ?? r['status'] ?? ''}',
                                style: GoogleFonts.dmSans(color: digiSlate),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => const BookAppointmentDialog(
                                        preselectedSpecialty: 'follow-up',
                                      ),
                                    );
                                  },
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1F4A3A)),
                                  child: const Text('Book this review'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
