import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/brand.dart';
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
    return Scaffold(
      backgroundColor: digiPaper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loading ? null : () => context.go('/login'),
                    icon: const Icon(Icons.arrow_back, size: 18, color: digiForest),
                    label: Text('Sign in', style: GoogleFonts.dmSans(color: digiForest, fontWeight: FontWeight.w700)),
                  ),
                ),
                Text(
                  AppBrand.name,
                  style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w700, color: digiForest),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join the clinic',
                  style: GoogleFonts.sourceSerif4(fontSize: 34, fontWeight: FontWeight.w700, color: digiInk, height: 1.05),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a doctor account, or register the telemedicine agency you run. You can sign in right away.',
                  style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.4),
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
                const SizedBox(height: 18),
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
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8E8E4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF8C3A2F), fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                ] else if (!_ready && !_loading) ...[
                  Text(
                    'Enter the required details to continue.',
                    style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading || !_ready ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: digiForest,
                      disabledBackgroundColor: digiForest.withValues(alpha: 0.35),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            doctor ? 'Create doctor account' : 'Create agency account',
                            style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

  InputDecoration _deco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: digiLine)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: digiLine)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: digiForest, width: 1.5),
      ),
    );
  }
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: digiLine),
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
        color: selected ? digiForest : Colors.transparent,
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
                color: selected ? Colors.white : digiSlate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
