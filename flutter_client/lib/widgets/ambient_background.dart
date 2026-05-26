import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import '../providers/ui_state_provider.dart';
import '../theme/design_tokens.dart';

class AmbientBackground extends ConsumerWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = ref.watch(uiStateProvider);

    List<Color> getColorsForState(UiState state) {
      switch (state) {
        case UiState.idle:
          return [
            AppColors.darkBackground,
            const Color(0xFF080808),
            const Color(0xFF0C0C0C),
            AppColors.darkBackground,
          ];
        case UiState.listening:
          // Warm glowing pulse indicating mic is hot (using electric blue, deep purple, orange/crimson)
          return [
            AppColors.neonBlue.withOpacity(0.4),
            AppColors.neonPurple.withOpacity(0.4),
            AppColors.neonOrange.withOpacity(0.3),
            AppColors.darkBackground,
          ];
        case UiState.processing:
          // Rapid aurora effect with full neon colors
          return [
            AppColors.neonGreen,
            AppColors.neonPurple,
            AppColors.neonBlue,
            AppColors.darkBackground,
          ];
        case UiState.responding:
          // Calm, steady, wide gradient
          return [
            AppColors.neonBlue.withOpacity(0.7),
            AppColors.neonPurple.withOpacity(0.5),
            AppColors.darkBackground,
            AppColors.neonBlue.withOpacity(0.3),
          ];
        case UiState.error:
          // Subtle dark crimson/orange pulse
          return [
            AppColors.darkBackground,
            const Color(0xFF4A0E0E), // Dark crimson
            AppColors.neonOrange.withOpacity(0.2),
            AppColors.darkBackground,
          ];
      }
    }

    double getSpeedForState(UiState state) {
      switch (state) {
        case UiState.idle:
          return 0.15; // Extremely slow, subtle movement
        case UiState.listening:
          return 3.0; // Moderate pulse speed
        case UiState.processing:
          return 8.0; // Rapid fluid movement
        case UiState.responding:
          return 1.5; // Calm, steady
        case UiState.error:
          return 1.0; // Slow pulse
      }
    }

    return AnimatedMeshGradient(
      colors: getColorsForState(uiState),
      options: AnimatedMeshGradientOptions(
        speed: getSpeedForState(uiState),
        frequency: 5,
        amplitude: 30,
      ),
    );
  }
}
