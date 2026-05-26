import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

class AppRadii {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  
  static final BorderRadius xsBorderRadius = BorderRadius.circular(xs);
  static final BorderRadius smBorderRadius = BorderRadius.circular(sm);
  static final BorderRadius mdBorderRadius = BorderRadius.circular(md);
  static final BorderRadius lgBorderRadius = BorderRadius.circular(lg);
  static final BorderRadius xlBorderRadius = BorderRadius.circular(xl);
  static final BorderRadius xxlBorderRadius = BorderRadius.circular(xxl);
}

class AppColors {
  // Premium Accent: Electric Blue
  static const Color accent = Color(0xFF007AFF); 
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);

  // Light Theme Colors (Sleek, airy)
  static const Color lightBackground = Color(0xFFF7F7F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFF0F0F2);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF6E6E73);
  static const Color lightDivider = Color(0xFFE5E5EA);

  // Dark Theme Colors (Deep OLED Black, Premium feel)
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF151515);
  static const Color darkSurfaceSecondary = Color(0xFF1E1E1E);
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF86868B);
  static const Color darkDivider = Color(0xFF2C2C2E);
}
