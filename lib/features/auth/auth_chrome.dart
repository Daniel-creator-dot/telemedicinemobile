import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';
import '../../core/env.dart';
import '../admin/admin_chrome.dart';

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
      backgroundColor: AdminPalette.bg,
      body: AdminMeshBackdrop(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.28,
              child: Image.asset('assets/branding/hero_login.png', fit: BoxFit.cover),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AdminPalette.bg.withValues(alpha: 0.35),
                    AdminPalette.bg.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
            SafeArea(child: child),
          ],
        ),
      ),
    );
  }
}

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 64.0 : 88.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            boxShadow: [
              BoxShadow(color: AdminPalette.cyan.withValues(alpha: 0.4), blurRadius: 28),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            child: Image.asset(AppBrand.logoAsset, fit: BoxFit.cover),
          ),
        ).animate().fadeIn(duration: 420.ms).scale(begin: const Offset(0.86, 0.86), curve: Curves.easeOutBack),
        SizedBox(height: compact ? 12 : 18),
        Text(
          AppBrand.name,
          textAlign: TextAlign.center,
          style: GoogleFonts.sourceSerif4(
            fontSize: compact ? 28 : 38,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.05,
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.08),
        const SizedBox(height: 6),
        Text(
          AppBrand.tagline,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: AdminPalette.gold,
            fontWeight: FontWeight.w500,
          ),
        ).animate().fadeIn(delay: 80.ms),
        const SizedBox(height: 6),
        Text(
          AppEnv.isLocalOverride ? 'Local clinic API' : 'Live clinic · Ghana',
          style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white54),
        ),
        if (AppEnv.debugHostHint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            AppEnv.debugHostHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              color: AdminPalette.cyan.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: const Color(0xCC101826),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(color: AdminPalette.cyan.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 12)),
            ],
          ),
          child: child,
        ),
      ),
    ).animate().fadeIn(delay: 160.ms, duration: 420.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }
}

InputDecoration authFieldDeco(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.dmSans(color: Colors.white38, fontSize: 14),
    prefixIcon: Icon(icon, color: AdminPalette.cyan, size: 20),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AdminPalette.cyan, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: AdminPalette.rose.withValues(alpha: 0.5)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AdminPalette.rose, width: 1.5),
    ),
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
        color: AdminPalette.rose.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminPalette.rose.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: GoogleFonts.dmSans(color: const Color(0xFFFCA5A5), fontSize: 12, fontWeight: FontWeight.w600)),
    ).animate().shake();
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AdminPalette.cyan,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AdminPalette.cyan.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : Text(label, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
