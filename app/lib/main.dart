import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() => runApp(const PharmaTraceApp());

class PharmaTraceApp extends StatelessWidget {
  const PharmaTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmaTrace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}