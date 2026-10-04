import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';

const digiForest = Color(0xFF1F4A3A);
const digiGold = Color(0xFFC4A574);
const digiPaper = Color(0xFFF6F3EE);
const digiInk = Color(0xFF1A1814);
const digiSlate = Color(0xFF6B6560);
const digiLine = Color(0xFFE8E4DC);

/// Legacy aliases — same clinic palette.
const digiViolet = digiForest;
const digiMint = digiGold;
const digiCanvas = digiPaper;

class DigiBrandMark extends StatelessWidget {
  const DigiBrandMark({super.key, this.size = 22, this.light = false});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.28),
          child: Image.asset(
            AppBrand.logoAsset,
            width: size * 1.35,
            height: size * 1.35,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: size * 0.35),
        Text(
          AppBrand.name,
          style: GoogleFonts.sourceSerif4(
            fontSize: size,
            fontWeight: FontWeight.w600,
            color: light ? Colors.white : digiForest,
          ),
        ),
      ],
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
                color: digiForest.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: digiForest, size: 32),
            ),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w600, color: digiInk)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: digiForest, foregroundColor: Colors.white),
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
  const StatTile({super.key, required this.label, required this.value, this.accent = digiForest});

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
        border: Border.all(color: digiLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w600, color: accent)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate, fontWeight: FontWeight.w600)),
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
      backgroundColor: digiPaper,
      foregroundColor: digiInk,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600, fontSize: 18, color: digiInk)),
          Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
        ],
      ),
      actions: [
        if (onRefresh != null) IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh, color: digiForest)),
        if (onLogout != null) IconButton(onPressed: onLogout, icon: const Icon(Icons.logout, color: digiSlate)),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: digiLine),
      ),
    );
  }
}

class DigiCard extends StatelessWidget {
  const DigiCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: digiLine),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: body),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.sourceSerif4(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: digiInk,
        height: 1.2,
      ),
    );
  }
}

class QuietChip extends StatelessWidget {
  const QuietChip({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: digiInk),
      label: Text(label, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: digiInk)),
      backgroundColor: Colors.white,
      side: const BorderSide(color: digiLine),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
