import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';

/// Logo blue and teal. Gradient is for the primary button and the active tab.
const healynksBlue = Color(0xFF1D6BFF);
const healynksTeal = Color(0xFF12C4A0);
const healynksCanvas = Color(0xFFF4F7FB);
const healynksInk = Color(0xFF0E1525);
const healynksMuted = Color(0xFF5C6B7A);
const healynksLine = Color(0xFFE6ECF2);

const clinicalActionGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [healynksBlue, healynksTeal],
);

/// Legacy names kept so existing screens compile against the new palette.
const digiForest = healynksBlue;
const digiGold = healynksTeal;
const digiPaper = healynksCanvas;
const digiInk = healynksInk;
const digiSlate = healynksMuted;
const digiLine = healynksLine;

const clinicalRadius = 18.0;
const clinicalButtonRadius = 14.0;
const clinicalMaxWidth = 1120.0;

const clinicalShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0F0E1525),
    blurRadius: 24,
    offset: Offset(0, 8),
  ),
];

const digiViolet = digiForest;
const digiMint = digiGold;
const digiCanvas = digiPaper;

enum ClinicalTone { forest, gold, slate, clay }

TextStyle clinicalDisplay(
  double size, {
  FontWeight weight = FontWeight.w700,
  Color color = digiInk,
  double height = 1.12,
  double letterSpacing = -0.45,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

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
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            AppBrand.logoAsset,
            width: size * 1.45,
            height: size * 1.45,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: size * 0.4),
        Text(
          AppBrand.name,
          style: clinicalDisplay(size, weight: FontWeight.w700, color: light ? Colors.white : digiInk),
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
        Text(title, style: clinicalDisplay(28)),
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
      ClinicalTone.forest => (const Color(0xFFE5F8F3), const Color(0xFF0C7A62)),
      ClinicalTone.gold => (const Color(0xFFEAF1FF), const Color(0xFF1D4ED8)),
      ClinicalTone.slate => (const Color(0xFFEEF2F6), digiSlate),
      ClinicalTone.clay => (const Color(0xFFFDECEC), const Color(0xFFB42318)),
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
    this.expand = true,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(clinicalButtonRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: enabled ? clinicalActionGradient : null,
        color: enabled ? null : healynksBlue.withValues(alpha: 0.28),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 18),
            child: SizedBox(
              width: expand ? double.infinity : null,
              height: 48,
              child: loading
                  ? _loadingRow()
                  : expand
                      ? Center(
                          child: Text(
                            label,
                            style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingRow() {
    final caption = (loadingLabel == null || loadingLabel!.trim().isEmpty) ? null : loadingLabel!.trim();
    final style = GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        if (caption != null) ...[
          const SizedBox(width: 10),
          if (expand)
            Flexible(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: style))
          else
            Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ],
      ],
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
          foregroundColor: digiInk,
          side: const BorderSide(color: digiLine),
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalButtonRadius)),
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
              color: const Color(0xFFE6ECF2),
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

InputDecoration clinicalFieldDecoration(
  String label, {
  Widget? suffixIcon,
  Widget? prefixIcon,
  String? helper,
  bool hideLabel = false,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(clinicalButtonRadius),
    borderSide: const BorderSide(color: digiLine),
  );
  return InputDecoration(
    labelText: hideLabel ? null : label,
    helperText: helper,
    helperMaxLines: 3,
    helperStyle: GoogleFonts.dmSans(color: digiSlate, fontSize: 12, height: 1.35),
    labelStyle: GoogleFonts.dmSans(color: digiSlate, fontSize: 14),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(clinicalButtonRadius),
      borderSide: const BorderSide(color: healynksBlue, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(clinicalButtonRadius),
      borderSide: const BorderSide(color: Color(0xFFB42318)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(clinicalButtonRadius),
      borderSide: const BorderSide(color: Color(0xFFB42318), width: 1.4),
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
              decoration: const BoxDecoration(
                color: Color(0xFFEAF1FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: healynksBlue, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: clinicalDisplay(22)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ClinicalPrimaryButton(label: actionLabel!, onPressed: onAction, expand: false),
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
  const StatTile({super.key, required this.label, required this.value, this.accent = healynksBlue});

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
          Text('$value', style: clinicalDisplay(22, color: accent)),
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
    this.trailing = const [],
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRefresh;
  final VoidCallback? onLogout;
  final List<Widget> trailing;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: digiInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: clinicalDisplay(18, weight: FontWeight.w700)),
          Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
        ],
      ),
      actions: [
        ...trailing,
        if (onRefresh != null)
          IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh, color: healynksBlue)),
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
    return Text(text, style: clinicalDisplay(22));
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalButtonRadius)),
    );
  }
}
