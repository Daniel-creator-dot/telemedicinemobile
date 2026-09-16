import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';
import '../../features/admin/admin_chrome.dart';

/// Cinematic Medilynks boot intro.
class AppLaunchCarousel extends StatefulWidget {
  const AppLaunchCarousel({
    super.key,
    this.message = 'Opening Medilynks…',
  });

  final String message;

  @override
  State<AppLaunchCarousel> createState() => _AppLaunchCarouselState();
}

class _AppLaunchCarouselState extends State<AppLaunchCarousel>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminPalette.bg,
      body: AdminMeshBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              SizedBox(
                width: 220,
                height: 220,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_spin, _pulse]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _IntroRingsPainter(
                        spin: _spin.value,
                        pulse: _pulse.value,
                      ),
                      child: Center(
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: AdminPalette.cyan.withValues(alpha: 0.45),
                                blurRadius: 36,
                              ),
                              BoxShadow(
                                color: AdminPalette.gold.withValues(alpha: 0.22),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(AppBrand.logoAsset, fit: BoxFit.cover),
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 600.ms)
                            .scale(begin: const Offset(0.55, 0.55), curve: Curves.easeOutBack, duration: 780.ms),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              Text(
                AppBrand.name,
                style: GoogleFonts.sourceSerif4(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: AdminPalette.ink,
                  letterSpacing: -0.8,
                  height: 1,
                ),
              )
                  .animate()
                  .fadeIn(delay: 280.ms, duration: 520.ms)
                  .slideY(begin: 0.18, curve: Curves.easeOutCubic),
              const SizedBox(height: 8),
              Text(
                AppBrand.tagline,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AdminPalette.gold,
                  letterSpacing: 0.4,
                ),
              )
                  .animate()
                  .fadeIn(delay: 520.ms, duration: 500.ms)
                  .slideY(begin: 0.2, curve: Curves.easeOutCubic),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: const [
                  _IntroChip(label: 'Live queue'),
                  _IntroChip(label: 'Records'),
                  _IntroChip(label: 'Specialists'),
                ],
              )
                  .animate()
                  .fadeIn(delay: 780.ms, duration: 480.ms)
                  .slideY(begin: 0.16, curve: Curves.easeOutCubic),
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 3,
                        child: Stack(
                          children: [
                            Container(color: Colors.white.withValues(alpha: 0.08)),
                            FractionallySizedBox(
                              widthFactor: 0.42,
                              alignment: Alignment(-1 + _sweep.value * 2, 0),
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, AdminPalette.cyan, AdminPalette.gold, Colors.transparent],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.message,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AdminPalette.mute,
                  letterSpacing: 0.6,
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.45, end: 1, duration: 900.ms),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroChip extends StatelessWidget {
  const _IntroChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AdminPalette.ink.withValues(alpha: 0.82),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _IntroRingsPainter extends CustomPainter {
  _IntroRingsPainter({required this.spin, required this.pulse});

  final double spin;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final t = ((pulse + i / 3) % 1.0);
      final r = 48 + t * 62;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AdminPalette.cyan.withValues(alpha: 0.28 * (1 - t)),
      );
    }

    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        startAngle: spin * math.pi * 2,
        colors: [
          Colors.transparent,
          AdminPalette.gold.withValues(alpha: 0.9),
          AdminPalette.cyan.withValues(alpha: 0.9),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: 86));
    canvas.drawCircle(c, 86, orbit);

    final p = Offset(
      c.dx + math.cos(spin * math.pi * 2) * 86,
      c.dy + math.sin(spin * math.pi * 2) * 86,
    );
    canvas.drawCircle(p, 4.5, Paint()..color = AdminPalette.gold);
    canvas.drawCircle(
      Offset(
        c.dx + math.cos(spin * math.pi * 2 + math.pi) * 86,
        c.dy + math.sin(spin * math.pi * 2 + math.pi) * 86,
      ),
      3.2,
      Paint()..color = AdminPalette.cyan,
    );
  }

  @override
  bool shouldRepaint(covariant _IntroRingsPainter oldDelegate) =>
      oldDelegate.spin != spin || oldDelegate.pulse != pulse;
}
