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
  String _scope = 'active';

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
      final queue = await care.pharmacyQueue(scope: _scope);
      setState(() {
        _org = org;
        _queue = queue;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> rx, String status, {String? notes}) async {
    final id = rx['id'] as int?;
    if (id == null) return;
    try {
      await context.read<CareRepository>().updatePharmacyStatus(id, status, notes: notes);
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

  Future<void> _cannotFill(Map<String, dynamic> rx) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cannot fill'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (shared with doctor & patient journey)',
            hintText: 'Out of stock, needs alternate strength…',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark unavailable')),
        ],
      ),
    );
    if (ok == true) {
      await _setStatus(rx, 'unavailable', notes: notes.text.trim().isEmpty ? null : notes.text.trim());
    }
    notes.dispose();
  }

  Future<void> _readyWithNotes(Map<String, dynamic> rx) async {
    final notes = TextEditingController(text: rx['pharmacy_notes']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ready for pickup'),
        content: TextField(
          controller: notes,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Pickup notes (optional)',
            hintText: 'Counter 2, bring ID…',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark ready')),
        ],
      ),
    );
    if (ok == true) {
      await _setStatus(rx, 'ready', notes: notes.text.trim().isEmpty ? null : notes.text.trim());
    }
    notes.dispose();
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _scopeChip('active', 'Active'),
                  const SizedBox(width: 8),
                  _scopeChip('ready', 'Ready'),
                  const SizedBox(width: 8),
                  _scopeChip('done', 'Completed'),
                  const SizedBox(width: 8),
                  _scopeChip('all', 'All'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _queue.isEmpty
                    ? ClinicalEmptyState(
                        icon: Icons.local_pharmacy_outlined,
                        title: _scope == 'active' ? 'No prescriptions waiting' : 'Nothing in this view',
                        message: _scope == 'active'
                            ? 'Electronic prescriptions sent to this pharmacy will appear here for accept, prepare and dispense.'
                            : 'Switch filters or wait for new e-prescriptions from Medilynks clinicians.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _queue.length,
                          itemBuilder: (_, i) {
                            final rx = _queue[i];
                            final status = rx['dispense_status']?.toString() ?? 'sent';
                            final phone = rx['patient_phone']?.toString() ?? '';
                            final pharmacyNotes = rx['pharmacy_notes']?.toString() ?? '';
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
                                    if (phone.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.phone_outlined, size: 14, color: Colors.black54),
                                            const SizedBox(width: 4),
                                            Text(phone, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                          ],
                                        ),
                                      ),
                                    Text(
                                      '${rx['strength'] ?? ''} ${rx['dosage'] ?? ''} · ${rx['frequency'] ?? ''} · Qty ${rx['quantity'] ?? '-'}',
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                    if ((rx['instructions'] ?? '').toString().isNotEmpty)
                                      Text('Advise: ${rx['instructions']}', style: const TextStyle(fontSize: 12)),
                                    if (pharmacyNotes.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Notes: $pharmacyNotes',
                                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                        ),
                                      ),
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
                                            onPressed: () => _readyWithNotes(rx),
                                            child: const Text('Ready for pickup'),
                                          ),
                                        if (status == 'ready')
                                          FilledButton(
                                            onPressed: () => _setStatus(rx, 'dispensed'),
                                            child: const Text('Dispense'),
                                          ),
                                        if (status != 'dispensed' && status != 'unavailable')
                                          TextButton(
                                            onPressed: () => _cannotFill(rx),
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
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(String value, String label) {
    final active = _scope == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (v) {
        if (!v) return;
        setState(() => _scope = value);
        _load();
      },
      selectedColor: const Color(0xFF0F766E).withValues(alpha: 0.18),
      labelStyle: GoogleFonts.roboto(
        color: active ? const Color(0xFF0F766E) : Colors.black54,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
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
