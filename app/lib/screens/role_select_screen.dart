import 'package:flutter/material.dart';
import 'role_login_screen.dart';

/// Legacy alias for role selection, routing to [RoleLoginScreen].
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleLoginScreen();
  }
}
