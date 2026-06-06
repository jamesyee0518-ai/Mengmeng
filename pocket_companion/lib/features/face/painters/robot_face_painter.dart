import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../expression_state.dart';

class FaceStyleProfile {
  const FaceStyleProfile({
    required this.id,
    required this.eyeScale,
    required this.eyeDistance,
    required this.mouthWidth,
    required this.breathingAmplitude,
    required this.baselineJitterPx,
    required this.eyebrowEnabled,
    required this.paletteShift,
  });

  final String id;
  final double eyeScale;
  final double eyeDistance;
  final double mouthWidth;
  final double breathingAmplitude;
  final double baselineJitterPx;
  final bool eyebrowEnabled;
  final Color paletteShift;
}

class RobotFacePainter extends CustomPainter {
  const RobotFacePainter({required this.state, required this.tick});

  final ExpressionState state;
  final double tick;

  @override
  void paint(Canvas canvas, Size size) {
    final profile = _profile();
    _drawBackground(canvas, size, profile);
    final facePaint = Paint()
      ..color = _accentColor()
      ..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..color = _accentColor().withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);

    final offset = _burnInOffset(profile);
    final center = Offset(size.width / 2, size.height / 2) + offset;
    final eyeY = center.dy - size.height * 0.08;
    final eyeGap = size.width * 0.19 * profile.eyeDistance;
    final eyeSize = Size(
      size.width * 0.18 * profile.eyeScale,
      size.height * 0.085 * profile.eyeScale,
    );

    _drawEye(
      canvas,
      center.translate(-eyeGap, eyeY - center.dy),
      eyeSize,
      glowPaint,
      facePaint,
      isLeft: true,
    );
    _drawEye(
      canvas,
      center.translate(eyeGap, eyeY - center.dy),
      eyeSize,
      glowPaint,
      facePaint,
      isLeft: false,
    );
    if (profile.eyebrowEnabled) {
      _drawEyebrows(canvas, center, eyeGap, eyeSize, facePaint, profile);
    }
    _drawMouth(
      canvas,
      center.translate(0, size.height * 0.16),
      size,
      facePaint,
      profile,
    );
  }

  FaceStyleProfile _profile() {
    return switch (state.role) {
      FaceRole.femaleSoft => const FaceStyleProfile(
        id: 'female_soft',
        eyeScale: 1.0,
        eyeDistance: 1.05,
        mouthWidth: 0.85,
        breathingAmplitude: 0.025,
        baselineJitterPx: 2.0,
        eyebrowEnabled: true,
        paletteShift: Color(0xFFFF9FB2),
      ),
      FaceRole.maleCalm => const FaceStyleProfile(
        id: 'male_calm',
        eyeScale: 0.95,
        eyeDistance: 1.12,
        mouthWidth: 0.95,
        breathingAmplitude: 0.018,
        baselineJitterPx: 1.6,
        eyebrowEnabled: true,
        paletteShift: Color(0xFF9DE8C9),
      ),
      FaceRole.femaleLively => const FaceStyleProfile(
        id: 'female_lively',
        eyeScale: 1.15,
        eyeDistance: 1.0,
        mouthWidth: 1.1,
        breathingAmplitude: 0.04,
        baselineJitterPx: 3.0,
        eyebrowEnabled: true,
        paletteShift: Color(0xFF74D8FF),
      ),
    };
  }

  void _drawBackground(Canvas canvas, Size size, FaceStyleProfile profile) {
    final pulse = 0.5 + 0.5 * math.sin(tick * math.pi * 2);
    final alpha = profile.breathingAmplitude * (0.45 + pulse);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          profile.paletteShift.withValues(alpha: alpha * 2.8),
          profile.paletteShift.withValues(alpha: alpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawEye(
    Canvas canvas,
    Offset center,
    Size size,
    Paint glowPaint,
    Paint facePaint, {
    required bool isLeft,
  }) {
    final openness = _eyeOpenness();
    final rect = Rect.fromCenter(
      center: center + _eyeLookOffset(isLeft),
      width: size.width,
      height: math.max(5, size.height * openness),
    );

    if (state.expression == RobotExpression.dizzy) {
      _drawDizzyEye(canvas, center, size, facePaint, isLeft);
      return;
    }

    if (state.expression == RobotExpression.sleeping) {
      final linePaint = Paint()
        ..color = facePaint.color
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        center.translate(-size.width * 0.42, 0),
        center.translate(size.width * 0.42, 0),
        linePaint,
      );
      return;
    }

    final radius = Radius.circular(rect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(7), radius),
      glowPaint,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), facePaint);
  }

  void _drawDizzyEye(
    Canvas canvas,
    Offset center,
    Size size,
    Paint paint,
    bool isLeft,
  ) {
    final path = Path();
    final turns = 2.8;
    for (var i = 0; i < 90; i++) {
      final t = i / 89;
      final angle =
          (isLeft ? 1 : -1) * turns * math.pi * 2 * t + tick * math.pi * 2;
      final radius = size.shortestSide * 0.08 + size.shortestSide * 0.38 * t;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final stroke = Paint()
      ..color = paint.color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, stroke);
  }

  void _drawMouth(
    Canvas canvas,
    Offset center,
    Size size,
    Paint paint,
    FaceStyleProfile profile,
  ) {
    final stroke = Paint()
      ..color = paint.color
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    final width = size.width * 0.2 * profile.mouthWidth;

    if (state.isSpeaking) {
      final open = 14 + 22 * (0.5 + 0.5 * math.sin(tick * math.pi * 10));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: width * 1.15, height: open),
          Radius.circular(open / 2),
        ),
        paint,
      );
      return;
    }

    if (state.expression == RobotExpression.thinking) {
      _drawThinkingMouth(canvas, center, size, paint);
      return;
    }

    switch (state.expression) {
      case RobotExpression.happy:
      case RobotExpression.charging:
      case RobotExpression.caring:
        path.moveTo(center.dx - width, center.dy);
        path.quadraticBezierTo(
          center.dx,
          center.dy + 32,
          center.dx + width,
          center.dy,
        );
      case RobotExpression.lowBattery:
      case RobotExpression.annoyed:
        path.moveTo(center.dx - width * 0.7, center.dy + 18);
        path.quadraticBezierTo(
          center.dx,
          center.dy - 12,
          center.dx + width * 0.7,
          center.dy + 18,
        );
      case RobotExpression.speaking:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: width * 1.15, height: 24),
            const Radius.circular(12),
          ),
          paint,
        );
        return;
      case RobotExpression.dizzy:
      case RobotExpression.confused:
        path.moveTo(center.dx - width, center.dy);
        for (var i = 0; i < 5; i++) {
          final x1 = center.dx - width + width * (i + 0.5) / 2.5;
          final x2 = center.dx - width + width * (i + 1) / 2.5;
          final y = center.dy + (i.isEven ? 18 : -18);
          path.quadraticBezierTo(x1, y, x2, center.dy);
        }
      case RobotExpression.sleeping:
      case RobotExpression.sleepy:
        path.moveTo(center.dx - width * 0.55, center.dy);
        path.lineTo(center.dx + width * 0.55, center.dy);
      case RobotExpression.surprised:
      case RobotExpression.listening:
        canvas.drawCircle(center, 18, paint);
        return;
      case RobotExpression.neutral:
      case RobotExpression.thinking:
      case RobotExpression.focus:
        path.moveTo(center.dx - width * 0.75, center.dy);
        path.lineTo(center.dx + width * 0.75, center.dy);
    }

    canvas.drawPath(path, stroke);
  }

  void _drawThinkingMouth(
    Canvas canvas,
    Offset center,
    Size size,
    Paint paint,
  ) {
    final dotPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    final spacing = size.width * 0.055;
    for (var i = 0; i < 3; i++) {
      final phase = (tick * 3 + i / 3) % 1;
      final lift = math.sin(phase * math.pi) * 10;
      final alpha = 0.35 + 0.65 * math.sin(phase * math.pi);
      dotPaint.color = paint.color.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(center.dx + (i - 1) * spacing, center.dy - lift),
        7,
        dotPaint,
      );
    }
  }

  void _drawEyebrows(
    Canvas canvas,
    Offset center,
    double eyeGap,
    Size eyeSize,
    Paint paint,
    FaceStyleProfile profile,
  ) {
    final stroke = Paint()
      ..color = paint.color.withValues(alpha: 0.72)
      ..strokeWidth = state.role == FaceRole.maleCalm ? 6 : 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final browY = center.dy - eyeSize.height * 1.25;
    var leftTilt = -0.08;
    var rightTilt = 0.08;
    if (state.expression == RobotExpression.confused) {
      leftTilt = -0.45;
      rightTilt = 0.35;
    } else if (state.expression == RobotExpression.annoyed ||
        state.expression == RobotExpression.focus) {
      leftTilt = 0.25;
      rightTilt = -0.25;
    } else if (state.expression == RobotExpression.caring ||
        state.expression == RobotExpression.sleepy) {
      leftTilt = 0.16;
      rightTilt = -0.16;
    }
    for (final side in [-1, 1]) {
      final browCenter = Offset(center.dx + eyeGap * side, browY);
      final tilt = side == -1 ? leftTilt : rightTilt;
      final half = eyeSize.width * 0.35;
      canvas.drawLine(
        browCenter.translate(-half, -tilt * half),
        browCenter.translate(half, tilt * half),
        stroke,
      );
    }
  }

  Offset _burnInOffset(FaceStyleProfile profile) {
    return Offset(
      math.sin(tick * math.pi * 2) * profile.baselineJitterPx,
      math.cos(tick * math.pi * 1.6) * profile.baselineJitterPx,
    );
  }

  Offset _eyeLookOffset(bool isLeft) {
    return switch (state.expression) {
      RobotExpression.thinking => Offset(
        isLeft ? -3 : 3,
        -12 - math.sin(tick * math.pi * 2) * 3,
      ),
      RobotExpression.confused => Offset(isLeft ? -8 : 8, 0),
      RobotExpression.listening => const Offset(0, 2),
      RobotExpression.sleepy ||
      RobotExpression.lowBattery => const Offset(0, 8),
      _ => Offset(math.sin(tick * math.pi * 2) * 3, 0),
    };
  }

  double _eyeOpenness() {
    final blinkWave = math.sin(tick * math.pi * 2);
    final blink = blinkWave > 0.92 ? 0.14 : 1.0;
    final base = switch (state.expression) {
      RobotExpression.sleepy => 0.45,
      RobotExpression.lowBattery => 0.38,
      RobotExpression.happy || RobotExpression.charging => 0.72,
      RobotExpression.surprised || RobotExpression.listening => 1.18,
      RobotExpression.annoyed => 0.5,
      _ => blink,
    };
    if (state.role == FaceRole.maleCalm) {
      return base * 0.82;
    }
    if (state.role == FaceRole.femaleLively &&
        state.expression == RobotExpression.happy) {
      return base * 0.62;
    }
    if (state.role == FaceRole.femaleSoft &&
        state.expression == RobotExpression.caring) {
      return base * 0.78;
    }
    return base;
  }

  Color _accentColor() {
    final expressionColor = switch (state.expression) {
      RobotExpression.happy => const Color(0xFF7CFFB2),
      RobotExpression.listening => const Color(0xFF74D8FF),
      RobotExpression.thinking => const Color(0xFFFFD166),
      RobotExpression.speaking => const Color(0xFFFFFFFF),
      RobotExpression.confused => const Color(0xFFFFB86C),
      RobotExpression.caring => const Color(0xFFFF9FB2),
      RobotExpression.sleepy ||
      RobotExpression.sleeping => const Color(0xFF8EA4FF),
      RobotExpression.dizzy ||
      RobotExpression.annoyed => const Color(0xFFFF6B6B),
      RobotExpression.charging => const Color(0xFF36D399),
      RobotExpression.lowBattery => const Color(0xFFFFC857),
      RobotExpression.surprised => const Color(0xFFB7F7FF),
      RobotExpression.focus => const Color(0xFF9DE8C9),
      RobotExpression.neutral => const Color(0xFFE7FFF4),
    };
    if (state.role == FaceRole.femaleSoft &&
        (state.expression == RobotExpression.neutral ||
            state.expression == RobotExpression.caring)) {
      return const Color(0xFFFF9FB2);
    }
    if (state.role == FaceRole.maleCalm &&
        (state.expression == RobotExpression.neutral ||
            state.expression == RobotExpression.focus ||
            state.expression == RobotExpression.thinking)) {
      return const Color(0xFF9DE8C9);
    }
    return expressionColor;
  }

  @override
  bool shouldRepaint(covariant RobotFacePainter oldDelegate) {
    return oldDelegate.state != state || oldDelegate.tick != tick;
  }
}
