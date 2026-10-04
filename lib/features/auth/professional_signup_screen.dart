import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'auth_chrome.dart';
import 'auth_repository.dart';
import 'ghana_phone.dart';

enum _JoinKind { doctor, agency }

const _specializations = [
  'General practice',
  'Paediatrics',
  'Internal medicine',
  'Obstetrics',
  'Mental health',
  'Other',
];

const _regions = [
  'Greater Accra',
  'Ashanti',
  'Western',
  'Western North',
  'Central',
  'Eastern',
  'Volta',
  'Oti',
  'Northern',
  'Savannah',
  'North East',
  'Upper East',
  'Upper West',
  'Bono',
  'Bono East',
  'Ahafo',
];

class ProfessionalSignupScreen extends StatefulWidget {
  const ProfessionalSignupScreen({super.key});

  @override
  State<ProfessionalSignupScreen> createState() => _ProfessionalSignupScreenState();
}

class _ProfessionalSignupScreenState extends State<ProfessionalSignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _license = TextEditingController();
  final _facility = TextEditingController();
  final _agencyName = TextEditingController();
  final _town = TextEditingController();
  final _address = TextEditingController();

  _JoinKind _kind = _JoinKind.doctor;
  String? _specialization;
  String? _region;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _password, _license, _facility, _agencyName, _town, _address]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _password, _license, _facility, _agencyName, _town, _address]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty || _password.text.length < 8) {
      return false;
    }
    if (_kind == _JoinKind.doctor) return _specialization != null;
    return _agencyName.text.trim().isNotEmpty && _region != null && _town.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_ready) {
      setState(() => _error = 'Enter the required details to continue.');
      return;
    }
    if (normalizeGhanaPhone(_phone.text) == null) {
      setState(() => _error = 'Enter a valid Ghana mobile number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<AuthRepository>();
      final result = _kind == _JoinKind.doctor
          ? await repo.signupDoctor(
              fullName: _name.text,
              phone: _phone.text,
              password: _password.text,
              specialization: _specialization!,
              licenseNumber: _license.text,
              facility: _facility.text,
            )
          : await repo.signupAgency(
              fullName: _name.text,
              phone: _phone.text,
              password: _password.text,
              agencyName: _agencyName.text,
              region: _region!,
              town: _town.text,
              address: _address.text,
            );
      if (!mounted) return;
      await context.read<Session>().setSession(token: result.token, user: result.user);
      if (!mounted) return;
      goHomeForRole(context, result.user.role.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctor = _kind == _JoinKind.doctor;
    return AuthScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : () => context.go('/login'),
              icon: const Icon(Icons.arrow_back, size: 18, color: digiForest),
              label: Text('Sign in', style: GoogleFonts.dmSans(color: digiForest, fontWeight: FontWeight.w600)),
            ),
          ),
          const AuthBrandHeader(compact: true),
          const SizedBox(height: 8),
          AuthGlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ClinicalPageHeader(
                  title: 'Join Healynks',
                  subtitle:
                      'Register as a doctor, or as the nurse agency you run. You can sign in while Healynks reviews the profile.',
                ),
                const SizedBox(height: 20),
                _KindSwitch(
                  kind: _kind,
                  onChanged: _loading
                      ? null
                      : (kind) => setState(() {
                            _kind = kind;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 8),
                Text(
                  doctor
                      ? 'Your name, a Ghana number, and a specialty. License and facility can wait.'
                      : 'The nurse who will sign in, and the agency they represent.',
                  style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4),
                ),
                const SizedBox(height: 16),
                _field(_name, doctor ? 'Full name' : 'Nurse full name', TextInputType.name),
                const SizedBox(height: 12),
                _field(_phone, 'Ghana mobile number', TextInputType.phone),
                const SizedBox(height: 12),
                _passwordField(),
                const SizedBox(height: 12),
                if (doctor) ...[
                  _dropdown(
                    label: 'Specialization',
                    value: _specialization,
                    items: _specializations,
                    onChanged: (v) => setState(() => _specialization = v),
                  ),
                  const SizedBox(height: 12),
                  _field(_license, 'License number (optional)', TextInputType.text),
                  const SizedBox(height: 12),
                  _field(_facility, 'Facility (optional)', TextInputType.text),
                ] else ...[
                  _field(_agencyName, 'Agency name', TextInputType.text),
                  const SizedBox(height: 12),
                  _dropdown(
                    label: 'Region',
                    value: _region,
                    items: _regions,
                    onChanged: (v) => setState(() => _region = v),
                  ),
                  const SizedBox(height: 12),
                  _field(_town, 'Town', TextInputType.text),
                  const SizedBox(height: 12),
                  _field(_address, 'Address (optional)', TextInputType.streetAddress),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  AuthErrorBanner(message: _error!),
                ],
                const SizedBox(height: 20),
                ClinicalPrimaryButton(
                  label: doctor ? 'Create doctor account' : 'Create agency account',
                  onPressed: _loading || !_ready ? null : _submit,
                  loading: _loading,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _password,
      obscureText: _obscure,
      style: GoogleFonts.dmSans(color: digiInk),
      decoration: _deco('Password (min 8 characters)').copyWith(
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: digiSlate, size: 20),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, TextInputType type) {
    return TextField(
      controller: controller,
      keyboardType: type,
      textCapitalization: type == TextInputType.name || type == TextInputType.streetAddress
          ? TextCapitalization.words
          : TextCapitalization.none,
      style: GoogleFonts.dmSans(color: digiInk),
      decoration: _deco(label),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: Colors.white,
      style: GoogleFonts.dmSans(color: digiInk, fontSize: 14),
      decoration: _deco(label),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
      onChanged: _loading ? null : onChanged,
    );
  }

  InputDecoration _deco(String label) => clinicalFieldDecoration(label);
}

class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final _JoinKind kind;
  final ValueChanged<_JoinKind>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF5),
        borderRadius: BorderRadius.circular(clinicalButtonRadius),
      ),
      child: Row(
        children: [
          _choice('Doctor', _JoinKind.doctor),
          _choice('Nurse agency', _JoinKind.agency),
        ],
      ),
    );
  }

  Widget _choice(String label, _JoinKind value) {
    final selected = kind == value;
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        elevation: 0,
        shadowColor: const Color(0x140E1525),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(value),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: selected ? healynksBlue : digiSlate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
