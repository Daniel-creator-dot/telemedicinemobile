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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final width = constraints.maxWidth > clinicalMaxWidth ? clinicalMaxWidth : constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 16),
                  child: wide ? _wideBody() : _narrowBody(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _intro({bool showRefresh = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: digiForest),
              tooltip: 'Back',
            ),
            const Spacer(),
            if (showRefresh)
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: digiForest),
                tooltip: 'Refresh',
              ),
          ],
        ),
        const ClinicalPageHeader(
          title: 'Prescriptions',
          subtitle:
              'Where each script is, and a refill once it has been collected or could not be filled.',
        ),
      ],
    );
  }

  Widget _narrowBody() {
    if (_loading) {
      return ListView(
        children: [
          _intro(),
          const SizedBox(height: 20),
          const ClinicalCardSkeleton(),
          const SizedBox(height: 12),
          const ClinicalCardSkeleton(),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          _intro(),
          const SizedBox(height: 24),
          ClinicalErrorState(message: _error!, onRetry: _load),
        ],
      );
    }
    if (_rows.isEmpty) {
      return ListView(
        children: [
          _intro(),
          const SizedBox(height: 24),
          const ClinicalEmptyState(
            icon: Icons.medication_outlined,
            title: 'No prescriptions yet',
            message: 'When a clinician writes a script, pickup status and refill requests will appear here.',
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: _rows.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) return _intro();
        final rx = _rows[i - 1];
        return _PrescriptionCard(
          rx: rx,
          submitting: _submittingId == rx.id,
          onRefill: () => _requestRefill(rx),
        );
      },
    );
  }

  Widget _wideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 340, child: _intro()),
        const SizedBox(width: 24),
        Expanded(child: _wideList()),
      ],
    );
  }

  Widget _wideList() {
    if (_loading) {
      return ListView(
        children: const [
          ClinicalCardSkeleton(),
          SizedBox(height: 12),
          ClinicalCardSkeleton(),
        ],
      );
    }
    if (_error != null) {
      return ClinicalErrorState(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const ClinicalEmptyState(
        icon: Icons.medication_outlined,
        title: 'No prescriptions yet',
        message: 'When a clinician writes a script, pickup status and refill requests will appear here.',
      );
    }
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final rx = _rows[i];
        return _PrescriptionCard(
          rx: rx,
          submitting: _submittingId == rx.id,
          onRefill: () => _requestRefill(rx),
        );
      },
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
    final tone = _statusTone(status);
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
              ClinicalStatusPill(label: label, tone: tone),
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
            ClinicalStatusPill(
              label: _refillLabel(rx.refillStatus),
              tone: _openRefill ? ClinicalTone.gold : ClinicalTone.forest,
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
              child: SizedBox(
                width: 200,
                child: ClinicalPrimaryButton(
                  label: submitting ? 'Sending…' : 'Request refill',
                  onPressed: submitting ? null : onRefill,
                  loading: submitting,
                ),
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
      return 'Ready';
    case 'dispensed':
      return 'Collected';
    case 'unavailable':
      return 'Could not fill';
    case 'cancelled':
      return 'Cancelled';
    default:
      if (status.isEmpty) return 'On your chart';
      return 'In progress';
  }
}

String _refillLabel(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'requested':
      return 'Refill requested';
    case 'approved':
      return 'Refill approved';
    case 'declined':
    case 'rejected':
      return 'Refill declined';
    default:
      return 'Refill on file';
  }
}

ClinicalTone _statusTone(String status) {
  switch (status) {
    case 'ready':
      return ClinicalTone.gold;
    case 'dispensed':
      return ClinicalTone.forest;
    case 'unavailable':
    case 'cancelled':
      return ClinicalTone.clay;
    default:
      return ClinicalTone.slate;
  }
}
