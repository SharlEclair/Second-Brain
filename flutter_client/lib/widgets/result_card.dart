import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/design_tokens.dart';

class ResultCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ResultCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.md,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.darkSurface, // Deep background
        borderRadius: BorderRadius.circular(32), // Heavy corner radius
        boxShadow: [
          // Soft, sprawling drop shadow for depth
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 30,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    ).animate().slideY(
          begin: 0.5,
          end: 0.0,
          curve: Curves.easeOutExpo,
          duration: 500.ms,
        ).fadeIn(
          duration: 500.ms,
          curve: Curves.easeOutExpo,
        );
  }
}
