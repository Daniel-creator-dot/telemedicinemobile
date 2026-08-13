import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/appointment.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';
import '../patient/chat_screen.dart';

class NurseHomeScreen extends StatefulWidget {
  const NurseHomeScreen({super.key});

  @override
  State<NurseHomeScreen> createState() => _NurseHomeScreenState();
}

class _NurseHomeScreenState extends State<NurseHomeScreen> {
  List<Map<String, dynamic>> _triage = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<CareRepository>().getTriage();
      setState(() {
        _triage = list;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _setUrgency(Map<String, dynamic> row, String urgency) async {
    final id = row['id'] as int?;
    if (id == null) return;
    await context.read<CareRepository>().updateTriage(id, {'urgency': urgency, 'status': 'reviewed'});
    final aptId = row['appointment_pk'] ?? row['appointment_id'];
    if (aptId != null) {
      await context.read<CareRepository>().assignQueue(
        aptId is int ? aptId : int.parse(aptId.toString()),
        {'urgency': urgency == 'emergency' ? 'High' : urgency == 'urgent' ? 'High' : 'Medium'},
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Triage · ${session.user?.name ?? 'Nurse'}', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
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
          : _triage.isEmpty
              ? const ClinicalEmptyState(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Triage queue is clear',
                  message: 'New Consult Now patients will appear here for vitals, urgency and handover to a doctor.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _triage.length,
                    itemBuilder: (_, i) {
                      final t = _triage[i];
                      final urgency = t['urgency']?.toString() ?? 'routine';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(t['full_name']?.toString() ?? 'Patient', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                                  ),
                                  Text('#${t['queue_number'] ?? '-'}', style: const TextStyle(color: Color(0xFF8B5CF6))),
                                ],
                              ),
                              Text(t['complaint']?.toString() ?? 'No complaint recorded'),
                              Text('Symptoms: ${t['symptoms'] ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              Text('Allergies: ${t['allergies'] ?? '-'} · Meds: ${t['medications'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  _chip('routine', urgency, t),
                                  _chip('urgent', urgency, t),
                                  _chip('emergency', urgency, t),
                                  TextButton(
                                    onPressed: () {
                                      final apt = Appointment.fromJson({
                                        'id': t['appointment_pk'] ?? t['appointment_id'],
                                        'appointment_id': t['apt_code']?.toString() ?? '',
                                        'full_name': t['full_name'],
                                        'phone_number': '',
                                        'preferred_date': '',
                                        'preferred_time': '',
                                        'status': t['appointment_status'] ?? 'queued',
                                        'is_telemedicine': true,
                                        'payment_status': 'unpaid',
                                        'doctor_name': t['doctor_name'],
                                      });
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => ClinicalChatScreen(appointment: apt),
                                      ));
                                    },
                                    child: const Text('Chat'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _chip(String value, String current, Map<String, dynamic> row) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(value),
      selected: selected,
      onSelected: (_) => _setUrgency(row, value),
    );
  }
}
