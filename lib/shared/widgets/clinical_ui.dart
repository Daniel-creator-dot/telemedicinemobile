import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const digiViolet = Color(0xFF8B5CF6);
const digiMint = Color(0xFF00D2C4);
const digiInk = Color(0xFF0F172A);
const digiSlate = Color(0xFF64748B);
const digiCanvas = Color(0xFFF8FAFC);

class DigiBrandMark extends StatelessWidget {
  const DigiBrandMark({super.key, this.size = 22, this.light = false});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Digi',
            style: GoogleFonts.roboto(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: light ? Colors.white : digiViolet,
            ),
          ),
          TextSpan(
            text: ' Health',
            style: GoogleFonts.roboto(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: light ? const Color(0xFF5EEAD4) : digiMint,
            ),
          ),
        ],
      ),
    );
  }
}

class ClinicalEmptyState extends StatelessWidget {
  const ClinicalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: digiMint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: digiMint, size: 32),
            ),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.w800, color: digiInk)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.roboto(color: digiSlate, height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: digiInk),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ClinicalErrorState extends StatelessWidget {
  const ClinicalErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ClinicalEmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Could not load this view',
      message: message,
      actionLabel: onRetry != null ? 'Try again' : null,
      onAction: onRetry,
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.accent = digiMint});

  final String label;
  final Object? value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w800, color: accent)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.roboto(fontSize: 12, color: digiSlate, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class RoleChrome extends StatelessWidget implements PreferredSizeWidget {
  const RoleChrome({
    super.key,
    required this.title,
    required this.subtitle,
    this.onRefresh,
    this.onLogout,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRefresh;
  final VoidCallback? onLogout;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: digiInk,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(subtitle, style: GoogleFonts.roboto(fontSize: 11, color: const Color(0xFF94A3B8))),
        ],
      ),
      actions: [
        if (onRefresh != null) IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
        if (onLogout != null) IconButton(onPressed: onLogout, icon: const Icon(Icons.logout)),
      ],
    );
  }
}
