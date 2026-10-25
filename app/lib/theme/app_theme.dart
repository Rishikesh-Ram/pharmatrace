import 'package:flutter/material.dart';

/// Peaceful, Light, Soothing Teal Design System for PharmaTrace.
class AppColors {
  // Core Peaceful Teal Palette
  static const Color primaryTeal = Color(0xFF238F88);
  static const Color deepTeal = Color(0xFF205B58);
  static const Color softMint = Color(0xFFE3F3ED);
  static const Color warmIvory = Color(0xFFFAFBF8);
  static const Color white = Color(0xFFFFFFFF);
  static const Color mutedSage = Color(0xFF829B91);
  static const Color secondaryText = Color(0xFF65766F);

  // Semantic & Legacy Aliases mapped to the Peaceful Teal Palette
  static const Color deepNavy = deepTeal;
  static const Color navy = deepTeal;
  static const Color navySurface = Color(0xFF266D69);
  static const Color emerald = primaryTeal;
  static const Color tealDark = deepTeal;
  static const Color mintSoft = softMint;
  static const Color mintTint = Color(0xFFF2F9F6);
  static const Color surface = warmIvory;
  static const Color card = white;
  static const Color ink = deepTeal;
  static const Color muted = secondaryText;
  static const Color hairline = Color(0xFFDCEBE5);

  static const Color success = Color(0xFF1F8A70);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
}

class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryTeal,
      primary: AppColors.primaryTeal,
      secondary: AppColors.deepTeal,
      surface: AppColors.card,
      onSurface: AppColors.deepTeal,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.warmIvory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.warmIvory,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.deepTeal,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.deepTeal,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        labelStyle: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.mutedSage, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.primaryTeal,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryTeal,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.deepTeal,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppColors.hairline, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
      ),
    );
  }
}
