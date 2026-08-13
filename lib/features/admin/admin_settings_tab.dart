import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminSettingsTab extends StatelessWidget {
  const AdminSettingsTab({
    super.key,
    required this.clinicName,
    required this.smsBaseUrl,
    required this.smsSenderId,
    required this.smsApiKey,
    required this.onSave,
    required this.fieldDecoration,
    this.opsSummary,
  });

  final TextEditingController clinicName;
  final TextEditingController smsBaseUrl;
  final TextEditingController smsSenderId;
  final TextEditingController smsApiKey;
  final VoidCallback onSave;
  final InputDecoration Function(String, IconData) fieldDecoration;
  final Map<String, dynamic>? opsSummary;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (opsSummary != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Operations snapshot', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'Active care programs: ${opsSummary!['active_programs'] ?? 0} · Vault records: ${opsSummary!['vault_documents'] ?? 0}',
                    style: GoogleFonts.roboto(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Clinic & SMS gateway', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  'The API key is never returned in full. Leave the masked field unchanged unless you are rotating the key.',
                  style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(controller: clinicName, decoration: fieldDecoration('Clinic display name', Icons.home_work_outlined)),
                const SizedBox(height: 10),
                TextField(controller: smsBaseUrl, decoration: fieldDecoration('SMS gateway URL', Icons.link_rounded)),
                const SizedBox(height: 10),
                TextField(controller: smsSenderId, decoration: fieldDecoration('Sender ID', Icons.abc_outlined)),
                const SizedBox(height: 10),
                TextField(controller: smsApiKey, obscureText: true, decoration: fieldDecoration('Gateway API token', Icons.key_rounded)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2C4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
