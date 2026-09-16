import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../admin/admin_chrome.dart';
import 'auth_chrome.dart';
import 'auth_repository.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _otpSent = false;
  bool _consentTele = false;
  bool _consentPrivacy = false;
  bool _consentComms = true;
  String? _debugOtp;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consentTele || !_consentPrivacy) {
      setState(() => _error = 'Accept telemedicine and privacy terms to continue.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<AuthRepository>();
      if (!_otpSent) {
        final debug = await repo.requestOtp(phone: _phone.text, purpose: 'register');
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _debugOtp = debug;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(debug != null ? 'OTP sent. Dev code: $debug' : 'OTP sent to your phone.')),
        );
        return;
      }

      final result = await repo.registerWithOtp(
        phone: _phone.text,
        code: _otp.text,
        password: _password.text,
        name: _name.text,
        email: _email.text,
        telemedicineConsent: _consentTele,
        privacyConsent: _consentPrivacy,
        communicationConsent: _consentComms,
      );
      if (!mounted) return;
      await context.read<Session>().setSession(token: result.token, user: result.user);
      if (!mounted) return;
      goHomeForRole(context, result.user.role.name);
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_phone.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final debug = await context.read<AuthRepository>().requestOtp(phone: _phone.text, purpose: 'register');
      if (!mounted) return;
      setState(() => _debugOtp = debug);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(debug != null ? 'OTP resent. Dev code: $debug' : 'A new OTP was sent.')),
      );
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
              ),
              const AuthBrandHeader(compact: true),
              const SizedBox(height: 22),
              AuthGlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _otpSent ? 'Verify your number' : 'Create your account',
                      style: GoogleFonts.sourceSerif4(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _otpSent
                          ? 'Enter the SMS code we sent to ${_phone.text.trim()}'
                          : 'Register as a patient to book visits and join live care',
                      style: GoogleFonts.dmSans(fontSize: 13, color: AdminPalette.mute, height: 1.35),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      AuthErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 18),
                    if (!_otpSent) ...[
                      TextFormField(
                        controller: _name,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        textCapitalization: TextCapitalization.words,
                        decoration: authFieldDeco('Full name', Icons.person_outline),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Full name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        decoration: authFieldDeco('Email address', Icons.email_outlined),
                        validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        decoration: authFieldDeco('Ghana mobile number', Icons.phone_outlined),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Phone number is required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        decoration: authFieldDeco('Password', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: Colors.white60,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.length < 5 ? 'Min 5 characters required' : null,
                      ),
                      const SizedBox(height: 8),
                      _ConsentTile(
                        value: _consentTele,
                        label: 'I consent to telemedicine care',
                        onChanged: (v) => setState(() => _consentTele = v),
                      ),
                      _ConsentTile(
                        value: _consentPrivacy,
                        label: 'I accept privacy and data-processing terms',
                        onChanged: (v) => setState(() => _consentPrivacy = v),
                      ),
                      _ConsentTile(
                        value: _consentComms,
                        label: 'Send me SMS, email and push updates',
                        onChanged: (v) => setState(() => _consentComms = v),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.dmSans(color: Colors.white, letterSpacing: 4, fontSize: 18),
                        textAlign: TextAlign.center,
                        decoration: authFieldDeco('6-digit OTP', Icons.lock_clock_outlined),
                        validator: (v) => v == null || v.trim().length < 4 ? 'Enter the OTP' : null,
                      ),
                      if (_debugOtp != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Dev OTP: $_debugOtp',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmSans(color: AdminPalette.cyan, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _loading ? null : _resend,
                          child: Text(
                            'Resend code',
                            style: GoogleFonts.dmSans(color: AdminPalette.violet, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AuthPrimaryButton(
                      label: _otpSent ? 'Verify & join Medilynks' : 'Send verification code',
                      onPressed: _submit,
                      loading: _loading,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text(
                        'Already have an account? Sign in',
                        style: GoogleFonts.dmSans(color: AdminPalette.cyan, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({required this.value, required this.label, required this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: AdminPalette.cyan,
      checkColor: Colors.black,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 12, height: 1.3)),
    );
  }
}
