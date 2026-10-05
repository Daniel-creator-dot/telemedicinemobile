import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'auth_chrome.dart';
import 'auth_repository.dart';
import 'ghana_phone.dart';

enum _JoinKind { doctor, nurse, agency }

const _specializations = [
  'General practice',
  'Paediatrics',
  'Internal medicine',
  'Obstetrics',
  'Mental health',
  'Other',
];

const _practiceAreas = [
  'General nursing',
  'Midwifery',
  'Triage',
  'Community',
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
  final _country = TextEditingController();

  _JoinKind _kind = _JoinKind.doctor;
  String? _specialization;
  String? _practiceArea;
  String? _region;
  bool _outsideGhana = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _password, _license, _facility, _agencyName, _town, _address, _country]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _password, _license, _facility, _agencyName, _town, _address, _country]) {
      c.removeListener(_refresh);
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty || _password.text.length < 8) {
      return false;
    }
    switch (_kind) {
      case _JoinKind.doctor:
        return _specialization != null;
      case _JoinKind.nurse:
        return _practiceArea != null;
      case _JoinKind.agency:
        if (_agencyName.text.trim().isEmpty || _town.text.trim().isEmpty) return false;
        if (_outsideGhana) return _country.text.trim().isNotEmpty;
        return _region != null;
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_ready) {
      setState(() => _error = 'Enter the required details to continue.');
      return;
    }
    if (normalizeAccountPhone(_phone.text) == null) {
      setState(() => _error = 'Use a Ghana number, or include a country code such as +1');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<AuthRepository>();
      final AuthResult result;
      switch (_kind) {
        case _JoinKind.doctor:
          result = await repo.signupDoctor(
            fullName: _name.text,
            phone: _phone.text,
            password: _password.text,
            specialization: _specialization!,
            licenseNumber: _license.text,
            facility: _facility.text,
          );
        case _JoinKind.nurse:
          result = await repo.signupNurse(
            fullName: _name.text,
            phone: _phone.text,
            password: _password.text,
            practiceArea: _practiceArea!,
            licenseNumber: _license.text,
            facility: _facility.text,
          );
        case _JoinKind.agency:
          result = await repo.signupAgency(
            fullName: _name.text,
            phone: _phone.text,
            password: _password.text,
            agencyName: _agencyName.text,
            region: _outsideGhana ? 'Other country' : _region!,
            town: _town.text,
            address: _address.text,
            country: _outsideGhana ? _country.text : 'Ghana',
          );
      }
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
                      'Register as a doctor, as a nurse who will practice on Healynks, or as the nurse agency you run. You can sign in while Healynks reviews the profile.',
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
                  _kindHint,
                  style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4),
                ),
                const SizedBox(height: 16),
                _field(_name, _kind == _JoinKind.agency ? 'Nurse full name' : 'Full name', TextInputType.name),
                const SizedBox(height: 12),
                _field(_phone, 'Mobile number', TextInputType.phone),
                const SizedBox(height: 12),
                _passwordField(),
                const SizedBox(height: 12),
                if (_kind == _JoinKind.doctor) ...[
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
                ] else if (_kind == _JoinKind.nurse) ...[
                  _dropdown(
                    label: 'Unit or area of practice',
                    value: _practiceArea,
                    items: _practiceAreas,
                    onChanged: (v) => setState(() => _practiceArea = v),
                  ),
                  const SizedBox(height: 12),
                  _field(_license, 'License or council number (optional)', TextInputType.text),
                  const SizedBox(height: 12),
                  _field(_facility, 'Facility (optional)', TextInputType.text),
                ] else ...[
                  _field(_agencyName, 'Agency name', TextInputType.text),
                  const SizedBox(height: 12),
                  _dropdown(
                    label: 'Where the agency operates',
                    value: _outsideGhana ? 'Other country' : 'Ghana',
                    items: const ['Ghana', 'Other country'],
                    onChanged: (v) => setState(() {
                      _outsideGhana = v == 'Other country';
                      if (!_outsideGhana) _country.clear();
                      if (_outsideGhana) _region = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (_outsideGhana)
                    _field(_country, 'Country', TextInputType.text)
                  else
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
                  label: _submitLabel,
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

  String get _kindHint {
    switch (_kind) {
      case _JoinKind.doctor:
        return 'Your name, a mobile number, and a specialty. License and facility can wait.';
      case _JoinKind.nurse:
        return 'Your name, a mobile number, and where you practice. License and facility can wait.';
      case _JoinKind.agency:
        return 'The nurse who will sign in, and the agency they run.';
    }
  }

  String get _submitLabel {
    switch (_kind) {
      case _JoinKind.doctor:
        return 'Create doctor account';
      case _JoinKind.nurse:
        return 'Create nurse account';
      case _JoinKind.agency:
        return 'Create agency account';
    }
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
          _choice('Nurse', _JoinKind.nurse),
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
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.2,
                  color: selected ? healynksBlue : digiSlate,
                ),
              ),
            ),
        ),
      ),
    );
  }
}
