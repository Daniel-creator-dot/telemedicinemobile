import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../models/prescription.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'appointments_repository.dart';

class PrescriptionsScreen extends StatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  State<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends State<PrescriptionsScreen> {
  List<Prescription> _rows = [];
  bool _loading = true;
  String? _error;
  int? _submittingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await context.read<AppointmentsRepository>().getMyPrescriptions();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _submittingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DioException
            ? ApiClient.messageFromDio(e, 'Could not load prescriptions.')
            : 'Could not load prescriptions.';
        _loading = false;
        _submittingId = null;
      });
    }
  }

  Future<void> _requestRefill(Prescription rx) async {
    final noteController = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: digiPaper,
          title: Text(
            'Request a refill',
            style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600, color: digiInk),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rx.medicationName,
                  style: GoogleFonts.dmSans(color: digiSlate, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLength: 500,
                  maxLines: 3,
                  style: GoogleFonts.dmSans(color: digiInk),
                  decoration: InputDecoration(
                    hintText: 'Optional note for your clinician',
                    hintStyle: GoogleFonts.dmSans(color: digiSlate),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: digiLine),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: digiLine),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.dmSans(color: digiSlate)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: digiForest, foregroundColor: Colors.white),
              child: const Text('Send request'),
            ),
          ],
        );
      },
    );
    final note = noteController.text;
    noteController.dispose();
    if (send != true || !mounted) return;

    setState(() => _submittingId = rx.id);
    try {
      await context.read<AppointmentsRepository>().requestRefill(rx.id, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refill requested for ${rx.medicationName}')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      final message = e is DioException
          ? ApiClient.messageFromDio(e, 'Could not request a refill.')
          : 'Could not request a refill.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _submittingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: AppBar(
        title: Text('Prescriptions', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: digiPaper,
        foregroundColor: digiInk,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, color: digiForest),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: digiForest))
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? const ClinicalEmptyState(
                      icon: Icons.medication_outlined,
                      title: 'No prescriptions yet',
                      message: 'When a clinician writes a script, pickup status and refill requests will appear here.',
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 880),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          itemCount: _rows.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            if (i == 0) return const _DeskIntro();
                            return _PrescriptionCard(
                              rx: _rows[i - 1],
                              submitting: _submittingId == _rows[i - 1].id,
                              onRefill: () => _requestRefill(_rows[i - 1]),
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}

class _DeskIntro extends StatelessWidget {
  const _DeskIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pharmacy pickup',
          style: GoogleFonts.sourceSerif4(fontSize: 28, fontWeight: FontWeight.w600, color: digiInk),
        ),
        const SizedBox(height: 6),
        Text(
          'See where each script is, and ask your clinician for a refill after it has been collected or could not be filled.',
          style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
        ),
      ],
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({
    required this.rx,
    required this.submitting,
    required this.onRefill,
  });

  final Prescription rx;
  final bool submitting;
  final VoidCallback onRefill;

  bool get _openRefill => (rx.refillStatus ?? '').toLowerCase() == 'requested';

  bool get _canRefill {
    final status = (rx.dispenseStatus ?? 'unsent').toLowerCase();
    return (status == 'dispensed' || status == 'unavailable') && !_openRefill;
  }

  @override
  Widget build(BuildContext context) {
    final status = (rx.dispenseStatus ?? 'unsent').toLowerCase();
    final label = dispenseStatusLabel(status);
    final tone = _statusColor(status);
    final regimen = [
      if ((rx.strength ?? '').isNotEmpty) rx.strength,
      if ((rx.dosage ?? '').isNotEmpty) rx.dosage,
      if ((rx.frequency ?? '').isNotEmpty) rx.frequency,
      if ((rx.duration ?? '').isNotEmpty) rx.duration,
      if ((rx.quantity ?? '').isNotEmpty) 'Qty ${rx.quantity}',
      if ((rx.route ?? '').isNotEmpty) rx.route,
    ].whereType<String>().join(' · ');

    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((rx.prescriptionRef ?? '').isNotEmpty)
                      Text(
                        rx.prescriptionRef!,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: digiGold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    Text(
                      rx.medicationName,
                      style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w600, color: digiInk),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatusPill(label: label, color: tone),
            ],
          ),
          if (regimen.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(regimen, style: GoogleFonts.dmSans(color: digiInk, height: 1.4)),
          ],
          if ((rx.instructions ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(rx.instructions!, style: GoogleFonts.dmSans(color: digiSlate, height: 1.4)),
          ],
          if (_hasPharmacy) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: digiPaper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: digiLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pickup',
                    style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: digiForest),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if ((rx.pharmacyName ?? '').isNotEmpty) rx.pharmacyName,
                      if ((rx.pharmacyTown ?? '').isNotEmpty) rx.pharmacyTown,
                    ].whereType<String>().join(' · '),
                    style: GoogleFonts.dmSans(color: digiInk, fontWeight: FontWeight.w600),
                  ),
                  if ((rx.pharmacyAddress ?? '').isNotEmpty)
                    Text(rx.pharmacyAddress!, style: GoogleFonts.dmSans(color: digiSlate, height: 1.4)),
                  if ((rx.pharmacyPhone ?? '').isNotEmpty)
                    Text(rx.pharmacyPhone!, style: GoogleFonts.dmSans(color: digiSlate)),
                  if ((rx.pharmacyNotes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(rx.pharmacyNotes!, style: GoogleFonts.dmSans(color: digiInk, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
          if (_openRefill || (rx.refillStatus ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            _StatusPill(
              label: _openRefill ? 'Refill requested' : 'Refill ${rx.refillStatus}',
              color: _openRefill ? digiGold : digiForest,
            ),
            if ((rx.refillNote ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note: ${rx.refillNote}', style: GoogleFonts.dmSans(color: digiSlate, height: 1.4)),
            ],
          ],
          if (_canRefill) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: submitting ? null : onRefill,
                style: FilledButton.styleFrom(
                  backgroundColor: digiForest,
                  foregroundColor: Colors.white,
                ),
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(submitting ? 'Sending…' : 'Request refill'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasPharmacy {
    return (rx.pharmacyName ?? '').isNotEmpty ||
        (rx.pharmacyTown ?? '').isNotEmpty ||
        (rx.pharmacyAddress ?? '').isNotEmpty ||
        (rx.pharmacyPhone ?? '').isNotEmpty ||
        (rx.pharmacyNotes ?? '').isNotEmpty;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

String dispenseStatusLabel(String status) {
  switch (status) {
    case 'unsent':
      return 'On your chart';
    case 'sent':
      return 'Sent to pharmacy';
    case 'received':
      return 'Pharmacy received';
    case 'preparing':
      return 'Being prepared';
    case 'ready':
      return 'Ready for pickup';
    case 'dispensed':
      return 'Collected';
    case 'unavailable':
      return 'Could not fill';
    case 'cancelled':
      return 'Cancelled';
    default:
      if (status.isEmpty) return 'On your chart';
      return status[0].toUpperCase() + status.substring(1);
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'ready':
      return digiGold;
    case 'dispensed':
      return digiForest;
    case 'unavailable':
    case 'cancelled':
      return const Color(0xFF8C3A3A);
    default:
      return digiForest;
  }
}
