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
  _JourneyFilter _filter = _JourneyFilter.all;

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
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not load your health journey.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _events {
    final all = ((_data['events'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    switch (_filter) {
      case _JourneyFilter.open:
        return all.where((e) => e['is_open'] == true).toList();
      case _JourneyFilter.done:
        return all.where((e) => e['is_open'] != true).toList();
      case _JourneyFilter.all:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _data['open_count'] is int
        ? _data['open_count'] as int
        : int.tryParse(_data['open_count']?.toString() ?? '') ?? 0;
    final events = _events;

    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Health Journey', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: digiPaper,
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient ID ${_data['patient_code'] ?? '—'} · labs, pharmacy & visits in one timeline',
                            style: GoogleFonts.dmSans(color: digiSlate, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (openCount > 0) ...[
                            const SizedBox(height: 10),
                            DigiCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_pharmacy_outlined, color: digiForest, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$openCount in progress — pharmacy, lab, imaging or referral',
                                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SegmentedButton<_JourneyFilter>(
                            segments: const [
                              ButtonSegment(value: _JourneyFilter.all, label: Text('All')),
                              ButtonSegment(value: _JourneyFilter.open, label: Text('In progress')),
                              ButtonSegment(value: _JourneyFilter.done, label: Text('Done')),
                            ],
                            selected: {_filter},
                            onSelectionChanged: (s) => setState(() => _filter = s.first),
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStatePropertyAll(GoogleFonts.dmSans(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: events.isEmpty
                          ? ClinicalEmptyState(
                              icon: Icons.timeline_rounded,
                              title: _filter == _JourneyFilter.open
                                  ? 'Nothing in progress'
                                  : 'Your journey starts here',
                              message: _filter == _JourneyFilter.open
                                  ? 'Completed and closed items appear under Done or All.'
                                  : 'Consultations, labs, imaging, prescriptions and referrals appear here with live status.',
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: events.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) => _JourneyTile(event: events[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

enum _JourneyFilter { all, open, done }

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

  Color get _chipColor {
    if (event['is_open'] == true) return digiForest;
    final status = event['status']?.toString().toLowerCase() ?? '';
    if (status == 'completed' || status == 'dispensed') return digiGold;
    if (status == 'cancelled') return digiSlate;
    return digiForest;
  }

  @override
  Widget build(BuildContext context) {
    final label = event['status_label']?.toString() ?? event['status']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: event['is_open'] == true ? digiForest.withValues(alpha: 0.35) : digiLine,
          width: event['is_open'] == true ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: digiForest.withValues(alpha: 0.12),
            child: Icon(_icon, color: digiForest, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event['title'] ?? 'Care event'}',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
                ),
                const SizedBox(height: 4),
                Text(
                  '${event['subtitle'] ?? ''}',
                  style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _chipColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: _chipColor),
            ),
          ),
        ],
      ),
    );
  }
}
