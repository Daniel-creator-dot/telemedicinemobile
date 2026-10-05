import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';
import '../../shared/widgets/clinical_ui.dart';

void goHomeForRole(BuildContext context, String role) {
  switch (role) {
    case 'doctor':
      context.go('/doctor');
    case 'admin':
      context.go('/admin');
    case 'lab_technician':
      context.go('/lab-technician');
    case 'nurse':
      context.go('/nurse');
    case 'medical_ops':
      context.go('/ops');
    case 'pharmacy':
      context.go('/pharmacy');
    case 'imaging':
      context.go('/imaging');
    case 'corporate':
      context.go('/corporate');
    case 'insurance':
      context.go('/insurance');
    case 'finance':
      context.go('/finance');
    case 'hospital':
      context.go('/hospital');
    default:
      context.go('/patient');
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiPaper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: clinicalMaxWidth),
                child: SizedBox(
                  width: double.infinity,
                  height: constraints.maxHeight,
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Expanded(child: _AuthAside()),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 28, 36, 28),
                                child: child,
                              ),
                            ),
                          ],
                        )
                      : child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

double _asideMinHeight(double maxHeight) {
  if (!maxHeight.isFinite) return 0;
  final spare = maxHeight - 56;
  return spare < 0 ? 0 : spare;
}

class _AuthAside extends StatelessWidget {
  const _AuthAside();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 28, 20, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: _asideMinHeight(constraints.maxHeight)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  AppBrand.logoAsset,
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ).animate().fadeIn(duration: 240.ms),
                const SizedBox(height: 20),
                Text(AppBrand.name, style: clinicalDisplay(40, letterSpacing: -1.1)),
                const SizedBox(height: 10),
                Text(
                  'Care that stays with you.',
                  style: clinicalDisplay(26, weight: FontWeight.w600, letterSpacing: -0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Consult a clinician, collect a prescription, and follow the visit — from Accra to the regions.',
                  style: GoogleFonts.dmSans(fontSize: 15, color: digiSlate, height: 1.5),
                ),
                const SizedBox(height: 28),
                const _AsideNote(
                  title: 'Patients',
                  body: 'Book a visit, join a consult, and see what the pharmacy has ready.',
                ),
                const _AsideNote(
                  title: 'Clinicians',
                  body: 'Doctors and nurses join to practice. Healynks reviews the profile first.',
                ),
                const _AsideNote(
                  title: 'Agencies',
                  body: 'Register the nurse agency you run. This is not a nurse clinician account.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AsideNote extends StatelessWidget {
  const _AsideNote({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: clinicalActionGradient,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: digiInk),
                ),
                const SizedBox(height: 2),
                Text(body, style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    if (wide) return const SizedBox.shrink();
    return Column(
      children: [
        Image.asset(
          AppBrand.logoAsset,
          width: compact ? 64 : 76,
          height: compact ? 64 : 76,
          fit: BoxFit.contain,
        ).animate().fadeIn(duration: 240.ms),
        const SizedBox(height: 10),
        Text(AppBrand.name, style: clinicalDisplay(compact ? 26 : 30, letterSpacing: -0.8)),
        const SizedBox(height: 4),
        Text(
          AppBrand.tagline,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4),
        ),
      ],
    );
  }
}

class AuthGlassPanel extends StatelessWidget {
  const AuthGlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: digiLine),
        boxShadow: clinicalShadow,
      ),
      child: child,
    ).animate().fadeIn(duration: 240.ms);
  }
}

InputDecoration authFieldDeco(String hint, IconData icon) {
  return clinicalFieldDecoration(
    hint,
    prefixIcon: Icon(icon, color: digiForest, size: 20),
  );
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6E8E4),
        borderRadius: BorderRadius.circular(clinicalRadius),
        border: Border.all(color: const Color(0xFFE4C8C2)),
      ),
      child: Text(
        message,
        style: GoogleFonts.dmSans(
          color: const Color(0xFF8C3A2F),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    ).animate().fadeIn(duration: 180.ms);
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ClinicalPrimaryButton(label: label, onPressed: onPressed, loading: loading);
  }
}
