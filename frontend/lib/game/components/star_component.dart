import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flame/events.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';

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

class _AppearanceStyle {
  final Color glowColor;
  final Color bodyColor;
  final Color pulseColor;
  const _AppearanceStyle({
    required this.glowColor,
    required this.bodyColor,
    required this.pulseColor,
  });
}

const _appearanceStyles = <StarAppearance, _AppearanceStyle>{
  StarAppearance.haloRing: _AppearanceStyle(
    glowColor: Color(0xFF74FFD0),
    bodyColor: Color(0xFFC8FFE9),
    pulseColor: Color(0xFF9BFFE2),
  ),
  StarAppearance.particles: _AppearanceStyle(
    glowColor: Color(0xFF42DFFF),
    bodyColor: Color(0xFFE8FFFF),
    pulseColor: Color(0xFF56E8FF),
  ),
  StarAppearance.orb: _AppearanceStyle(
    glowColor: Color(0xFF559BFF),
    bodyColor: Color(0xFFD5ECFF),
    pulseColor: Color(0xFF79B8FF),
  ),
  StarAppearance.swirl: _AppearanceStyle(
    glowColor: Color(0xFF9F54FF),
    bodyColor: Color(0xFFE9D1FF),
    pulseColor: Color(0xFFC18AFF),
  ),
  StarAppearance.coreCircle: _AppearanceStyle(
    glowColor: Color(0xFFFFA52F),
    bodyColor: Color(0xFFFFE4A8),
    pulseColor: Color(0xFFFFC45B),
  ),
  StarAppearance.lens: _AppearanceStyle(
    glowColor: Color(0xFF14D8F4),
    bodyColor: Color(0xFFBFFAFF),
    pulseColor: Color(0xFF4BEAFF),
  ),
};

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

class StarComponent extends Component with TapCallbacks, LongPressCallbacks {
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
    state.onStarTapped(user.id);
  }

  @override
  void onLongPressStart(LongPressStartEvent event) {
    super.onLongPressStart(event);
    if (state.sessionUserId == user.id) return;
    unawaited(state.jam(user.id));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final appearance = starAppearanceFromId(user.appearanceId);
    final style = _appearanceStyles[appearance]!;
    final pulse = user.pulse;
    final vis = 0.2 + 0.8 * user.pull;

    // ── Jam state ────────────────────────────────────────────────────────────
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isJammed = user.lastJamAt > 0 && (nowMs - user.lastJamAt) < 60000;

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
    _drawAppearance(canvas, _x, _y, user.r, pulse, vis, appearance, style);

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
    if (state.selectedUserId == user.id || state.previewUserId == user.id) {
      final selectedPaint = Paint()
        ..color = const Color(0x9FE7FF).withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(_x, _y), user.r + 12, selectedPaint);
    }
  }

  void _drawAppearance(
    Canvas canvas,
    double x,
    double y,
    double r,
    double pulse,
    double vis,
    StarAppearance appearance,
    _AppearanceStyle style,
  ) {
    final center = Offset(x, y);
    final coreRadius = r * (1 + pulse * 0.08);
    final corePaint = Paint()
      ..color = style.bodyColor.withOpacity(0.9 * vis)
      ..shader = RadialGradient(
        colors: [Colors.white, style.bodyColor, style.glowColor.withOpacity(0.25)],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius))
      ..blendMode = BlendMode.plus;
    final ringPaint = Paint()
      ..color = style.glowColor.withOpacity(vis * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, r * 0.055);
    final fineRingPaint = Paint()
      ..color = style.pulseColor.withOpacity(vis * 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.7, r * 0.025);

    switch (appearance) {
      case StarAppearance.haloRing:
        canvas.drawCircle(center, r * 0.66, corePaint);
        canvas.drawCircle(center, r * 0.82, ringPaint);
        canvas.drawCircle(center, r * 0.98, fineRingPaint);
        canvas.drawCircle(center, r * 1.12, ringPaint..strokeWidth *= 0.55);
      case StarAppearance.particles:
        canvas.drawCircle(center, r * 0.23, corePaint);
        for (var i = 0; i < 36; i++) {
          final angle = i * 2 * pi / 36;
          final radius = r * (0.38 + (i % 3) * 0.18);
          final point = Offset(
            x + cos(angle) * radius,
            y + sin(angle) * radius,
          );
          canvas.drawCircle(
            point,
            max(0.7, r * (i % 4 == 0 ? 0.045 : 0.025)),
            Paint()..color = style.glowColor.withOpacity(vis * 0.9),
          );
        }
      case StarAppearance.orb:
        canvas.drawCircle(center, r * 0.8, corePaint);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.35);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2.4, height: r * 0.72),
          fineRingPaint,
        );
        canvas.restore();
        canvas.drawCircle(
          Offset(x + r * 0.56, y - r * 0.32),
          max(1.5, r * 0.08),
          Paint()..color = Colors.white.withOpacity(vis),
        );
      case StarAppearance.swirl:
        for (var arm = 0; arm < 3; arm++) {
          final path = Path();
          for (var i = 0; i <= 60; i++) {
            final progress = i / 60;
            final angle = progress * 2.8 * pi + arm * 2 * pi / 3;
            final radius = r * (0.08 + progress * 0.82);
            final point = Offset(
              x + cos(angle) * radius,
              y + sin(angle) * radius,
            );
            if (i == 0) {
              path.moveTo(point.dx, point.dy);
            } else {
              path.lineTo(point.dx, point.dy);
            }
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = style.glowColor.withOpacity(vis * 0.82)
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1.2, r * 0.19)
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawCircle(center, r * 0.28, corePaint);
      case StarAppearance.coreCircle:
        canvas.drawCircle(center, r * 0.52, corePaint);
        canvas.drawCircle(center, r * 0.74, ringPaint);
        canvas.drawCircle(center, r * 0.95, fineRingPaint);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r * 1.12),
          pi * 1.1,
          pi * 0.65,
          false,
          ringPaint..strokeWidth *= 0.7,
        );
      case StarAppearance.lens:
        canvas.drawCircle(center, r * 0.86, corePaint);
        canvas.drawOval(
          Rect.fromCenter(center: center, width: r * 2.1, height: r * 0.62),
          ringPaint,
        );
        canvas.drawOval(
          Rect.fromCenter(center: center, width: r * 1.82, height: r * 0.42),
          fineRingPaint,
        );
        canvas.drawCircle(
          Offset(x + r * 0.7, y + r * 0.35),
          max(1.5, r * 0.075),
          Paint()..color = Colors.white.withOpacity(vis),
        );
    }
  }
}
