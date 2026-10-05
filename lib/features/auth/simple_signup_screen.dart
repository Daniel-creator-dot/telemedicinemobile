import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'auth_chrome.dart';
import 'auth_repository.dart';
import 'ghana_phone.dart';
import 'larger_text.dart';
import 'simple_signup_step.dart';

/// One question at a time, for an older person or a family member reading aloud.
class SimpleSignupScreen extends StatefulWidget {
  const SimpleSignupScreen({super.key});

  @override
  State<SimpleSignupScreen> createState() => _SimpleSignupScreenState();
}

class _SimpleSignupScreenState extends State<SimpleSignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  int _step = 0;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _debugOtp;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _back() {
    if (_step > 0) {
      setState(() {
        _step -= 1;
        _error = null;
      });
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/signup');
    }
  }

  Future<void> _next() async {
    setState(() => _error = null);
    if (_step == 0) {
      if (_name.text.trim().isEmpty) {
        setState(() => _error = 'Please tell us your first name.');
        return;
      }
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      await _sendCode();
      return;
    }
    if (_step == 2) {
      if (_code.text.trim().length < 4) {
        setState(() => _error = 'Enter the code from the text.');
        return;
      }
      setState(() => _step = 3);
      return;
    }
    await _createAccount();
  }

  Future<void> _sendCode() async {
    if (normalizeAccountPhone(_phone.text) == null) {
      setState(() => _error = 'Enter a mobile number. Ghana numbers can start with 0.');
      return;
    }
    setState(() => _loading = true);
    try {
      final debug = await context.read<AuthRepository>().requestOtp(phone: _phone.text, purpose: 'register');
      if (!mounted) return;
      setState(() {
        _step = 2;
        _debugOtp = kDebugMode ? debug : null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthRepository.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await context.read<AuthRepository>().registerWithOtp(
            phone: _phone.text,
            code: _code.text,
            password: _password.text,
            name: _name.text.trim(),
            email: '',
            telemedicineConsent: true,
            privacyConsent: true,
            communicationConsent: true,
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
    final larger = LargerTextScope.largerOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 380 ? 16.0 : 24.0;
    return Scaffold(
      backgroundColor: healynksCanvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _loading ? null : _back,
                        iconSize: 28,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(56, 56),
                          foregroundColor: healynksInk,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      const LargerTextToggle(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Step ${_step + 1} of 4',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: simpleBodySize(larger),
                            fontWeight: FontWeight.w700,
                            color: healynksInk,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _stepBody(larger),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading ? null : () => context.go('/signup'),
                          style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
                          child: Text(
                            'Use the regular signup',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: larger ? 18 : 16,
                              fontWeight: FontWeight.w700,
                              color: healynksBlue,
                            ),
                          ),
                        ),
                      ],
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

  Widget _stepBody(bool larger) {
    final fieldStyle = GoogleFonts.plusJakartaSans(
      fontSize: simpleBodySize(larger),
      fontWeight: FontWeight.w600,
      color: healynksInk,
    );
    switch (_step) {
      case 0:
        return SimpleSignupStep(
          larger: larger,
          question: 'What is your first name?',
          body: 'This is the name we will use when we talk with you.',
          buttonLabel: 'Next',
          onPressed: _loading ? null : _next,
          error: _error,
          child: TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: fieldStyle,
            decoration: simpleFieldDecoration('First name', larger: larger),
            onSubmitted: (_) => _next(),
          ),
        );
      case 1:
        return SimpleSignupStep(
          larger: larger,
          question: 'What is your mobile number?',
          body: 'We will text you a code.',
          buttonLabel: 'Text me the code',
          loadingLabel: 'Sending the code',
          loading: _loading,
          onPressed: _loading ? null : _next,
          error: _error,
          child: TextField(
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: fieldStyle,
            decoration: simpleFieldDecoration('Mobile number', larger: larger),
            onSubmitted: (_) => _next(),
          ),
        );
      case 2:
        return SimpleSignupStep(
          larger: larger,
          question: 'What is the code in the text?',
          body: 'We will text you a code. It is a short number.',
          buttonLabel: 'Next',
          onPressed: _loading ? null : _next,
          error: _error,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: fieldStyle.copyWith(letterSpacing: 4, fontSize: simpleQuestionSize(larger)),
                decoration: simpleFieldDecoration('Code', larger: larger),
                onSubmitted: (_) => _next(),
              ),
              if (kDebugMode && _debugOtp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Dev code: $_debugOtp',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: simpleBodySize(larger),
                      fontWeight: FontWeight.w700,
                      color: healynksInk,
                    ),
                  ),
                ),
              TextButton(
                onPressed: _loading ? null : _sendCode,
                style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
                child: Text(
                  'Send the code again',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: larger ? 18 : 16,
                    fontWeight: FontWeight.w700,
                    color: healynksBlue,
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return SimpleSignupStep(
          larger: larger,
          question: 'Choose a password you can remember',
          body: 'You will type this with your mobile number when you sign in. By continuing, you agree to care by phone or video, and to texts about your care.',
          buttonLabel: 'Create my account',
          loadingLabel: 'Creating your account',
          loading: _loading,
          onPressed: _loading ? null : _next,
          error: _error,
          child: TextField(
            controller: _password,
            autofocus: true,
            obscureText: _obscure,
            style: fieldStyle,
            decoration: simpleFieldDecoration('Password', larger: larger).copyWith(
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: healynksInk,
                ),
              ),
            ),
            onSubmitted: (_) => _next(),
          ),
        );
    }
  }
}
