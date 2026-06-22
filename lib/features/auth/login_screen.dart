import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import 'auth_repository.dart';

enum _AuthMode { signIn, signUp, forgot, reset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _email = TextEditingController();
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
    _name.dispose();
    _phoneNumber.dispose();
    _email.dispose();
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
          _navigateHome(result.user.role.name);
          break;

        case _AuthMode.signUp:
          await repo.register(
            username: _username.text,
            password: _password.text,
            name: _name.text,
            phoneNumber: _phoneNumber.text,
            email: _email.text,
          );
          // After successful signup, auto-login
          final loginResult = await repo.login(
            username: _username.text,
            password: _password.text,
          );
          await session.setSession(token: loginResult.token, user: loginResult.user);
          if (!mounted) return;
          _navigateHome(loginResult.user.role.name);
          break;

        case _AuthMode.forgot:
          await repo.forgotPassword(_username.text);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP sent to registered phone number.')),
          );
          _setMode(_AuthMode.reset);
          break;

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
          break;
      }
    } catch (e) {
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateHome(String role) {
    if (role == 'doctor') {
      context.go('/doctor');
    } else if (role == 'admin') {
      context.go('/admin');
    } else if (role == 'lab_technician') {
      context.go('/lab-technician');
    } else {
      context.go('/patient');
    }
  }

  String get _primaryLabel {
    switch (_mode) {
      case _AuthMode.signIn:
        return 'Sign In';
      case _AuthMode.signUp:
        return 'Create Account';
      case _AuthMode.forgot:
        return 'Send OTP';
      case _AuthMode.reset:
        return 'Reset Password';
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ = Theme.of(context); // Keep context-aware rebuild; see _inputDeco
    final isSignIn = _mode == _AuthMode.signIn;
    final isSignUp = _mode == _AuthMode.signUp;
    final isForgot = _mode == _AuthMode.forgot;
    final isReset = _mode == _AuthMode.reset;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background photo provided by the user
          Image.asset(
            'assets/branding/hero_login.png',
            fit: BoxFit.cover,
          ),
          // Subtle gradient overlays for readibility
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.85),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    // Brand icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00D2C4).withOpacity(0.15),
                        border: Border.all(color: const Color(0xFF00D2C4).withOpacity(0.4), width: 2),
                      ),
                      child: const Icon(Icons.public_rounded, color: Color(0xFF00D2C4), size: 42),
                    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.85, 0.85)),
                    const SizedBox(height: 20),
                    Text(
                      'DIGI HEALTH',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),
                    Text(
                      'Universal Telehealth Portal',
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF00D2C4),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 50),

                    // Glassmorphic Input Container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            isSignIn
                                ? 'Welcome Back'
                                : isSignUp
                                    ? 'Join Digi Health'
                                    : isForgot
                                        ? 'Forgot Password'
                                        : 'Reset Password',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isSignIn
                                ? 'Sign in to access your clinical dashboard'
                                : isSignUp
                                    ? 'Register as a patient to schedule visits'
                                    : isForgot
                                        ? 'Enter your username to receive an SMS verification code'
                                        : 'Enter the verification code & your new password',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 15),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ).animate().shake(),
                          ],
                          const SizedBox(height: 20),

                          // Form fields based on mode
                          if (isSignUp) ...[
                            TextFormField(
                              controller: _name,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('Full Name', Icons.person_outline),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Full name is required'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('Email Address', Icons.email_outlined),
                              validator: (v) => v == null || !v.contains('@')
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phoneNumber,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('Phone Number', Icons.phone_outlined),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Phone number is required'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Username field used in sign in, sign up, forgot, reset
                          TextFormField(
                            controller: _username,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDeco('Username', Icons.account_circle_outlined),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Username is required'
                                : null,
                          ),

                          if (isReset) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _otpCode,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('OTP Verification Code', Icons.lock_clock_outlined),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter verification code'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _newPassword,
                              obscureText: _obscure,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('New Password', Icons.lock_outline),
                              validator: (v) => v == null || v.length < 5
                                  ? 'Min 5 characters required'
                                  : null,
                            ),
                          ],

                          if (isSignIn || isSignUp) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDeco('Password', Icons.lock_outline).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    color: Colors.white60,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) => v == null || v.length < 4
                                  ? 'Enter a valid password'
                                  : null,
                            ),
                          ],

                          const SizedBox(height: 25),

                          // Submit Button
                          ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00D2C4),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : Text(
                                    _primaryLabel,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 15),

                          // Toggles for modes
                          if (isSignIn) ...[
                            Center(
                              child: TextButton(
                                onPressed: () => _setMode(_AuthMode.forgot),
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 13),
                                ),
                              ),
                            ),
                          ] else if (isSignUp) ...[
                            Center(
                              child: TextButton(
                                onPressed: () => _setMode(_AuthMode.signIn),
                                child: const Text(
                                  'Already have an account? Sign In',
                                  style: TextStyle(color: Color(0xFF00D2C4), fontSize: 13),
                                ),
                              ),
                            ),
                          ] else if (isForgot) ...[
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () => _setMode(_AuthMode.signIn),
                                  child: const Text(
                                    'Back to Sign In',
                                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _setMode(_AuthMode.reset),
                                  child: const Text(
                                    'Enter Code',
                                    style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (isReset) ...[
                            Center(
                              child: TextButton(
                                onPressed: () => _setMode(_AuthMode.signIn),
                                child: const Text(
                                  'Back to Sign In',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.05, end: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hintText, IconData prefixIcon) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF00D2C4), size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF00D2C4), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.withOpacity(0.3)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }
}
