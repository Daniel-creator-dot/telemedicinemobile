import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminPalette {
  static const bg = Color(0xFF070B14);
  static const surface = Color(0xFF101826);
  static const glass = Color(0xE6121A2A);
  static const line = Color(0xFF243044);
  static const cyan = Color(0xFF2EE6D6);
  static const gold = Color(0xFFE8C27A);
  static const ink = Color(0xFFF4F1EA);
  static const mute = Color(0xFF8B95A7);
  static const violet = Color(0xFF8B7CFF);
  static const rose = Color(0xFFFF5D7A);
  static const lime = Color(0xFF3DDC97);
  static const blue = Color(0xFF4DA3FF);
}

TextStyle adminSerif({
  double size = 22,
  FontWeight weight = FontWeight.w600,
  Color color = AdminPalette.ink,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.sourceSerif4(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextStyle adminSans({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color color = AdminPalette.ink,
  double? height,
  double? letterSpacing,
}) {
  return GoogleFonts.dmSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class AdminMeshBackdrop extends StatefulWidget {
  const AdminMeshBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AdminMeshBackdrop> createState() => _AdminMeshBackdropState();
}

class _AdminMeshBackdropState extends State<AdminMeshBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return CustomPaint(
          painter: _MeshPainter(_c.value),
          child: widget.child,
        );
      },
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AdminPalette.bg);

    final orbs = [
      (Offset(size.width * (0.12 + 0.04 * math.sin(t * math.pi * 2)), size.height * 0.08), 220.0, AdminPalette.cyan),
      (Offset(size.width * 0.92, size.height * (0.18 + 0.05 * math.cos(t * math.pi * 2))), 260.0, AdminPalette.violet),
      (Offset(size.width * 0.55, size.height * 0.95), 200.0, AdminPalette.gold),
    ];
    for (final o in orbs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [o.$3.withValues(alpha: 0.18), o.$3.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: o.$1, radius: o.$2));
      canvas.drawCircle(o.$1, o.$2, paint);
    }

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => oldDelegate.t != t;
}

class AdminGlass extends StatelessWidget {
  const AdminGlass({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.glow,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? glow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: AdminPalette.glass,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              if (glow != null)
                BoxShadow(color: glow!.withValues(alpha: 0.22), blurRadius: 28, offset: const Offset(0, 10)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12)),
            ],
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: AdminPalette.cyan.withValues(alpha: 0.12),
        child: card,
      ),
    );
  }
}

class AdminLiveDot extends StatefulWidget {
  const AdminLiveDot({super.key, this.color = AdminPalette.lime});
  final Color color;

  @override
  State<AdminLiveDot> createState() => _AdminLiveDotState();
}

class _AdminLiveDotState extends State<AdminLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final p = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14 * (0.6 + p * 0.8),
                height: 14 * (0.6 + p * 0.8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - p)),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AdminKpiCard extends StatelessWidget {
  const AdminKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AdminGlass(
      glow: color,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.45)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, color: Colors.black, size: 18),
              ),
              const Spacer(),
              CustomPaint(size: const Size(46, 18), painter: _SparkPainter(color)),
            ],
          ),
          const Spacer(),
          Text(value, style: adminSerif(size: 28, weight: FontWeight.w700, letterSpacing: -0.8)),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: adminSans(size: 10, weight: FontWeight.w700, color: AdminPalette.mute, letterSpacing: 1.1),
          ),
        ],
      ),
    ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(size.width * 0.2, size.height * 0.9, size.width * 0.38, size.height * 0.45)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.05, size.width * 0.72, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.86, size.height * 0.62, size.width, size.height * 0.22);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AdminActionTile extends StatelessWidget {
  const AdminActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AdminGlass(
      onTap: onTap,
      glow: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Icon(icon, color: Colors.black, size: 20),
          ),
          const Spacer(),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: adminSans(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: adminSans(size: 11, color: AdminPalette.mute)),
        ],
      ),
    ),
    );
  }
}

class AdminGlowBar extends StatelessWidget {
  const AdminGlowBar({super.key, required this.label, required this.pct, required this.color, this.trailing});

  final String label;
  final double pct;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: adminSans(size: 12, weight: FontWeight.w600))),
            Text(trailing ?? '${(pct * 100).round()}%', style: adminSans(size: 12, weight: FontWeight.w800, color: color)),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Stack(
            children: [
              Container(height: 8, color: Colors.white.withValues(alpha: 0.06)),
              FractionallySizedBox(
                widthFactor: pct.clamp(0.04, 1),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.55)]),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 10)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminOrbitLoader extends StatefulWidget {
  const AdminOrbitLoader({super.key, this.message = 'Syncing clinic ops…'});
  final String message;

  @override
  State<AdminOrbitLoader> createState() => _AdminOrbitLoaderState();
}

class _AdminOrbitLoaderState extends State<AdminOrbitLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                return CustomPaint(painter: _OrbitPainter(_c.value));
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.message, style: adminSans(size: 13, color: AdminPalette.mute)),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      28,
      Paint()
        ..color = AdminPalette.cyan.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 28),
      t * math.pi * 2,
      1.8,
      false,
      Paint()
        ..color = AdminPalette.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 18),
      -t * math.pi * 2.4,
      2.1,
      false,
      Paint()
        ..color = AdminPalette.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c, 5, Paint()..color = AdminPalette.ink);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => oldDelegate.t != t;
}

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.toUpperCase(),
        style: adminSans(size: 9, weight: FontWeight.w800, color: color, letterSpacing: 0.8),
      ),
    );
  }
}

class AdminRingMetric extends StatelessWidget {
  const AdminRingMetric({super.key, required this.label, required this.pct, required this.color});
  final String label;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct.clamp(0, 1)),
            duration: 900.ms,
            curve: Curves.easeOutCubic,
            builder: (context, v, _) {
              return CustomPaint(
                painter: _RingPainter(v, color),
                child: Center(
                  child: Text('${(v * 100).round()}%', style: adminSerif(size: 20, weight: FontWeight.w700)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(label, textAlign: TextAlign.center, style: adminSans(size: 11, weight: FontWeight.w700, color: AdminPalette.mute)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const stroke = 8.0;
    canvas.drawCircle(
      c,
      size.width / 2 - stroke,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: size.width / 2 - stroke),
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          colors: [color, color.withValues(alpha: 0.3)],
        ).createShader(Rect.fromCircle(center: c, radius: size.width / 2))
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.v != v;
}

class AdminTrendChart extends StatelessWidget {
  const AdminTrendChart({super.key, required this.trends});
  final List<dynamic> trends;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(child: Text('No analytics yet', style: adminSans(color: AdminPalette.mute))),
      );
    }
    final maxCount = trends
        .map((item) => double.tryParse(item['count']?.toString() ?? '0') ?? 1.0)
        .fold<double>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 148,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < trends.length; i++)
            Expanded(
              child: _Bar(
                delay: i * 60,
                count: double.tryParse(trends[i]['count']?.toString() ?? '0') ?? 0,
                maxCount: maxCount,
                day: trends[i]['day']?.toString() ?? '',
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.delay, required this.count, required this.maxCount, required this.day});
  final int delay;
  final double count;
  final double maxCount;
  final String day;

  @override
  Widget build(BuildContext context) {
    final h = maxCount > 0 ? (count / maxCount) * 96 : 8.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('${count.toInt()}', style: adminSans(size: 10, color: AdminPalette.mute, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          height: h.clamp(8, 96),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            gradient: const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [AdminPalette.cyan, AdminPalette.gold],
            ),
            boxShadow: [BoxShadow(color: AdminPalette.cyan.withValues(alpha: 0.35), blurRadius: 10)],
          ),
        ).animate().scaleY(begin: 0.1, duration: 650.ms, delay: delay.ms, curve: Curves.easeOutCubic, alignment: Alignment.bottomCenter),
        const SizedBox(height: 8),
        Text(day.toUpperCase(), style: adminSans(size: 9, weight: FontWeight.w800, color: AdminPalette.mute, letterSpacing: 0.6)),
      ],
    );
  }
}

InputDecoration adminFieldDeco(String hint, IconData icon) {
  return InputDecoration(
    hintText: hint,
    hintStyle: adminSans(size: 13, color: AdminPalette.mute),
    prefixIcon: Icon(icon, color: AdminPalette.cyan, size: 18),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.04),
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AdminPalette.cyan, width: 1.4),
    ),
  );
}
