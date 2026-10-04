import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../admin/admin_chrome.dart';
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

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _otpCode.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
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
          goHomeForRole(context, result.user.role.name);
        case _AuthMode.forgot:
          await repo.forgotPassword(_username.text);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('If an account exists, a reset code has been sent.')),
          );
          _setMode(_AuthMode.reset);
        case _AuthMode.reset:
          await repo.resetPassword(
            username: _username.text,
            code: _otpCode.text,
            newPassword: _newPassword.text,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset successful. Please sign in.')),
          );
          _setMode(_AuthMode.signIn);
      }
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Welcome back';
      case _AuthMode.forgot:
        return 'Forgot password';
      case _AuthMode.reset:
        return 'Reset password';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign in to your clinical workspace';
      case _AuthMode.forgot:
        return 'Enter your username or phone to receive an SMS code';
      case _AuthMode.reset:
        return 'Enter the verification code and a new password';
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

  @override
  Widget build(BuildContext context) {
    final isSignIn = _mode == _AuthMode.signIn;
    final isReset = _mode == _AuthMode.reset;

    return AuthScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 18),
              const AuthBrandHeader(),
              const SizedBox(height: 32),
              AuthGlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _title,
                      style: GoogleFonts.sourceSerif4(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: GoogleFonts.dmSans(fontSize: 13, color: AdminPalette.mute, height: 1.35),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      AuthErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _username,
                      style: GoogleFonts.dmSans(color: Colors.white),
                      textInputAction: isSignIn ? TextInputAction.next : TextInputAction.done,
                      decoration: authFieldDeco(
                        isSignIn ? 'Username or phone' : 'Username',
                        Icons.account_circle_outlined,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Username is required' : null,
                    ),
                    if (isSignIn) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        onFieldSubmitted: (_) => _submit(),
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
                        validator: (v) => v == null || v.length < 4 ? 'Enter a valid password' : null,
                      ),
                    ],
                    if (isReset) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otpCode,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        decoration: authFieldDeco('OTP from SMS', Icons.lock_clock_outlined),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter verification code' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _newPassword,
                        obscureText: _obscure,
                        style: GoogleFonts.dmSans(color: Colors.white),
                        decoration: authFieldDeco('New password', Icons.lock_outline).copyWith(
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
                    ],
                    const SizedBox(height: 22),
                    AuthPrimaryButton(label: _primaryLabel, onPressed: _submit, loading: _loading),
                    const SizedBox(height: 10),
                    if (isSignIn) ...[
                      TextButton(
                        onPressed: () => _setMode(_AuthMode.forgot),
                        child: Text(
                          'Forgot password?',
                          style: GoogleFonts.dmSans(color: AdminPalette.violet, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('New patient?', style: GoogleFonts.dmSans(color: AdminPalette.mute, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.go('/signup'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AdminPalette.cyan,
                            side: BorderSide(color: AdminPalette.cyan.withValues(alpha: 0.55)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text('Create an account', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                    ] else ...[
                      TextButton(
                        onPressed: () => _setMode(_AuthMode.signIn),
                        child: Text(
                          'Back to sign in',
                          style: GoogleFonts.dmSans(color: AdminPalette.mute, fontSize: 13),
                        ),
                      ),
                      if (_mode == _AuthMode.forgot)
                        TextButton(
                          onPressed: () => _setMode(_AuthMode.reset),
                          child: Text(
                            'I already have a code',
                            style: GoogleFonts.dmSans(color: AdminPalette.violet, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
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
