import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/appointment.dart';
import '../../models/doctor_profile.dart';
import '../patient/care_repository.dart';

class ReferralDialog extends StatefulWidget {
  const ReferralDialog({super.key, required this.appointment, required this.patientId});

  final Appointment appointment;
  final int patientId;

  @override
  State<ReferralDialog> createState() => _ReferralDialogState();
}

class _ReferralDialogState extends State<ReferralDialog> {
  final _reason = TextEditingController();
  final _summary = TextEditingController();
  List<DoctorProfile> _doctors = [];
  int? _toDoctorId;
  String _specialty = 'Cardiology';
  String _urgency = 'routine';
  bool _loading = true;
  bool _submitting = false;

  static const _specialties = [
    'Cardiology',
    'Paediatrics',
    'Obstetrics & Gynaecology',
    'Orthopaedics',
    'Dermatology',
    'ENT',
    'Ophthalmology',
    'Psychiatry',
    'Internal Medicine',
    'General Surgery',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final docs = await context.read<CareRepository>().getDirectory();
    setState(() {
      _doctors = docs;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await context.read<CareRepository>().createReferral({
        'appointment_id': widget.appointment.id,
        'patient_id': widget.patientId,
        'to_doctor_id': _toDoctorId,
        'specialty': _specialty,
        'reason': _reason.text.trim(),
        'clinical_summary': _summary.text.trim(),
        'urgency': _urgency,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Referral failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Specialist referral', style: GoogleFonts.roboto(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _specialty,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: _deco('Specialty'),
                      items: _specialties
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.white))))
                          .toList(),
                      onChanged: (v) => setState(() => _specialty = v ?? _specialty),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _toDoctorId,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: _deco('Specialist (optional)'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Any available specialist', style: TextStyle(color: Colors.white70))),
                        ..._doctors.where((d) => d.userId != null).map(
                          (d) => DropdownMenuItem<int?>(
                            value: d.userId,
                            child: Text('${d.name} · ${d.specialization ?? ''}', style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _toDoctorId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _urgency,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: _deco('Urgency'),
                      items: const [
                        DropdownMenuItem(value: 'routine', child: Text('Routine', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'urgent', child: Text('Urgent', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 'emergency', child: Text('Emergency', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (v) => setState(() => _urgency = v ?? 'routine'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reason,
                      style: const TextStyle(color: Colors.white),
                      decoration: _deco('Reason for referral'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _summary,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: _deco('Clinical summary'),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D2C4),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(_submitting ? 'Sending…' : 'Send referral', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  InputDecoration _deco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00D2C4))),
    );
  }
}
