import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'admin_chrome.dart';

class AdminSettingsTab extends StatelessWidget {
  const AdminSettingsTab({
    super.key,
    required this.clinicName,
    required this.smsBaseUrl,
    required this.smsSenderId,
    required this.smsApiKey,
    required this.paystackPublicKey,
    required this.paystackSecretKey,
    required this.onSave,
    required this.fieldDecoration,
    this.opsSummary,
  });

  final TextEditingController clinicName;
  final TextEditingController smsBaseUrl;
  final TextEditingController smsSenderId;
  final TextEditingController smsApiKey;
  final TextEditingController paystackPublicKey;
  final TextEditingController paystackSecretKey;
  final VoidCallback onSave;
  final InputDecoration Function(String, IconData) fieldDecoration;
  final Map<String, dynamic>? opsSummary;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (opsSummary != null) ...[
            AdminGlass(
              glow: AdminPalette.cyan,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AdminLiveDot(),
                      const SizedBox(width: 8),
                      Text('Operations snapshot', style: adminSerif(size: 18)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Active care programs: ${opsSummary!['active_programs'] ?? 0}  ·  Vault records: ${opsSummary!['vault_documents'] ?? 0}',
                    style: adminSans(size: 13, color: AdminPalette.mute),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 380.ms),
            const SizedBox(height: 14),
          ],
          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Clinic & SMS gateway', style: adminSerif(size: 20)),
                const SizedBox(height: 6),
                Text(
                  'The API key is never returned in full. Leave the masked field unchanged unless you are rotating the key.',
                  style: adminSans(size: 12, color: AdminPalette.mute, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(controller: clinicName, style: adminSans(), decoration: fieldDecoration('Clinic display name', Icons.home_work_outlined)),
                const SizedBox(height: 10),
                TextField(controller: smsBaseUrl, style: adminSans(), decoration: fieldDecoration('SMS gateway URL', Icons.link_rounded)),
                const SizedBox(height: 10),
                TextField(controller: smsSenderId, style: adminSans(), decoration: fieldDecoration('Sender ID', Icons.abc_outlined)),
                const SizedBox(height: 10),
                TextField(controller: smsApiKey, obscureText: true, style: adminSans(), decoration: fieldDecoration('Gateway API token', Icons.key_rounded)),
                const SizedBox(height: 22),
                Text('Paystack', style: adminSerif(size: 20)),
                const SizedBox(height: 6),
                Text(
                  'Use a matching pair: pk_test_ with sk_test_, or pk_live_ with sk_live_. Secret is never returned in full.',
                  style: adminSans(size: 12, color: AdminPalette.mute, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(controller: paystackPublicKey, style: adminSans(), decoration: fieldDecoration('Paystack public key (pk_…)', Icons.public_rounded)),
                const SizedBox(height: 10),
                TextField(controller: paystackSecretKey, obscureText: true, style: adminSans(), decoration: fieldDecoration('Paystack secret key (sk_…)', Icons.lock_rounded)),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save settings'),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 400.ms),
        ],
      ),
    );
  }
}
