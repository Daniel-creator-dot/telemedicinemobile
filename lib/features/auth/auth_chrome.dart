import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';
import '../../core/env.dart';
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
            final width = constraints.maxWidth > clinicalMaxWidth ? clinicalMaxWidth : constraints.maxWidth;
            final frame = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: _AuthAside()),
                      Container(width: 1, color: digiLine),
                      Expanded(child: child),
                    ],
                  )
                : child;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: frame,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthAside extends StatelessWidget {
  const _AuthAside();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            AppBrand.logoLockupAsset,
            width: 196,
            fit: BoxFit.contain,
          ).animate().fadeIn(duration: 240.ms),
          const SizedBox(height: 32),
          Text(
            'Care that stays with you.',
            style: GoogleFonts.sourceSerif4(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: digiInk,
              height: 1.15,
            ),
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
            body: 'Work the floor, the queue, and the chart from one desk.',
          ),
          const _AsideNote(
            title: 'Agencies',
            body: 'Register a nurse agency. Healynks reviews the profile before it goes live.',
          ),
          if (AppEnv.debugHostHint.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              AppEnv.debugHostHint,
              style: GoogleFonts.dmSans(fontSize: 11, color: digiSlate),
            ),
          ],
        ],
      ),
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
            width: 2,
            height: 36,
            margin: const EdgeInsets.only(top: 2, right: 12),
            color: digiGold,
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
          AppBrand.logoLockupAsset,
          width: compact ? 148 : 176,
          fit: BoxFit.contain,
        ).animate().fadeIn(duration: 240.ms),
        const SizedBox(height: 12),
        Text(
          AppBrand.tagline,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4),
        ),
        if (AppEnv.debugHostHint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            AppEnv.debugHostHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 11, color: digiSlate),
          ),
        ],
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
        borderRadius: BorderRadius.circular(clinicalRadius),
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
