import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
//  RippleTap — particle burst on tap (use instead of GestureDetector)
// ═══════════════════════════════════════════════════════════════
class RippleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const RippleTap({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  State<RippleTap> createState() => _RippleTapState();
}

class _RippleTapState extends State<RippleTap>
    with TickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scale;
  final List<_Particle> _particles = [];

  static const _colors = [
    Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFA855F7),
    Color(0xFFC084FC), Color(0xFF7C3AED), Color(0xFFE879F9),
  ];

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    for (final p in _particles) {
      p.ctrl.dispose();
    }
    super.dispose();
  }

  void _spawnParticles(Offset local) {
    final rng = Random();
    for (int i = 0; i < 10; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 500 + rng.nextInt(300)),
      );
      final angle = rng.nextDouble() * 2 * pi;
      final dist = rng.nextDouble() * 70 + 30;
      final size = rng.nextDouble() * 10 + 5;
      final p = _Particle(
        x: local.dx, y: local.dy,
        dx: cos(angle) * dist, dy: sin(angle) * dist,
        size: size,
        color: _colors[rng.nextInt(_colors.length)],
        ctrl: ctrl,
      );
      ctrl.addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (mounted) setState(() => _particles.remove(p));
          ctrl.dispose();
        }
      });
      _particles.add(p);
      ctrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          setState(() => _spawnParticles(box.globalToLocal(d.globalPosition)));
        }
        _scaleCtrl.forward();
      },
      onTapUp: (_) {
        _scaleCtrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _scaleCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (_particles.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge(
                        _particles.map((p) => p.ctrl).toList()),
                    builder: (_, __) =>
                        CustomPaint(painter: _ParticlePainter(_particles)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SparkleButton — same as RippleTap (alias for backwards compat)
// ═══════════════════════════════════════════════════════════════
class SparkleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const SparkleButton({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return RippleTap(
      onTap: onTap,
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(16)),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  FloatingBubblesBackground — decorative floating bubbles bg
// ═══════════════════════════════════════════════════════════════
class FloatingBubblesBackground extends StatefulWidget {
  final Widget child;
  const FloatingBubblesBackground({super.key, required this.child});

  @override
  State<FloatingBubblesBackground> createState() =>
      _FloatingBubblesBackgroundState();
}

class _FloatingBubblesBackgroundState extends State<FloatingBubblesBackground>
    with TickerProviderStateMixin {
  final List<_FloatBubble> _items = [];

  static const _colors = [
    Color(0x226366F1), Color(0x18A855F7),
    Color(0x2A7C3AED), Color(0x20818CF8),
  ];

  @override
  void initState() {
    super.initState();
    final rng = Random();
    for (int i = 0; i < 8; i++) {
      final b = _FloatBubble(
        x: rng.nextDouble(),
        size: rng.nextDouble() * 35 + 10,
        color: _colors[rng.nextInt(_colors.length)],
        duration: Duration(seconds: 5 + rng.nextInt(5)),
        delay: Duration(milliseconds: rng.nextInt(3000)),
        vsync: this,
      );
      _items.add(b);
      b.start();
    }
  }

  @override
  void dispose() {
    for (final b in _items) b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // أول عنصر يحدد حجم الـ Stack = كل المساحة المتاحة
      SizedBox.expand(),
      // الفقاعات (خلفية)
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: Listenable.merge(_items.map((b) => b.ctrl).toList()),
            builder: (_, __) =>
                CustomPaint(painter: _FloatPainter(_items)),
          ),
        ),
      ),
      // المحتوى فوق الفقاعات
      Positioned.fill(child: widget.child),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════
//  Internal helpers
// ═══════════════════════════════════════════════════════════════
class _Particle {
  final double x, y, dx, dy, size;
  final Color color;
  final AnimationController ctrl;
  _Particle({
    required this.x, required this.y,
    required this.dx, required this.dy,
    required this.size, required this.color,
    required this.ctrl,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = p.ctrl.value;
      final opacity = (1 - t).clamp(0.0, 1.0);
      final x = p.x + p.dx * t;
      final y = p.y + p.dy * t;
      final r = p.size * (0.5 + t * 0.6);
      canvas.drawCircle(Offset(x, y), r,
          Paint()..color = p.color.withOpacity(opacity * 0.9));
      canvas.drawCircle(
          Offset(x, y), r,
          Paint()
            ..color = Colors.white.withOpacity(opacity * 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

class _FloatBubble {
  final double x, size;
  final Color color;
  final Duration duration, delay;
  late AnimationController ctrl;
  late Animation<double> anim;

  _FloatBubble({
    required this.x, required this.size, required this.color,
    required this.duration, required this.delay,
    required TickerProvider vsync,
  }) {
    ctrl = AnimationController(vsync: vsync, duration: duration);
    anim = CurvedAnimation(parent: ctrl, curve: Curves.easeInOut);
  }

  void start() async {
    await Future.delayed(delay);
    ctrl.repeat();
  }

  void dispose() => ctrl.dispose();
}

class _FloatPainter extends CustomPainter {
  final List<_FloatBubble> bubbles;
  _FloatPainter(this.bubbles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bubbles) {
      final t = b.anim.value;
      final y = size.height * (1 - t) - b.size;
      final x = b.x * size.width;
      final opacity = t < 0.1
          ? t / 0.1
          : t > 0.85
              ? (1 - t) / 0.15
              : 1.0;
      canvas.drawCircle(
          Offset(x, y),
          b.size / 2,
          Paint()..color = b.color.withOpacity(opacity.clamp(0, 1)));
    }
  }

  @override
  bool shouldRepaint(_FloatPainter old) => true;
}