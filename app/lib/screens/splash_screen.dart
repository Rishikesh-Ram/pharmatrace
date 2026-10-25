import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/pharma_artwork.dart';
import 'continue_choice_screen.dart';

class SplashScreen extends StatefulWidget {
  final Duration duration;

  const SplashScreen({super.key, this.duration = const Duration(seconds: 3)});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _brandFade;
  late final Animation<double> _brandScale;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;

  Timer? _navigationTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: widget.duration);

    _brandFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.32, curve: Curves.easeOutCubic),
    );
    _brandScale = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.36, curve: Curves.easeOutBack),
      ),
    );
    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.48, curve: Curves.easeOut),
    );
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.18, 0.48, curve: Curves.easeOutCubic),
          ),
        );

    _controller.forward();
    _navigationTimer = Timer(widget.duration, _transitionToChoiceScreen);
  }

  void _transitionToChoiceScreen() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const ContinueChoiceScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.warmIvory,
              Color(0xFFF1F9F5),
              AppColors.softMint,
            ],
            stops: [0.0, 0.62, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = reduceMotion ? 1.0 : _controller.value;
              final brandOpacity = reduceMotion ? 1.0 : _brandFade.value;
              final brandScale = reduceMotion ? 1.0 : _brandScale.value;
              final taglineOpacity = reduceMotion ? 1.0 : _taglineFade.value;
              final taglineOffset = reduceMotion
                  ? Offset.zero
                  : _taglineSlide.value;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 36,
                ),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    Opacity(
                      opacity: brandOpacity,
                      child: Transform.scale(
                        scale: brandScale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SplashCapsuleArtwork(
                              animationValue: progress,
                              size: 215,
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'PharmaTrace',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.deepTeal,
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: taglineOpacity,
                      child: FractionalTranslation(
                        translation: taglineOffset,
                        child: const Text(
                          'Trust Every Dose. Trace Every Batch.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.primaryTeal,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 4),
                    ThreeDotLoadingIndicator(
                      key: const Key('welcome_three_dots'),
                      progress: progress,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'AUTHENTICITY & SUPPLY-CHAIN VERIFICATION',
                      style: TextStyle(
                        color: AppColors.mutedSage,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Three small non-clickable dots that animate sequentially one after another
/// with a gentle scale and fade effect, looping across the 3-second welcome screen.
class ThreeDotLoadingIndicator extends StatelessWidget {
  final double progress;

  const ThreeDotLoadingIndicator({super.key, required this.progress});

  /// Compute the activation weight (0.0 to 1.0) for dot [index] (0, 1, or 2)
  /// as the sequence loops 3 times over the 3-second duration.
  static double dotActivation(double progress, int index) {
    final cyclePhase = (progress * 3.0) % 1.0;
    final targetPhase = (index + 0.5) / 3.0;
    double distance = (cyclePhase - targetPhase).abs();
    if (distance > 0.5) {
      distance = 1.0 - distance;
    }
    return math.max(0.0, 1.0 - (distance * 3.0));
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          final weight = dotActivation(progress, index);
          final scale = 1.0 + (0.38 * weight);
          final opacity = 0.35 + (0.65 * weight);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Transform.scale(
              key: Key('welcome_dot_scale_$index'),
              scale: scale,
              child: Opacity(
                key: Key('welcome_dot_opacity_$index'),
                opacity: opacity,
                child: Container(
                  key: Key('welcome_dot_$index'),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: weight > 0.35
                        ? AppColors.primaryTeal
                        : AppColors.mutedSage,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
