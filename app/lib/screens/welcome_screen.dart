import 'package:flutter/material.dart';

import 'splash_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final Duration duration;

  const WelcomeScreen({super.key, this.duration = const Duration(seconds: 3)});

  @override
  Widget build(BuildContext context) {
    return SplashScreen(duration: duration);
  }
}
