import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../nurse/nurse_home_screen.dart';
import '../patient/care_repository.dart';

class OpsHomeScreen extends StatefulWidget {
  const OpsHomeScreen({super.key});

  @override
  State<OpsHomeScreen> createState() => _OpsHomeScreenState();
}

class _OpsHomeScreenState extends State<OpsHomeScreen> {
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await context.read<CareRepository>().opsDashboard();
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Medical Operations', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
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
                Text('Medical Operations command centre', style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Live staffing, queue, documentation and closed-loop care. Clinical quality only — commercial contracts stay with finance and admin.',
                  style: GoogleFonts.roboto(color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _stat('Doctors online', _stats['doctors_online']),
                    _stat('Consulting now', _stats['consulting_now']),
                    _stat('Patients waiting', _stats['patients_waiting']),
                    _stat('Avg wait (min)', _stats['avg_wait']),
                    _stat('Completed today', _stats['completed_today']),
                    _stat('Cancelled', _stats['cancelled_today']),
                    _stat('Missed', _stats['missed_today']),
                    _stat('Pending notes', _stats['pending_notes']),
                    _stat('Pending labs', _stats['pending_labs']),
                    _stat('Pending scans', _stats['pending_scans']),
                    _stat('Pharmacy queue', _stats['pending_pharmacy']),
                    _stat('Open referrals', _stats['open_referrals']),
                    _stat('Overdue follow-ups', _stats['overdue_followups']),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NurseHomeScreen()));
                  },
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Open live triage queue'),
                ),
              ],
            ),
    );
  }

  Widget _stat(String label, dynamic value) {
    String text = value?.toString() ?? '0';
    if (value is num && value is! int) text = value.toStringAsFixed(0);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF8B5CF6))),
          Text(label, style: GoogleFonts.roboto(fontSize: 12, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }
}
