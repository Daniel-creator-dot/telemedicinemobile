import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../models/appointment.dart';

class PrescriptionDialog extends StatefulWidget {
  const PrescriptionDialog({super.key, required this.appointment});

  final Appointment appointment;

  @override
  State<PrescriptionDialog> createState() => _PrescriptionDialogState();
}

class _PrescriptionDialogState extends State<PrescriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _medicationName = TextEditingController();
  final _dosage = TextEditingController();
  final _frequency = TextEditingController();
  final _duration = TextEditingController();
  final _instructions = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _medicationName.dispose();
    _dosage.dispose();
    _frequency.dispose();
    _duration.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      final api = context.read<ApiClient>();

      // Get patient_id from appointment list
      final appointmentsRes = await api.dio.get<List<dynamic>>('/api/appointments');
      int patientId = 0;
      if (appointmentsRes.data != null) {
        final matches = appointmentsRes.data!.where((json) => json['id'] == widget.appointment.id);
        if (matches.isNotEmpty) {
          patientId = matches.first['patient_id'] as int? ?? 0;
        }
      }

      await api.dio.post<Map<String, dynamic>>(
        '/api/prescriptions',
        data: {
          'appointment_id': widget.appointment.id,
          'patient_id': patientId,
          'medication_name': _medicationName.text.trim(),
          'dosage': _dosage.text.trim(),
          'frequency': _frequency.text.trim(),
          'duration': _duration.text.trim(),
          'instructions': _instructions.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prescription registered successfully.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit prescription: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Write Prescription',
                      style: GoogleFonts.roboto(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _medicationName,
                  style: GoogleFonts.roboto(color: Colors.white),
                  decoration: _inputDeco('Medication Name', Icons.medication_outlined),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Medication name required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dosage,
                  style: GoogleFonts.roboto(color: Colors.white),
                  decoration: _inputDeco('Dosage (e.g. 500mg, 1 tablet)', Icons.healing_outlined),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Dosage required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _frequency,
                  style: GoogleFonts.roboto(color: Colors.white),
                  decoration: _inputDeco('Frequency (e.g. 3 times daily)', Icons.repeat_rounded),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Frequency required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _duration,
                  style: GoogleFonts.roboto(color: Colors.white),
                  decoration: _inputDeco('Duration (e.g. 7 days)', Icons.calendar_today_outlined),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Duration required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instructions,
                  maxLines: 2,
                  style: GoogleFonts.roboto(color: Colors.white),
                  decoration: _inputDeco('Special Instructions (e.g. Take after meals)', Icons.info_outline),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2C4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'Issue Prescription',
                          style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hintText, IconData prefixIcon) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.roboto(color: Colors.white30, fontSize: 13),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF00D2C4), size: 18),
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.04)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00D2C4), width: 1.2),
      ),
    );
  }
}
