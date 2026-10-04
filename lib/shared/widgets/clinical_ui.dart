import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';

const digiForest = Color(0xFF1F4A3A);
const digiGold = Color(0xFFC4A574);
const digiPaper = Color(0xFFF6F3EE);
const digiInk = Color(0xFF1A1814);
const digiSlate = Color(0xFF6B6560);
const digiLine = Color(0xFFE8E4DC);

const clinicalRadius = 12.0;
const clinicalMaxWidth = 1120.0;

const clinicalShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0F1A1814),
    blurRadius: 16,
    offset: Offset(0, 4),
  ),
];

/// Legacy aliases — same clinic palette.
const digiViolet = digiForest;
const digiMint = digiGold;
const digiCanvas = digiPaper;

enum ClinicalTone { forest, gold, slate, clay }

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
          borderRadius: BorderRadius.circular(8),
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

class ClinicalPageHeader extends StatelessWidget {
  const ClinicalPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.sourceSerif4(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: digiInk,
            height: 1.15,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.45),
          ),
        ],
      ],
    );
    if (trailing == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        const SizedBox(width: 16),
        trailing!,
      ],
    );
  }
}

class ClinicalStatusPill extends StatelessWidget {
  const ClinicalStatusPill({
    super.key,
    required this.label,
    this.tone = ClinicalTone.slate,
  });

  final String label;
  final ClinicalTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tone) {
      ClinicalTone.forest => (const Color(0xFFE5EFEA), digiForest),
      ClinicalTone.gold => (const Color(0xFFF6EFE3), const Color(0xFF7A5B32)),
      ClinicalTone.slate => (const Color(0xFFF0EDE8), digiSlate),
      ClinicalTone.clay => (const Color(0xFFF6E8E4), const Color(0xFF8C3A2F)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
      ),
    );
  }
}

class ClinicalPrimaryButton extends StatelessWidget {
  const ClinicalPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: digiForest,
          foregroundColor: Colors.white,
          disabledBackgroundColor: digiForest.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalRadius)),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class ClinicalSecondaryButton extends StatelessWidget {
  const ClinicalSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: digiForest,
          side: const BorderSide(color: digiLine),
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalRadius)),
        ),
        child: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class ClinicalSkeleton extends StatelessWidget {
  const ClinicalSkeleton({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines; i++) ...[
          Container(
            height: i == 0 ? 22 : 12,
            width: i == 0 ? 168 : double.infinity,
            decoration: BoxDecoration(
              color: digiLine,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          if (i != lines - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class ClinicalCardSkeleton extends StatelessWidget {
  const ClinicalCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const DigiCard(child: ClinicalSkeleton(lines: 4));
  }
}

InputDecoration clinicalFieldDecoration(String label, {Widget? suffixIcon, Widget? prefixIcon}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(clinicalRadius),
    borderSide: const BorderSide(color: digiLine),
  );
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.dmSans(color: digiSlate, fontSize: 14),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(clinicalRadius),
      borderSide: const BorderSide(color: digiForest, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(clinicalRadius),
      borderSide: const BorderSide(color: Color(0xFF8C3A2F)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(clinicalRadius),
      borderSide: const BorderSide(color: Color(0xFF8C3A2F), width: 1.4),
    ),
  );
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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: digiForest.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: digiForest, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w600, color: digiInk),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: digiForest,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalRadius)),
                ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(clinicalRadius),
        border: Border.all(color: digiLine),
        boxShadow: clinicalShadow,
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
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600, fontSize: 20, color: digiInk)),
          Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
        ],
      ),
      actions: [
        if (onRefresh != null)
          IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh, color: digiForest)),
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
        borderRadius: BorderRadius.circular(clinicalRadius),
        border: Border.all(color: digiLine),
        boxShadow: clinicalShadow,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(clinicalRadius),
        child: body,
      ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalRadius)),
    );
  }
}
