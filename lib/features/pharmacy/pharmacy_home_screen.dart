import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class PharmacyHomeScreen extends StatefulWidget {
  const PharmacyHomeScreen({super.key});

  @override
  State<PharmacyHomeScreen> createState() => _PharmacyHomeScreenState();
}

class _PharmacyHomeScreenState extends State<PharmacyHomeScreen> {
  List<Map<String, dynamic>> _queue = [];
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
      final care = context.read<CareRepository>();
      final org = await care.myPartnerOrg();
      final queue = await care.pharmacyQueue();
      setState(() {
        _org = org;
        _queue = queue;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> rx, String status) async {
    final id = rx['id'] as int?;
    if (id == null) return;
    try {
      await context.read<CareRepository>().updatePharmacyStatus(id, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked ${rx['medication_name'] ?? 'Rx'} as $status')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: RoleChrome(
        title: _org?['name']?.toString() ?? 'Pharmacy',
        subtitle: 'Accept, prepare, dispense',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _queue.isEmpty
              ? const ClinicalEmptyState(
                  icon: Icons.local_pharmacy_outlined,
                  title: 'No prescriptions waiting',
                  message: 'Electronic prescriptions sent to this pharmacy will appear here for accept, prepare and dispense.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _queue.length,
                    itemBuilder: (_, i) {
                      final rx = _queue[i];
                      final status = rx['dispense_status']?.toString() ?? 'sent';
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
                                      rx['prescription_ref']?.toString() ?? 'RX',
                                      style: GoogleFonts.roboto(
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F766E),
                                      ),
                                    ),
                                  ),
                                  _statusChip(status),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                rx['medication_name']?.toString() ?? '',
                                style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text('${rx['patient_name'] ?? ''} · ${rx['patient_code'] ?? ''}'),
                              Text(
                                '${rx['strength'] ?? ''} ${rx['dosage'] ?? ''} · ${rx['frequency'] ?? ''} · Qty ${rx['quantity'] ?? '-'}',
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              if ((rx['instructions'] ?? '').toString().isNotEmpty)
                                Text('Advise: ${rx['instructions']}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (status == 'sent')
                                    FilledButton(
                                      onPressed: () => _setStatus(rx, 'received'),
                                      child: const Text('Receive'),
                                    ),
                                  if (status == 'received')
                                    FilledButton(
                                      onPressed: () => _setStatus(rx, 'preparing'),
                                      child: const Text('Start preparing'),
                                    ),
                                  if (status == 'received' || status == 'preparing')
                                    FilledButton(
                                      onPressed: () => _setStatus(rx, 'ready'),
                                      child: const Text('Ready for pickup'),
                                    ),
                                  if (status == 'ready')
                                    FilledButton(
                                      onPressed: () => _setStatus(rx, 'dispensed'),
                                      child: const Text('Dispense'),
                                    ),
                                  if (status != 'dispensed' && status != 'unavailable')
                                    TextButton(
                                      onPressed: () => _setStatus(rx, 'unavailable'),
                                      child: const Text('Cannot fill'),
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

  Widget _statusChip(String status) {
    final colors = {
      'sent': Colors.blue,
      'received': Colors.indigo,
      'preparing': Colors.orange,
      'ready': Colors.teal,
      'dispensed': Colors.green,
      'unavailable': Colors.red,
    };
    return Chip(
      label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 11)),
      backgroundColor: colors[status] ?? Colors.grey,
      visualDensity: VisualDensity.compact,
    );
  }
}
