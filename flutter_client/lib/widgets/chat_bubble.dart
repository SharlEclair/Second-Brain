import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/design_tokens.dart';

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
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
          color: isUser ? AppColors.darkSurfaceSecondary : Colors.transparent,
          borderRadius: isUser
              ? const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(4), // Grounded bottom-right corner
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                  bottomLeft: Radius.circular(4), // Grounded bottom-left corner
                ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.darkTextPrimary,
                height: 1.4,
              ),
        ),
      ),
    ).animate().slideY(
          begin: 0.2,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        ).fadeIn(
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
