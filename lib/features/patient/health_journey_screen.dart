import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class HealthJourneyScreen extends StatefulWidget {
  const HealthJourneyScreen({super.key});

  @override
  State<HealthJourneyScreen> createState() => _HealthJourneyScreenState();
}

class _HealthJourneyScreenState extends State<HealthJourneyScreen> {
  Map<String, dynamic> _data = {};
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
      final data = await context.read<CareRepository>().healthJourney();
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'We could not load your health journey.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ((_data['events'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Health Journey', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : events.isEmpty
                  ? ClinicalEmptyState(
                      icon: Icons.timeline_rounded,
                      title: 'Your journey starts here',
                      message: 'Consultations, labs, imaging, prescriptions and referrals will appear in one timeline.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: events.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Text(
                              'Patient ID ${_data['patient_code'] ?? '—'} · one continuous record',
                              style: GoogleFonts.roboto(color: digiSlate, fontWeight: FontWeight.w600),
                            );
                          }
                          final e = events[i - 1];
                          return _JourneyTile(event: e);
                        },
                      ),
                    ),
    );
  }
}

class _JourneyTile extends StatelessWidget {
  const _JourneyTile({required this.event});
  final Map<String, dynamic> event;

  IconData get _icon {
    switch (event['kind']) {
      case 'lab':
        return Icons.science_outlined;
      case 'imaging':
        return Icons.photo_camera_outlined;
      case 'prescription':
        return Icons.medication_outlined;
      case 'referral':
        return Icons.share_outlined;
      default:
        return Icons.videocam_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: digiViolet.withValues(alpha: 0.12),
            child: Icon(_icon, color: digiViolet, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${event['title'] ?? 'Care event'}', style: GoogleFonts.roboto(fontWeight: FontWeight.w700)),
                Text('${event['subtitle'] ?? ''}', style: GoogleFonts.roboto(color: digiSlate, fontSize: 13)),
              ],
            ),
          ),
          Text(
            '${event['status'] ?? ''}',
            style: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.w700, color: digiMint),
          ),
        ],
      ),
    );
  }
}
