import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';

import 'dart:math';

class BackgroundComponent extends Component {
  final AppState state;
  final Random _rnd = Random(42);

  /// Stars drawn on the background (fixed in world space so they scroll with the map)
  final List<_BgStar> _bgStars = [];

  BackgroundComponent(this.state) {
    _generateStars();
  }

  void _generateStars() {
    // Three layers – far (dim, tiny) → near (bright, larger)
    // (count, rMin, rMax, aMin, aMax)
    const layers = [
      [220, 0.3, 0.7,  0.08, 0.25], // distant, faint
      [110, 0.5, 1.2,  0.20, 0.55], // mid-field
      [ 55, 0.9, 2.2,  0.45, 0.90], // foreground, bright
    ];

    for (final cfg in layers) {
      final int count  = cfg[0].toInt();
      final double rMin = cfg[1].toDouble();
      final double rMax = cfg[2].toDouble();
      final double aMin = cfg[3].toDouble();
      final double aMax = cfg[4].toDouble();

      for (int s = 0; s < count; s++) {
        // slight hue variety: blue-ish, warm, or white
        final double hue = _rnd.nextDouble() < 0.3
            ? 200 + _rnd.nextDouble() * 40
            : _rnd.nextDouble() < 0.15
                ? 30 + _rnd.nextDouble() * 20
                : 0;

        _bgStars.add(_BgStar(
          x:             -200 + _rnd.nextDouble() * 2440,
          y:             -200 + _rnd.nextDouble() * 2440,
          r:             rMin + _rnd.nextDouble() * (rMax - rMin),
          a:             aMin + _rnd.nextDouble() * (aMax - aMin),
          hue:           hue,
          twinkleOffset: _rnd.nextDouble() * pi * 2,
          twinkleSpeed:  0.4 + _rnd.nextDouble() * 0.9,
        ));
      }
    }
  }

  // cached grid paint
  final Paint _gridPaint = Paint()
    ..color = const Color(0x2878b4dc)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final double t = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // ── deep-space background ────────────────────────────────────────────────
    canvas.drawRect(
      const Rect.fromLTWH(-500, -500, 3240, 3240),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [
            Color(0xFF0a0e1a), // deep navy centre
            Color(0xFF050709), // almost black edges
          ],
        ).createShader(const Rect.fromLTWH(-500, -500, 3240, 3240)),
    );

    // ── stars ────────────────────────────────────────────────────────────────
    for (final star in _bgStars) {
      // Gentle twinkle: oscillate alpha ±25 %
      final double twinkle =
          0.75 + 0.25 * sin(t * star.twinkleSpeed + star.twinkleOffset);
      final double alpha = (star.a * twinkle).clamp(0.0, 1.0);

      // Star colour (white-blue default, or tinted)
      final Color coreColor = star.hue == 0
          ? HSLColor.fromAHSL(alpha, 220, 0.25, 1.0).toColor()
          : HSLColor.fromAHSL(alpha, star.hue, 0.6, 0.92).toColor();

      // Outer glow
      canvas.drawCircle(
        Offset(star.x, star.y),
        star.r * 4.5,
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, star.r * 3.0)
          ..color = coreColor.withAlpha(
            ((alpha * 0.35) * 255).round().clamp(0, 255),
          ),
      );

      // Inner soft halo
      canvas.drawCircle(
        Offset(star.x, star.y),
        star.r * 1.8,
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, star.r * 1.1)
          ..color = coreColor.withAlpha(
            ((alpha * 0.65) * 255).round().clamp(0, 255),
          ),
      );

      // Sharp core pixel
      canvas.drawCircle(
        Offset(star.x, star.y),
        star.r,
        Paint()..color = coreColor,
      );
    }

    // ── grid sectors ─────────────────────────────────────────────────────────
    final int n = max(1, (state.users.length / 10).ceil());
    for (int i = 0; i < n; i++) {
      final int col = i % 3;
      final int row = i ~/ 3;
      canvas.drawRect(
        Rect.fromLTWH(col * 560.0, row * 560.0, 560, 560),
        _gridPaint,
      );
    }
  }
}

// ─── data class ───────────────────────────────────────────────────────────────
class _BgStar {
  final double x, y, r, a, hue, twinkleOffset, twinkleSpeed;
  const _BgStar({
    required this.x,
    required this.y,
    required this.r,
    required this.a,
    required this.hue,
    required this.twinkleOffset,
    required this.twinkleSpeed,
  });
}
