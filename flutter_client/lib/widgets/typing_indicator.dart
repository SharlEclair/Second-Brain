import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/design_tokens.dart';

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppColors.neonBlue,
      AppColors.neonPurple,
      AppColors.neonGreen,
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceSecondary.withOpacity(0.3),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
            bottomRight: Radius.circular(24),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: colors[index % colors.length],
                shape: BoxShape.circle,
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .slideY(
              begin: 0,
              end: -0.6,
              duration: 400.ms,
              curve: Curves.easeInOut,
              delay: (index * 150).ms,
            )
            .then()
            .slideY(
              begin: 0,
              end: 0.6,
              duration: 400.ms,
              curve: Curves.easeInOut,
            )
            .animate(onPlay: (controller) => controller.repeat())
            .fadeIn(
              duration: 400.ms,
              curve: Curves.easeInOut,
              delay: (index * 150).ms,
            )
            .then()
            .fadeOut(
              duration: 400.ms,
              curve: Curves.easeInOut,
            );
          }),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}
