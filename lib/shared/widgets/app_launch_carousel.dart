import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class _LaunchSlide {
  const _LaunchSlide({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final String asset;
  final String title;
  final String subtitle;
  final Color accent;
}

class AppLaunchCarousel extends StatefulWidget {
  const AppLaunchCarousel({
    super.key,
    this.message = 'Initializing medical tunnels…',
  });

  final String message;

  static const _slides = [
    _LaunchSlide(
      asset: 'assets/branding/onboarding_1.png',
      title: 'Seamless Telehealth',
      subtitle: 'Consult with certified doctors from the comfort of your home',
      accent: Color(0xFF00D2C4),
    ),
    _LaunchSlide(
      asset: 'assets/branding/onboarding_2.png',
      title: 'Real-time Diagnostics',
      subtitle: 'Monitor your health stats and sync with your clinical portal',
      accent: Color(0xFF8B5CF6),
    ),
    _LaunchSlide(
      asset: 'assets/branding/onboarding_3.png',
      title: 'HIPAA Secure',
      subtitle: 'Your consultations are protected with military-grade encryption',
      accent: Color(0xFF00D2C4),
    ),
    _LaunchSlide(
      asset: 'assets/branding/onboarding_4.png',
      title: '24/7 Medical Care',
      subtitle: 'Access general physicians and specialists anytime, anywhere',
      accent: Color(0xFF8B5CF6),
    ),
  ];

  @override
  State<AppLaunchCarousel> createState() => _AppLaunchCarouselState();
}

class _AppLaunchCarouselState extends State<AppLaunchCarousel>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _page = 0;
  Timer? _autoTimer;
  late final AnimationController _loaderSpin;
  late final AnimationController _loaderPulse;

  @override
  void initState() {
    super.initState();
    _loaderSpin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loaderPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _autoTimer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!_pageController.hasClients) return;
      final next = (_page + 1) % AppLaunchCarousel._slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    _loaderSpin.dispose();
    _loaderPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: const Color(0xFFFFFFFF), // White background
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _AmbientGlow(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Gra',
                            style: TextStyle(color: Color(0xFF8B5CF6)), // Violet
                          ),
                          TextSpan(
                            text: 'prime',
                            style: TextStyle(color: Color(0xFF00D2C4)), // Mint
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemCount: AppLaunchCarousel._slides.length,
                    itemBuilder: (context, index) {
                      return _SlideCard(
                        slide: AppLaunchCarousel._slides[index],
                        active: index == _page,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                _PageDots(count: AppLaunchCarousel._slides.length, index: _page),
                const SizedBox(height: 25),
                _RingLaunchLoader(
                  spin: _loaderSpin,
                  pulse: _loaderPulse,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  style: const TextStyle(
                    color: Color(0xFF64748B), // Dark slate — readable on white
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 16 + bottomPad),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x2500D2C4), // primary teal
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x208B5CF6), // electric violet
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide, required this.active});

  final _LaunchSlide slide;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.0 : 0.94,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: slide.accent.withValues(alpha: active ? 0.35 : 0.1),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: slide.accent.withValues(alpha: 0.15),
                      blurRadius: active ? 28 : 12,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      slide.asset,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.75),
                          ],
                          stops: const [0.35, 0.65, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _CaptionPanel(slide: slide),
          ],
        ),
      ),
    );
  }
}

class _CaptionPanel extends StatelessWidget {
  const _CaptionPanel({required this.slide});

  final _LaunchSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92), // Slate container
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: slide.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'DIGI HEALTH',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: slide.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: const Color(0xFFF8FAFC),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            slide.subtitle,
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? const Color(0xFF00D2C4)
                : const Color(0xFFCBD5E1), // Light grey — visible on white
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF00D2C4).withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _RingLaunchLoader extends StatelessWidget {
  const _RingLaunchLoader({
    required this.spin,
    required this.pulse,
  });

  final AnimationController spin;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([spin, pulse]),
      builder: (context, child) {
        final scale = 0.92 + pulse.value * 0.08;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 52,
            height: 52,
            child: CustomPaint(
              painter: _RingLoaderPainter(rotation: spin.value),
            ),
          ),
        );
      },
    );
  }
}

class _RingLoaderPainter extends CustomPainter {
  _RingLoaderPainter({required this.rotation});

  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final track = Paint()
      ..color = const Color(0xFFE2E8F0) // Light grey track — visible on white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 6.28318);

    final mintArc = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0x0800D2C4),
          Color(0xFF00D2C4),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final violetArc = Paint()
      ..color = const Color(0xFF8B5CF6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      0,
      2.1,
      false,
      mintArc,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      2.4,
      1.2,
      false,
      violetArc,
    );
    canvas.restore();

    final dot = Paint()..color = const Color(0xFF00D2C4);
    canvas.drawCircle(center, 3.5, dot);
  }

  @override
  bool shouldRepaint(covariant _RingLoaderPainter old) =>
      old.rotation != rotation;
}
