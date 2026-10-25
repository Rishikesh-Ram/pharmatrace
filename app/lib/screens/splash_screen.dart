import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/pharma_artwork.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  final Duration duration;

  const SplashScreen({super.key, this.duration = const Duration(seconds: 5)});

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
      curve: const Interval(0.0, 0.28, curve: Curves.easeOutCubic),
    );
    _brandScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.32, curve: Curves.easeOutBack),
      ),
    );
    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.44, curve: Curves.easeOut),
    );
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.18, 0.44, curve: Curves.easeOutCubic),
          ),
        );

    _controller.forward();
    _navigationTimer = Timer(widget.duration, _transitionToWelcome);
  }

  void _transitionToWelcome() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, _, _) => const WelcomeScreen(),
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
      backgroundColor: AppColors.deepNavy,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF09121B), AppColors.navy, Color(0xFF0D2D35)],
            stops: [0.0, 0.58, 1.0],
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
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: taglineOpacity,
                      child: FractionalTranslation(
                        translation: taglineOffset,
                        child: const Text(
                          'Trust Every Dose. Trace Every Batch.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.mintSoft,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(flex: 4),
                    _FiveDotLoadingIndicator(progress: progress),
                    const SizedBox(height: 14),
                    Text(
                      'AUTHENTICITY & SUPPLY-CHAIN VERIFICATION',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
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

class _FiveDotLoadingIndicator extends StatelessWidget {
  final double progress;

  const _FiveDotLoadingIndicator({required this.progress});

  @override
  Widget build(BuildContext context) {
    // 5 dots that illuminate sequentially and pulse gently across the 5-second window
    final activeIndex = (progress * 5).floor().clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isLit = index <= activeIndex;
        final isCurrent = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: isCurrent ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isLit
                ? AppColors.emerald
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: AppColors.emerald.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
