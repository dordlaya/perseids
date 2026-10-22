import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'dart:math';
import 'package:flame/events.dart';

// ---------------------------------------------------------------------------
// Star classification tiers
// ---------------------------------------------------------------------------

enum StarTier { protostar, mainSequence, giant, supergiant }

StarTier starTierOf(double r) {
  if (r >= 38) return StarTier.supergiant;
  if (r >= 28) return StarTier.giant;
  if (r >= 18) return StarTier.mainSequence;
  return StarTier.protostar;
}

String starTierName(double r) {
  switch (starTierOf(r)) {
    case StarTier.protostar:    return 'Protostar';
    case StarTier.mainSequence: return 'Main Sequence';
    case StarTier.giant:        return 'Giant';
    case StarTier.supergiant:   return 'Supergiant';
  }
}

class _TierStyle {
  final int spikes;
  final Color glowColor;
  final Color bodyColor;
  final Color pulseColor;
  const _TierStyle({
    required this.spikes,
    required this.glowColor,
    required this.bodyColor,
    required this.pulseColor,
  });
}

// Cool blue → warm yellow → orange → deep red/crimson as tier increases.
const _tierStyles = <StarTier, _TierStyle>{
  StarTier.protostar: _TierStyle(
    spikes:     4,
    glowColor:  Color(0xFFB0D4FF),
    bodyColor:  Color(0xFFD0E8FF),
    pulseColor: Color(0xFFB0D8FF),
  ),
  StarTier.mainSequence: _TierStyle(
    spikes:     6,
    glowColor:  Color(0xFFFFD696),
    bodyColor:  Color(0xFFFFF0D2),
    pulseColor: Color(0xFFFFD282),
  ),
  StarTier.giant: _TierStyle(
    spikes:     8,
    glowColor:  Color(0xFFFFAA50),
    bodyColor:  Color(0xFFFFCC88),
    pulseColor: Color(0xFFFFAA40),
  ),
  StarTier.supergiant: _TierStyle(
    spikes:     12,
    glowColor:  Color(0xFFFF6040),
    bodyColor:  Color(0xFFFF9868),
    pulseColor: Color(0xFFFF5020),
  ),
};

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

class StarComponent extends Component with TapCallbacks {
  UserSnap user;
  final AppState state;
  late double _x;
  late double _y;
  // Accumulated time for animation effects (e.g. jam flicker).
  double _time = 0.0;

  StarComponent(this.user, this.state)
      : _x = user.x,
        _y = user.y;

  void updateUser(UserSnap next) {
    user = next;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final amount = 1 - exp(-18 * dt.clamp(0.0, 0.1));
    _x += (user.x - _x) * amount;
    _y += (user.y - _y) * amount;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    final d = (point.x - _x) * (point.x - _x) + (point.y - _y) * (point.y - _y);
    final tapR = max(user.r + 6, 16.0);
    return d <= tapR * tapR;
  }

  @override
  void onTapDown(TapDownEvent event) {
    state.selectedUserId = user.id;
    state.notifyListeners();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final tier = starTierOf(user.r);
    final style = _tierStyles[tier]!;
    final pulse = user.pulse;
    final vis = 0.2 + 0.8 * user.pull;

    // ── Jam state ────────────────────────────────────────────────────────────
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isJammed = user.lastJamAt > 0 && (nowMs - user.lastJamAt) < 60000;

    // ── Outer halo (Supergiant only) ─────────────────────────────────────────
    if (tier == StarTier.supergiant) {
      final haloPaint = Paint()
        ..color = style.glowColor.withOpacity(vis * 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, user.r * 1.6)
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(Offset(_x, _y), user.r * 1.8, haloPaint);
    }

    // ── Jam interference glow (behind the star) ───────────────────────────────
    if (isJammed) {
      // Red energy cloud that slowly breathes
      final jamBreath = (sin(_time * 3.0) * 0.5 + 0.5); // 0..1 at ~3 rad/s
      final jamGlowPaint = Paint()
        ..color = const Color(0xFFFF2020).withOpacity(vis * (0.25 + jamBreath * 0.2))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, user.r + 18)
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(Offset(_x, _y), user.r + 10, jamGlowPaint);
    }

    // ── Glow (hue shifts red when jammed) ────────────────────────────────────
    final effectiveGlow = isJammed
        ? Color.lerp(style.glowColor, const Color(0xFFFF4040), 0.55)!
        : style.glowColor;
    final glowPaint = Paint()
      ..color = effectiveGlow.withOpacity(vis * (0.45 + pulse * 0.5))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, user.r + 12)
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(Offset(_x, _y), user.r + 12, glowPaint);

    // ── Pulse Ring ───────────────────────────────────────────────────────────
    if (pulse > 0) {
      final pulsePaint = Paint()
        ..color = style.pulseColor.withOpacity(pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(_x, _y), user.r + 6 + (1 - pulse) * 16, pulsePaint);
    }

    // ── Star Shape ───────────────────────────────────────────────────────────
    _drawStarShape(canvas, _x, _y, user.r, pulse, vis, style);

    // ── Jam interference rings (in front of star body) ────────────────────────
    if (isJammed) {
      // Two counter-rotating dashed-look rings that flicker at ~4 Hz
      final flicker = (sin(_time * 25.0) * 0.5 + 0.5); // fast oscillation
      final ringOpacity = (0.5 + flicker * 0.5) * vis;

      final ring1Paint = Paint()
        ..color = const Color(0xFFFF3030).withOpacity(ringOpacity * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(_x, _y), user.r + 5 + sin(_time * 2.1) * 2, ring1Paint);

      final ring2Paint = Paint()
        ..color = const Color(0xFFFF6060).withOpacity(ringOpacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset(_x, _y), user.r + 10 + sin(_time * 1.7 + 1.0) * 3, ring2Paint);
    }

    // ── Selection Ring ───────────────────────────────────────────────────────
    if (state.selectedUserId == user.id) {
      final selectedPaint = Paint()
        ..color = const Color(0x9FE7FF).withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(_x, _y), user.r + 12, selectedPaint);
    }
  }

  void _drawStarShape(
    Canvas canvas,
    double x,
    double y,
    double r,
    double pulse,
    double vis,
    _TierStyle style,
  ) {
    final spikes = style.spikes;
    final outer = r + pulse * 3;
    final inner = outer * 0.4;
    final path = Path();

    for (int i = 0; i < spikes * 2; i++) {
      final rad = i % 2 == 0 ? outer : inner;
      final a = (pi / spikes) * i - pi / 2;
      final px = x + cos(a) * rad;
      final py = y + sin(a) * rad;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    final shapePaint = Paint()
      ..color = style.bodyColor.withOpacity(0.9 * vis)
      ..blendMode = BlendMode.plus;
    canvas.drawPath(path, shapePaint);
  }
}
