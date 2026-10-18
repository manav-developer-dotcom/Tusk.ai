import 'package:flutter/material.dart';

/// Semantic monochrome design tokens for Tusk.ai.
/// Strict black, white, and neutral greys only. No colors, no gradients.
class TuskColors {
  TuskColors._();

  // Pure bounds
  static const Color pureBlack = Color(0xFF000000);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // Dark Theme Neutral Grayscale
  static const Color darkBackground = Color(0xFF090909);
  static const Color darkSurface = Color(0xFF141414);
  static const Color darkSurfaceElevated = Color(0xFF1E1E1E);
  static const Color darkBorder = Color(0xFF2A2A2A);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFFA0A0A0);
  static const Color darkTextMuted = Color(0xFF666666);
  static const Color darkDivider = Color(0xFF222222);

  // Light Theme Neutral Grayscale
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF7F7F7);
  static const Color lightSurfaceElevated = Color(0xFFEEEEEE);
  static const Color lightBorder = Color(0xFFE0E0E0);
  static const Color lightTextPrimary = Color(0xFF111111);
  static const Color lightTextSecondary = Color(0xFF666666);
  static const Color lightTextMuted = Color(0xFF9E9E9E);
  static const Color lightDivider = Color(0xFFEBEBEB);
}

class TuskTheme {
  TuskTheme._();

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TuskColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: TuskColors.pureWhite,
        onPrimary: TuskColors.pureBlack,
        surface: TuskColors.darkSurface,
        onSurface: TuskColors.darkTextPrimary,
        outline: TuskColors.darkBorder,
      ),
      dividerColor: TuskColors.darkDivider,
      dividerTheme: const DividerThemeData(
        color: TuskColors.darkDivider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TuskColors.darkBackground,
        foregroundColor: TuskColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TuskColors.darkSurface,
        hintStyle: const TextStyle(
          color: TuskColors.darkTextMuted,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TuskColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TuskColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TuskColors.pureWhite, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TuskColors.darkBackground,
        selectedItemColor: TuskColors.pureWhite,
        unselectedItemColor: TuskColors.darkTextMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: TuskColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: TuskColors.pureBlack,
        onPrimary: TuskColors.pureWhite,
        surface: TuskColors.lightSurface,
        onSurface: TuskColors.lightTextPrimary,
        outline: TuskColors.lightBorder,
      ),
      dividerColor: TuskColors.lightDivider,
      dividerTheme: const DividerThemeData(
        color: TuskColors.lightDivider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TuskColors.lightBackground,
        foregroundColor: TuskColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TuskColors.lightSurface,
        hintStyle: const TextStyle(
          color: TuskColors.lightTextMuted,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TuskColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TuskColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: TuskColors.pureBlack, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: TuskColors.lightBackground,
        selectedItemColor: TuskColors.pureBlack,
        unselectedItemColor: TuskColors.lightTextMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
