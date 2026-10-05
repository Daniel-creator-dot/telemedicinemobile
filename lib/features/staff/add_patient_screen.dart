import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../auth/auth_chrome.dart';
import '../auth/ghana_phone.dart';

class _AddedPatient {
  const _AddedPatient({required this.name, required this.phone});
  final String name;
  final String phone;
}

/// Staff create a patient record for someone who cannot sign up alone.
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _familyName = TextEditingController();
  final _familyPhone = TextEditingController();
  final _town = TextEditingController();

  bool _loading = false;
  bool _listLoading = true;
  String? _error;
  String? _notice;
  String? _signInPassword;
  String? _signInPhone;
  List<_AddedPatient> _added = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _familyName.dispose();
    _familyPhone.dispose();
    _town.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().dio.get<Map<String, dynamic>>('/api/patients/onboard');
      final raw = res.data?['patients'];
      final list = <_AddedPatient>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          list.add(
            _AddedPatient(
              name: item['full_name']?.toString() ?? '',
              phone: item['phone_number']?.toString() ?? '',
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _added = list;
        _listLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listLoading = false;
        _error = _message(e, 'We could not load the patients you added.');
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Enter the patient's full name.");
      return;
    }
    if (normalizeAccountPhone(phone) == null) {
      setState(() => _error = "Enter the patient's mobile number.");
      return;
    }
    final familyPhone = _familyPhone.text.trim();
    if (familyPhone.isNotEmpty && normalizeAccountPhone(familyPhone) == null) {
      setState(() => _error = 'Enter a family mobile number, or leave it blank.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _signInPassword = null;
      _signInPhone = null;
    });
    try {
      final res = await context.read<ApiClient>().dio.post<Map<String, dynamic>>(
        '/api/patients/onboard',
        data: {
          'full_name': name,
          'phone': phone,
          if (_familyName.text.trim().isNotEmpty) 'family_name': _familyName.text.trim(),
          if (familyPhone.isNotEmpty) 'family_phone': familyPhone,
          if (_town.text.trim().isNotEmpty) 'town': _town.text.trim(),
        },
      );
      if (!mounted) return;
      final sent = res.data?['sms_sent'] == true;
      final savedPhone = res.data?['patient']?['phone_number']?.toString() ?? phone;
      final password = res.data?['sign_in_password']?.toString() ?? '';
      setState(() {
        _signInPassword = password;
        _signInPhone = savedPhone;
        _notice = sent
            ? 'We texted $savedPhone. They sign in with this phone.'
            : 'Saved. We could not send a text. They can still sign in with this phone.';
      });
      _name.clear();
      _phone.clear();
      _familyName.clear();
      _familyPhone.clear();
      _town.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(e, 'We could not save this patient. Try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object err, String fallback) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, fallback);
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: healynksCanvas,
      appBar: AppBar(
        title: const Text('Add a patient'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                DigiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Who is the patient?', style: clinicalDisplay(22)),
                      const SizedBox(height: 8),
                      Text(
                        'We save their care record and a sign-in they can use with this phone.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 15, height: 1.4, color: healynksInk),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        AuthErrorBanner(message: _error!),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 14),
                        AuthNoticeBanner(message: _notice!),
                        if (_signInPassword != null && _signInPassword!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Password to read to them',
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: healynksInk),
                          ),
                          const SizedBox(height: 4),
                          Text(_signInPassword!, style: clinicalDisplay(28)),
                          if (_signInPhone != null)
                            Text(
                              'Phone: $_signInPhone',
                              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: healynksInk),
                            ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      _field(_name, 'Patient full name', TextInputType.name),
                      const SizedBox(height: 12),
                      _field(_phone, 'Mobile number', TextInputType.phone),
                      const SizedBox(height: 12),
                      _field(_familyName, 'Family contact name (optional)', TextInputType.name),
                      const SizedBox(height: 12),
                      _field(_familyPhone, 'Family phone (optional)', TextInputType.phone),
                      const SizedBox(height: 12),
                      _field(_town, 'Town (optional)', TextInputType.text),
                      const SizedBox(height: 18),
                      ClinicalPrimaryButton(
                        label: 'Save patient',
                        loadingLabel: 'Saving',
                        loading: _loading,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('Patients you added', style: clinicalDisplay(22)),
                const SizedBox(height: 10),
                if (_listLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_added.isEmpty)
                  DigiCard(
                    child: Text(
                      'No patients added yet.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, height: 1.4, color: healynksInk),
                    ),
                  )
                else
                  for (final patient in _added) ...[
                    DigiCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(patient.name, style: clinicalDisplay(18)),
                          const SizedBox(height: 4),
                          Text(
                            patient.phone,
                            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: healynksInk),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      textCapitalization: type == TextInputType.name || type == TextInputType.text
          ? TextCapitalization.words
          : TextCapitalization.none,
      style: GoogleFonts.plusJakartaSans(fontSize: 16, color: healynksInk, fontWeight: FontWeight.w600),
      decoration: clinicalFieldDecoration(label),
    );
  }
}
