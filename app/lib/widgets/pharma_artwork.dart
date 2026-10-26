import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Custom pharmaceutical capsule + digital traceability node illustration for SplashScreen.
class SplashCapsuleArtwork extends StatelessWidget {
  final double animationValue;
  final double size;

  const SplashCapsuleArtwork({
    super.key,
    this.animationValue = 0.5,
    this.size = 210,
  });

  @override
  Widget build(BuildContext context) {
    final floatOffset = math.sin(animationValue * math.pi * 2) * 5.0;
    return SizedBox(
      width: size,
      height: size,
      child: Transform.translate(
        offset: Offset(0, floatOffset),
        child: CustomPaint(
          painter: _SplashCapsulePainter(progress: animationValue),
        ),
      ),
    );
  }
}

class _SplashCapsulePainter extends CustomPainter {
  final double progress;

  _SplashCapsulePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    // 1. Soft mint & primary teal ambient glow behind the illustration
    final pulseGlow = 0.92 + 0.08 * math.sin(progress * math.pi * 2);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              AppColors.softMint,
              AppColors.primaryTeal.withValues(alpha: 0.14),
              AppColors.warmIvory.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.62, 1.0],
          ).createShader(
            Rect.fromCircle(center: center, radius: radius * 1.28 * pulseGlow),
          );
    canvas.drawCircle(center, radius * 1.28 * pulseGlow, glowPaint);

    // 2. Soft mint inner disc
    canvas.drawCircle(
      center,
      radius * 0.76,
      Paint()..color = AppColors.softMint.withValues(alpha: 0.75),
    );

    // 3. Outer & inner digital traceability rings in muted sage & primary teal
    final ringPaint = Paint()
      ..color = AppColors.mutedSage.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(center, radius * 0.96, ringPaint);

    final innerRingPaint = Paint()
      ..color = AppColors.primaryTeal.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius * 0.76, innerRingPaint);

    // 4. Connected supply-chain traceability nodes around the capsule
    final nodeAngles = <double>[-0.65, 0.35, 1.20, 2.30, 3.10];
    final nodeDistances = <double>[
      radius * 0.96,
      radius * 0.76,
      radius * 0.96,
      radius * 0.96,
      radius * 0.76,
    ];

    final nodePoints = <Offset>[];
    for (int i = 0; i < nodeAngles.length; i++) {
      final a = nodeAngles[i] + (progress * 0.40);
      final d = nodeDistances[i];
      nodePoints.add(
        Offset(center.dx + math.cos(a) * d, center.dy + math.sin(a) * d),
      );
    }

    final connectorPaint = Paint()
      ..color = AppColors.primaryTeal.withValues(alpha: 0.22)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < nodePoints.length; i++) {
      final next = nodePoints[(i + 1) % nodePoints.length];
      canvas.drawLine(nodePoints[i], next, connectorPaint);
    }

    for (int i = 0; i < nodePoints.length; i++) {
      final pt = nodePoints[i];
      final pulse = 0.55 + 0.45 * math.sin((progress * math.pi * 2) + i * 1.3);
      canvas.drawCircle(
        pt,
        7.5 * pulse,
        Paint()..color = AppColors.primaryTeal.withValues(alpha: 0.22 * pulse),
      );
      canvas.drawCircle(pt, 4.2, Paint()..color = AppColors.white);
      canvas.drawCircle(
        pt,
        3.0,
        Paint()..color = i.isEven ? AppColors.primaryTeal : AppColors.deepTeal,
      );
    }

    // 5. Tilted two-tone pharmaceutical capsule in the center
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 5.5);

    final capWidth = size.width * 0.25;
    final capHeight = size.height * 0.52;
    final capRect = Rect.fromCenter(
      center: Offset.zero,
      width: capWidth,
      height: capHeight,
    );
    final capRRect = RRect.fromRectAndRadius(
      capRect,
      Radius.circular(capWidth / 2),
    );

    // Gentle teal-tinted elevation shadow
    canvas.drawRRect(
      capRRect.shift(const Offset(0, 8)),
      Paint()
        ..color = AppColors.deepTeal.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Clip to capsule silhouette
    canvas.save();
    canvas.clipRRect(capRRect);

    // Top half: Primary Teal to Deep Teal gradient
    final topRect = Rect.fromLTRB(-capWidth, -capHeight, capWidth, 0);
    canvas.drawRect(
      topRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryTeal, AppColors.deepTeal],
        ).createShader(topRect),
    );

    // Bottom half: Warm Ivory & Soft Mint
    final bottomRect = Rect.fromLTRB(-capWidth, 0, capWidth, capHeight);
    canvas.drawRect(
      bottomRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.white, AppColors.softMint],
        ).createShader(bottomRect),
    );

    // Center band / seam in muted sage
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: capWidth, height: 3.5),
      Paint()..color = AppColors.mutedSage.withValues(alpha: 0.45),
    );

    // Glossy highlight along left edge
    final glossRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -capWidth * 0.32,
        -capHeight * 0.40,
        capWidth * 0.14,
        capHeight * 0.80,
      ),
      Radius.circular(capWidth),
    );
    canvas.drawRRect(
      glossRect,
      Paint()..color = AppColors.white.withValues(alpha: 0.38),
    );

    canvas.restore();

    // Subtle sage-teal border on capsule
    canvas.drawRRect(
      capRRect,
      Paint()
        ..color = AppColors.deepTeal.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    canvas.restore();

    // 6. Verification shield badge at bottom-right of capsule
    final badgeCenter = Offset(
      center.dx + radius * 0.38,
      center.dy + radius * 0.34,
    );
    canvas.drawCircle(badgeCenter, 17, Paint()..color = AppColors.white);
    canvas.drawCircle(
      badgeCenter,
      14.5,
      Paint()..color = AppColors.primaryTeal,
    );
    final checkPath = Path()
      ..moveTo(badgeCenter.dx - 5, badgeCenter.dy + 0.5)
      ..lineTo(badgeCenter.dx - 1.2, badgeCenter.dy + 4.2)
      ..lineTo(badgeCenter.dx + 5.5, badgeCenter.dy - 3.5);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = AppColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashCapsulePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Editorial hero illustration for WelcomeScreen (medicine pack + capsule + authenticity seal).
class WelcomeHeroArtwork extends StatelessWidget {
  final double size;

  const WelcomeHeroArtwork({super.key, this.size = 240});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.86,
      child: CustomPaint(painter: _WelcomeHeroPainter()),
    );
  }
}

class _WelcomeHeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Soft mint backdrop circle
    canvas.drawCircle(
      center,
      size.height * 0.46,
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDDF7EE), Color(0xFFEAF6F3)],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.height * 0.46),
            ),
    );

    // Concentric subtle wave rings
    final wavePaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, size.height * 0.36, wavePaint);

    // Medicine blister card silhouette (left-center)
    final blisterRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx - 18, center.dy - 4),
        width: 112,
        height: 136,
      ),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      blisterRect.shift(const Offset(0, 10)),
      Paint()
        ..color = AppColors.navy.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(blisterRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      blisterRect,
      Paint()
        ..color = AppColors.hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Top teal header bar on blister card
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx - 18, center.dy - 48),
          width: 84,
          height: 14,
        ),
        const Radius.circular(7),
      ),
      Paint()..color = AppColors.mintSoft,
    );

    // 6 capsule cavities in blister grid
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 2; col++) {
        final cx = (center.dx - 38) + col * 40.0;
        final cy = (center.dy - 14) + row * 38.0;
        final pillRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: 22, height: 12),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          pillRRect,
          Paint()
            ..color = (row + col).isEven
                ? AppColors.emerald.withValues(alpha: 0.85)
                : AppColors.navy.withValues(alpha: 0.80),
        );
      }
    }

    // Floating Midnight Navy Verification Seal Card (bottom-right)
    final sealCenter = Offset(center.dx + 44, center.dy + 22);
    final sealRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: sealCenter, width: 76, height: 76),
      const Radius.circular(22),
    );
    canvas.drawRRect(
      sealRect.shift(const Offset(0, 8)),
      Paint()
        ..color = AppColors.navy.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(sealRect, Paint()..color = AppColors.navy);

    // Glowing emerald shield/check inside the seal
    canvas.drawCircle(
      sealCenter,
      20,
      Paint()..color = AppColors.emerald.withValues(alpha: 0.20),
    );
    final check = Path()
      ..moveTo(sealCenter.dx - 8, sealCenter.dy + 0.5)
      ..lineTo(sealCenter.dx - 2, sealCenter.dy + 6.5)
      ..lineTo(sealCenter.dx + 9, sealCenter.dy - 5.5);
    canvas.drawPath(
      check,
      Paint()
        ..color = AppColors.emerald
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom vector illustration for the Consumer card on ContinueChoiceScreen.
class ConsumerShieldArtwork extends StatelessWidget {
  const ConsumerShieldArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(painter: _ConsumerShieldPainter()),
    );
  }
}

class _ConsumerShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ),
      Paint()..color = AppColors.mintSoft,
    );

    final shield = Path()
      ..moveTo(c.dx, c.dy - 20)
      ..lineTo(c.dx + 16, c.dy - 13)
      ..lineTo(c.dx + 16, c.dy + 1)
      ..quadraticBezierTo(c.dx + 16, c.dy + 15, c.dx, c.dy + 21)
      ..quadraticBezierTo(c.dx - 16, c.dy + 15, c.dx - 16, c.dy + 1)
      ..lineTo(c.dx - 16, c.dy - 13)
      ..close();

    canvas.drawPath(shield, Paint()..color = AppColors.navy);

    // Capsule inside shield
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 10, height: 20),
      const Radius.circular(5),
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(math.pi / 4);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRRect(pill, Paint()..color = AppColors.emerald);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom vector illustration for the Organization card on ContinueChoiceScreen.
class OrganizationTraceArtwork extends StatelessWidget {
  const OrganizationTraceArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(painter: _OrganizationTracePainter()),
    );
  }
}

class _OrganizationTracePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ),
      Paint()..color = AppColors.softMint,
    );

    // Package cube + connected nodes
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 28, height: 28),
      const Radius.circular(8),
    );
    canvas.drawRRect(boxRect, Paint()..color = AppColors.deepTeal);

    final linePaint = Paint()
      ..color = AppColors.softMint
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - 7, c.dy), Offset(c.dx + 7, c.dy), linePaint);
    canvas.drawLine(Offset(c.dx, c.dy - 7), Offset(c.dx, c.dy + 7), linePaint);

    for (final pt in [
      Offset(c.dx - 18, c.dy - 15),
      Offset(c.dx + 18, c.dy - 15),
      Offset(c.dx + 18, c.dy + 15),
    ]) {
      canvas.drawCircle(pt, 3.5, Paint()..color = AppColors.primaryTeal);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clean Vertical Timeline for Medicine Provenance (replaces boxy UML/flowchart cards).
class VerticalJourneyTimeline extends StatelessWidget {
  final List<JourneyStage> stages;
  final bool stage4CompletedOverride;

  const VerticalJourneyTimeline({
    super.key,
    required this.stages,
    this.stage4CompletedOverride = false,
  });

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.warmIvory,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: const Text(
          'Your medicine journey will appear here after the first transaction.',
          style: TextStyle(
            fontSize: 13.5,
            color: AppColors.secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < stages.length; i++)
          _TimelineNodeRow(
            stage: stages[i],
            isLast: i == stages.length - 1,
            completedOverride: stages[i].stage == 4 && stage4CompletedOverride,
          ),
      ],
    );
  }
}

class _TimelineNodeRow extends StatelessWidget {
  final JourneyStage stage;
  final bool isLast;
  final bool completedOverride;

  const _TimelineNodeRow({
    required this.stage,
    required this.isLast,
    required this.completedOverride,
  });

  @override
  Widget build(BuildContext context) {
    final completed = stage.completed;
    final dotColor = completed
        ? (stage.isOnChain ? AppColors.tealDark : AppColors.navy)
        : const Color(0xFF94A3B8);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: completed ? dotColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2),
                  ),
                  child: Icon(
                    completed ? Icons.check : Icons.circle,
                    size: completed ? 14 : 6,
                    color: completed ? Colors.white : dotColor,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: completed
                          ? AppColors.emerald.withValues(alpha: 0.45)
                          : AppColors.hairline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 4 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        stage.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: completed
                              ? (stage.isOnChain
                                  ? AppColors.mintSoft
                                  : const Color(0xFFE8EEF2))
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: completed
                                ? Colors.transparent
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Text(
                          completed
                              ? (stage.isOnChain ? 'Confirmed on-chain' : 'Verified by Consumer')
                              : 'Pending',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: completed
                                ? (stage.isOnChain
                                    ? AppColors.tealDark
                                    : AppColors.navy)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stage.organization,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (stage.details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      stage.details,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (stage.timestamp.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      stage.blockNumber != null
                          ? '${stage.timestamp} • Block #${stage.blockNumber}'
                          : stage.timestamp,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
