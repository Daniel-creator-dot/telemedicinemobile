import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class ImagingHomeScreen extends StatefulWidget {
  const ImagingHomeScreen({super.key});

  @override
  State<ImagingHomeScreen> createState() => _ImagingHomeScreenState();
}

class _ImagingHomeScreenState extends State<ImagingHomeScreen> {
  List<dynamic> _scans = [];
  Map<String, dynamic>? _org;
  bool _loading = true;
  String _filter = 'active';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final org = await context.read<CareRepository>().myPartnerOrg();
      final scans = await api.dio.get<List<dynamic>>('/api/scans');
      setState(() {
        _org = org;
        _scans = scans.data ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    return _scans.where((s) {
      final status = s['status']?.toString().toLowerCase() ?? 'pending';
      if (_filter == 'all') return true;
      if (_filter == 'done') return status == 'completed' || status == 'cancelled';
      return status != 'completed' && status != 'cancelled';
    }).toList();
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status, {String? results, String? notes}) async {
    try {
      await context.read<ApiClient>().dio.put(
        '/api/scans/${item['id']}',
        data: {
          'status': status,
          'results': results ?? item['results']?.toString() ?? '',
          'result_notes': notes ?? item['result_notes']?.toString() ?? '',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == 'completed' ? 'Report returned to clinician' : 'Marked $status')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  Future<void> _submitReport(Map<String, dynamic> item) async {
    final results = TextEditingController(text: item['results']?.toString() ?? '');
    final notes = TextEditingController(text: item['result_notes']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return imaging report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: results, maxLines: 3, decoration: const InputDecoration(labelText: 'Findings')),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Radiologist notes')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Return to doctor')),
        ],
      ),
    );
    if (ok == true) {
      await _setStatus(item, 'completed', results: results.text.trim(), notes: notes.text.trim());
    }
    results.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: RoleChrome(
        title: _org?['name']?.toString() ?? 'Imaging centre',
        subtitle: 'Schedule → scan → return report',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Active'),
                  selected: _filter == 'active',
                  onSelected: (_) => setState(() => _filter = 'active'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Completed'),
                  selected: _filter == 'done',
                  onSelected: (_) => setState(() => _filter = 'done'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const ClinicalEmptyState(
                        icon: Icons.photo_camera_outlined,
                        title: 'No imaging referrals',
                        message:
                            'X-ray, ultrasound, CT and MRI requests from Medilynks clinicians will land here for scheduling and report return.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final s = list[i] as Map<String, dynamic>;
                            final status = s['status']?.toString().toLowerCase() ?? 'pending';
                            final done = status == 'completed';
                            final phone = s['patient_phone']?.toString() ?? '';
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
                                          child: Text(
                                            '${s['scan_type']?.toString().toUpperCase() ?? 'SCAN'} — ${s['body_part'] ?? ''}',
                                            style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        _statusChip(status),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('${s['patient_name'] ?? ''} · ${s['urgency'] ?? 'routine'}'),
                                    if (phone.isNotEmpty)
                                      Text(phone, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                    if ((s['clinical_indication'] ?? '').toString().isNotEmpty)
                                      Text(
                                        s['clinical_indication'].toString(),
                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    if (!done) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          if (status == 'pending')
                                            FilledButton(
                                              onPressed: () => _setStatus(s, 'scheduled'),
                                              child: const Text('Schedule'),
                                            ),
                                          if (status == 'pending' || status == 'scheduled')
                                            FilledButton.tonal(
                                              onPressed: () => _setStatus(s, 'processing'),
                                              child: const Text('Start scan'),
                                            ),
                                          FilledButton(
                                            onPressed: () => _submitReport(s),
                                            child: const Text('Return report'),
                                          ),
                                        ],
                                      ),
                                    ] else
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Row(
                                          children: [
                                            Icon(Icons.check_circle, color: Colors.green, size: 18),
                                            SizedBox(width: 6),
                                            Text('Report returned'),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final colors = {
      'pending': Colors.amber,
      'scheduled': Colors.indigo,
      'processing': Colors.blue,
      'completed': Colors.green,
      'cancelled': Colors.red,
    };
    return Chip(
      label: Text(status.replaceAll('_', ' '), style: const TextStyle(color: Colors.white, fontSize: 11)),
      backgroundColor: colors[status] ?? Colors.grey,
      visualDensity: VisualDensity.compact,
    );
  }
}
