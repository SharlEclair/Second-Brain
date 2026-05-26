import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_tokens.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        background: AppColors.lightBackground,
        surface: AppColors.lightSurface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: AppColors.lightTextPrimary,
        onSurface: AppColors.lightTextPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: AppColors.lightDivider,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold, letterSpacing: -1.0)),
        displayMedium: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        displaySmall: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold)),
        headlineLarge: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600)),
        headlineMedium: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600)),
        headlineSmall: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600)),
        titleLarge: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600)),
        titleMedium: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w500)),
        titleSmall: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w500)),
        bodyLarge: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontSize: 16)),
        bodyMedium: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontSize: 14)),
        bodySmall: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
        labelLarge: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w500)),
        labelMedium: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.lightTextSecondary)),
        labelSmall: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.lightTextSecondary)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent, // Glassmorphism-ready
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.lgBorderRadius),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.lgBorderRadius),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.mdBorderRadius),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceSecondary,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: AppRadii.lgBorderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.lgBorderRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.lgBorderRadius,
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.lightTextSecondary),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: AppColors.darkTextPrimary,
        onSurface: AppColors.darkTextPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: AppColors.darkDivider,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold, letterSpacing: -1.0)),
        displayMedium: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        displaySmall: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold)),
        headlineLarge: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600)),
        headlineMedium: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600)),
        headlineSmall: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600)),
        titleLarge: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600)),
        titleMedium: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w500)),
        titleSmall: GoogleFonts.outfit(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w500)),
        bodyLarge: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontSize: 16)),
        bodyMedium: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontSize: 14)),
        bodySmall: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12)),
        labelLarge: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w500)),
        labelMedium: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.darkTextSecondary)),
        labelSmall: GoogleFonts.inter(textStyle: const TextStyle(color: AppColors.darkTextSecondary)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent, // Glassmorphism-ready
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.lgBorderRadius),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.lgBorderRadius),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.mdBorderRadius),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceSecondary,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: AppRadii.lgBorderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.lgBorderRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.lgBorderRadius,
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
      ),
    );
  }
}
