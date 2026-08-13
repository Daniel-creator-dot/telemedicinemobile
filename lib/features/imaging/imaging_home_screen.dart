import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
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

  Future<void> _submit(Map<String, dynamic> item) async {
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
    if (ok != true) return;
    await context.read<ApiClient>().dio.put(
      '/api/scans/${item['id']}',
      data: {
        'status': 'completed',
        'results': results.text.trim(),
        'result_notes': notes.text.trim(),
      },
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _org?['name']?.toString() ?? 'Imaging centre',
          style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
        ),
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
          : _scans.isEmpty
              ? const Center(child: Text('No imaging requests assigned.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _scans.length,
                    itemBuilder: (_, i) {
                      final s = _scans[i] as Map<String, dynamic>;
                      final done = s['status']?.toString() == 'completed';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(
                            '${s['scan_type']?.toString().toUpperCase() ?? 'SCAN'} — ${s['body_part'] ?? ''}',
                            style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${s['patient_name'] ?? ''} · ${s['urgency'] ?? 'routine'}\n${s['clinical_indication'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: done
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : FilledButton(
                                  onPressed: () => _submit(s),
                                  child: const Text('Report'),
                                ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
