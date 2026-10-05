import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/brand.dart';
import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../homecare/home_care_logic.dart';
import 'auth_chrome.dart';
import 'auth_repository.dart';

enum _AuthMode { signIn, forgot, reset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _otpCode = TextEditingController();
  final _newPassword = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _otpCode.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  String? _safeNext() {
    try {
      if (GoRouter.maybeOf(context) == null) return null;
      return homeCareJobPath(GoRouterState.of(context).uri.queryParameters['next']);
    } catch (_) {
      return null;
    }
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = context.read<AuthRepository>();
      final session = context.read<Session>();

      switch (_mode) {
        case _AuthMode.signIn:
          final result = await repo.login(
            username: _username.text,
            password: _password.text,
          );
          await session.setSession(token: result.token, user: result.user);
          if (!mounted) return;
          final next = _safeNext();
          if (next != null) {
            context.go(next);
          } else {
            goHomeForRole(context, result.user.role.name);
          }
        case _AuthMode.forgot:
          await repo.forgotPassword(_username.text);
          if (!mounted) return;
          setState(() {
            _mode = _AuthMode.reset;
            _error = null;
            _notice = 'If an account matches, a reset code is on its way by text.';
          });
        case _AuthMode.reset:
          await repo.resetPassword(
            username: _username.text,
            code: _otpCode.text,
            newPassword: _newPassword.text,
          );
          if (!mounted) return;
          setState(() {
            _mode = _AuthMode.signIn;
            _error = null;
            _notice = 'Password saved. Sign in with the new one.';
            _password.clear();
            _otpCode.clear();
            _newPassword.clear();
          });
      }
    } catch (e) {
      setState(() {
        _notice = null;
        _error = AuthRepository.errorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign in';
      case _AuthMode.forgot:
        return 'Reset your password';
      case _AuthMode.reset:
        return 'Choose a new password';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _AuthMode.signIn:
        return AppBrand.tagline;
      case _AuthMode.forgot:
        return 'We will text a code to the mobile number on the account.';
      case _AuthMode.reset:
        return 'Enter the code from the text, then choose a password.';
    }
  }

  String get _primaryLabel {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign in';
      case _AuthMode.forgot:
        return 'Send reset code';
      case _AuthMode.reset:
        return 'Save new password';
    }
  }

  String get _loadingLabel {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Signing in…';
      case _AuthMode.forgot:
        return 'Sending the code…';
      case _AuthMode.reset:
        return 'Saving the password…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignIn = _mode == _AuthMode.signIn;
    final isReset = _mode == _AuthMode.reset;

    final width = MediaQuery.sizeOf(context).width;
    final short = MediaQuery.sizeOf(context).height < 700;
    final horizontal = width < 380 ? 12.0 : 20.0;
    // The phone header already shows the tagline. Repeating it in the card
    // pushed Forgot password and Create account below a short screen.
    final showSubtitle = !isSignIn || width >= 960;
    return AuthScaffold(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontal, short ? 8 : 24, horizontal, short ? 16 : 32),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              AuthBrandHeader(compact: short),
              SizedBox(height: short ? 10 : 20),
              AuthGlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_title, style: clinicalDisplay(short ? 24 : 28)),
                    if (showSubtitle) ...[
                      const SizedBox(height: 8),
                      Text(
                        _subtitle,
                        style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.45),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      AuthErrorBanner(message: _error!),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      AuthNoticeBanner(message: _notice!),
                    ],
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _username,
                      style: GoogleFonts.dmSans(color: digiInk),
                      textInputAction: isSignIn ? TextInputAction.next : TextInputAction.done,
                      decoration: authFieldDeco('Username or phone', Icons.account_circle_outlined),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Enter the username or phone number on the account.' : null,
                    ),
                    if (isSignIn) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        style: GoogleFonts.dmSans(color: digiInk),
                        onFieldSubmitted: (_) => _submit(),
                        decoration: authFieldDeco('Password', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: digiSlate,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Enter your password.' : null,
                      ),
                    ],
                    if (isReset) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otpCode,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.dmSans(color: digiInk),
                        decoration: authFieldDeco('Code from the text', Icons.lock_clock_outlined),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter the code from the text.' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPassword,
                        obscureText: _obscure,
                        style: GoogleFonts.dmSans(color: digiInk),
                        decoration: authFieldDeco('New password', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: digiSlate,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.length < 5 ? 'Use at least 5 characters.' : null,
                      ),
                    ],
                    const SizedBox(height: 20),
                    AuthPrimaryButton(
                      label: _primaryLabel,
                      loadingLabel: _loadingLabel,
                      onPressed: _submit,
                      loading: _loading,
                    ),
                    const SizedBox(height: 4),
                    if (isSignIn) ...[
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () => _setMode(_AuthMode.forgot),
                          child: Text(
                            'Forgot password?',
                            style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClinicalSecondaryButton(
                        label: 'Create a patient account',
                        onPressed: () => context.go('/signup'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/signup/simple'),
                        child: Text(
                          'Need a simpler signup?',
                          style: GoogleFonts.dmSans(color: digiForest, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ] else ...[
                      TextButton(
                        onPressed: () => _setMode(_AuthMode.signIn),
                        child: Text(
                          'Back to sign in',
                          style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_mode == _AuthMode.forgot)
                        TextButton(
                          onPressed: () => _setMode(_AuthMode.reset),
                          child: Text(
                            'I already have a code',
                            style: GoogleFonts.dmSans(color: digiForest, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (isSignIn) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () {
                    final next = _safeNext();
                    if (next == null) {
                      context.go('/join');
                    } else {
                      context.go(
                        Uri(
                          path: '/join',
                          queryParameters: {'as': 'nurse', 'next': next},
                        ).toString(),
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: digiForest,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  child: Text(
                    'Join as a doctor, nurse, or nurse agency',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(color: digiForest, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
