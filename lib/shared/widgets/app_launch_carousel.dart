import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/brand.dart';
import 'clinical_ui.dart';

/// Calm Healynks boot screen. Matches the public canvas, not the admin console.
class AppLaunchCarousel extends StatefulWidget {
  const AppLaunchCarousel({
    super.key,
    this.message = 'Opening Healynks…',
  });

  final String message;

  @override
  State<AppLaunchCarousel> createState() => _AppLaunchCarouselState();
}

class _AppLaunchCarouselState extends State<AppLaunchCarousel> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: healynksCanvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spare = constraints.maxHeight - 56;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: spare < 0 ? 0 : spare),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: digiLine),
                        boxShadow: clinicalShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(AppBrand.logoAsset, fit: BoxFit.cover),
                      ),
                    ).animate().fadeIn(duration: 280.ms),
                    const SizedBox(height: 22),
                    Text(AppBrand.name, style: clinicalDisplay(36, letterSpacing: -0.9), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      AppBrand.tagline,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _IntroChip(label: 'Doctors'),
                        _IntroChip(label: 'Nurses'),
                        _IntroChip(label: 'Video consults'),
                      ],
                    ),
                    const SizedBox(height: 28),
                    AnimatedBuilder(
                      animation: _sweep,
                      builder: (context, _) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: SizedBox(
                            height: 3,
                            width: 180,
                            child: Stack(
                              children: [
                                const ColoredBox(color: digiLine, child: SizedBox.expand()),
                                FractionallySizedBox(
                                  widthFactor: 0.38,
                                  alignment: Alignment(-1 + _sweep.value * 2, 0),
                                  child: const ColoredBox(color: healynksBlue),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: digiSlate, height: 1.35),
                    ),
                  ],
                ),
              ),
            );
          },
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: digiLine),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: digiInk),
      ),
    );
  }
}
