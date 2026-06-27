import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../models/prescription.dart';
import '../../models/consultation.dart';
import 'appointments_repository.dart';
// ==================== PROFILE VIEW ====================
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  List<Prescription> _prescriptions = [];
  List<Consultation> _consultations = [];
  bool _loadingData = true;

  @override
  void initState() {
    super.initState();
    _loadProfileLogs();
  }

  Future<void> _loadProfileLogs() async {
    try {
      final repo = context.read<AppointmentsRepository>();
      final scripts = await repo.getMyPrescriptions();
      final logs = await repo.getMyConsultations();
      setState(() {
        _prescriptions = scripts;
        _consultations = logs;
        _loadingData = false;
      });
    } catch (e) {
      setState(() => _loadingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<Session>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Profile Header
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF1E293B),
              child: Text(
                session.user?.name.substring(0, session.user!.name.length > 1 ? 2 : 1).toUpperCase() ?? 'SJ',
                style: const TextStyle(
                  fontSize: 24,
                  color: Color(0xFF00D2C4),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            session.user?.name ?? 'Sarah Jenkins',
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 22),
          ),
          Text(
            'Patient ID: #DH-${session.user?.id ?? "00"}-PORTAL',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 10),

          Expanded(
            child: _loadingData
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: theme.colorScheme.primary,
                          unselectedLabelColor: Colors.white38,
                          indicatorColor: theme.colorScheme.primary,
                          tabs: const [
                            Tab(text: 'My Prescriptions'),
                            Tab(text: 'Past Consultations'),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildPrescriptionsTab(),
                              _buildConsultationsTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          
          ElevatedButton.icon(
            onPressed: () async {
              await session.clear();
              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log Out from Portal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withOpacity(0.12),
              foregroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionsTab() {
    if (_prescriptions.isEmpty) {
      return const Center(
        child: Text('No active prescriptions registered.', style: TextStyle(color: Colors.white24, fontSize: 13)),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _prescriptions.length,
      itemBuilder: (context, index) {
        final pr = _prescriptions[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.02)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pr.medicationName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Dosage: ${pr.dosage ?? "-"}  |  Frequency: ${pr.frequency ?? "-"}  |  Duration: ${pr.duration ?? "-"}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              if (pr.instructions != null && pr.instructions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Instructions: ${pr.instructions}',
                  style: const TextStyle(color: Color(0xFF00D2C4), fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildConsultationsTab() {
    if (_consultations.isEmpty) {
      return const Center(
        child: Text('No past consultation logs found.', style: TextStyle(color: Colors.white24, fontSize: 13)),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _consultations.length,
      itemBuilder: (context, index) {
        final c = _consultations[index];
        // Collect vitals that were recorded
        final vitals = <Map<String, String>>[];
        if (c.vitalsBp != null && c.vitalsBp!.isNotEmpty) vitals.add({'label': 'BP', 'value': c.vitalsBp!});
        if (c.vitalsTemp != null && c.vitalsTemp!.isNotEmpty) vitals.add({'label': 'Temp', 'value': '${c.vitalsTemp}Â°C'});
        if (c.vitalsPulse != null && c.vitalsPulse!.isNotEmpty) vitals.add({'label': 'Pulse', 'value': '${c.vitalsPulse} bpm'});
        if (c.vitalsWeight != null && c.vitalsWeight!.isNotEmpty) vitals.add({'label': 'Wt', 'value': '${c.vitalsWeight} kg'});
        if (c.vitalsHeight != null && c.vitalsHeight!.isNotEmpty) vitals.add({'label': 'Ht', 'value': '${c.vitalsHeight} cm'});
        if (c.vitalsSpo2 != null && c.vitalsSpo2!.isNotEmpty) vitals.add({'label': 'SpO2', 'value': '${c.vitalsSpo2}%'});

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.02)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c.doctorName ?? 'Consultation Log',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  if (c.createdAt != null)
                    Text(
                      c.createdAt!.split('T').first,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00D2C4), size: 16),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Diagnosis: ${c.diagnosis ?? "No diagnosis entered."}',
                style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text('Chief Complaint: ${c.chiefComplaint ?? "-"}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Text('Symptoms: ${c.symptoms ?? "-"}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              if (c.clinicalNotes != null && c.clinicalNotes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Advice: ${c.clinicalNotes}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
              // Vitals badges row
              if (vitals.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: vitals.map((v) => _vitalsBadge(v['label']!, v['value']!)).toList(),
                ),
              ],
              if (c.followUpDate != null && c.followUpDate!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.event_repeat_rounded, size: 12, color: Color(0xFF00D2C4)),
                    const SizedBox(width: 4),
                    Text(
                      'Follow-up: ${c.followUpDate}',
                      style: const TextStyle(color: Color(0xFF00D2C4), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _vitalsBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
