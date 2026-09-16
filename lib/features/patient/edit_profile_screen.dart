import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/patient_profile.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

/// Contact-focused profile editor so patients can keep a phone number for SMS / notifications.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  PatientProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _smsConsent = true;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final care = context.read<CareRepository>();
      final profile = await care.getMyProfile();
      bool smsOn = true;
      try {
        final consents = await care.myConsents();
        final match = consents.where((r) => r['consent_type']?.toString() == 'communication');
        if (match.isNotEmpty) smsOn = match.first['accepted'] == true;
      } catch (_) {}

      if (!mounted) return;
      _profile = profile;
      _name.text = profile.fullName;
      _phone.text = profile.phoneNumber;
      _email.text = profile.email ?? '';
      _emergencyName.text = profile.emergencyName ?? '';
      _emergencyPhone.text = profile.emergencyPhone ?? '';
      setState(() {
        _smsConsent = smsOn;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Phone number is required for SMS and notifications.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final care = context.read<CareRepository>();
      final saved = await care.saveMyProfile({
        'full_name': _name.text.trim(),
        'phone_number': phone,
        'email': _email.text.trim(),
        'emergency_name': _emergencyName.text.trim(),
        'emergency_phone': _emergencyPhone.text.trim(),
      });
      try {
        await care.saveConsent('communication', accepted: _smsConsent);
      } catch (_) {}

      if (!mounted) return;
      final session = context.read<Session>();
      if (session.user != null) {
        session.patchUser(session.user!.copyWith(
          name: saved.fullName,
          phoneNumber: saved.phoneNumber,
          email: saved.email,
          patientCode: saved.patientCode,
        ));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved. SMS and notifications will use this phone number.'),
        ),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _profile?.patientCode ?? context.watch<Session>().user?.patientCode;

    return Scaffold(
      backgroundColor: digiPaper,
      appBar: AppBar(
        title: Text('Edit profile', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: digiPaper,
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (code != null && code.isNotEmpty)
                  DigiCard(
                    child: Row(
                      children: [
                        const Icon(Icons.badge_outlined, color: digiForest, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Patient ID', style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
                              Text(code, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Keep your phone number current so Medilynks can reach you by SMS about visits, queue updates, and results.',
                  style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 18),
                Text('Contact', style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _field(_name, 'Full name', Icons.person_outline),
                _field(
                  _phone,
                  'Phone number (SMS)',
                  Icons.sms_outlined,
                  keyboard: TextInputType.phone,
                  helper: 'Primary number for SMS and login by phone',
                ),
                _field(_email, 'Email (optional)', Icons.email_outlined, keyboard: TextInputType.emailAddress),
                const SizedBox(height: 8),
                Text('Emergency contact', style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _field(_emergencyName, 'Emergency contact name', Icons.contact_emergency_outlined),
                _field(
                  _emergencyPhone,
                  'Emergency contact phone',
                  Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                DigiCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'SMS & notifications',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: digiInk),
                    ),
                    subtitle: Text(
                      'Allow messages about visits, queue status, and results.',
                      style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                    ),
                    value: _smsConsent,
                    activeThumbColor: digiForest,
                    onChanged: (v) => setState(() => _smsConsent = v),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/patient/consents'),
                  child: Text('Manage all consents', style: GoogleFonts.dmSans(color: digiForest)),
                ),
                TextButton(
                  onPressed: () => context.push('/patient/profile'),
                  child: Text('Edit medical profile', style: GoogleFonts.dmSans(color: digiForest)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: digiForest,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _saving ? 'Saving…' : 'Save profile',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          prefixIcon: Icon(icon, size: 20, color: digiForest),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: digiLine),
          ),
        ),
      ),
    );
  }
}
