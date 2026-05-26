import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/design_tokens.dart';
import '../providers/ui_state_provider.dart';

class MultimodalToggles extends ConsumerWidget {
  final VoidCallback onCameraPressed;

  const MultimodalToggles({
    super.key,
    required this.onCameraPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMicButton(ref),
        const SizedBox(width: AppSpacing.sm),
        _buildGlassButton(
          icon: Icons.camera_alt_rounded,
          onPressed: onCameraPressed,
        ),
      ],
    );
  }

  Widget _buildMicButton(WidgetRef ref) {
    return GestureDetector(
      onTapDown: (_) {
        ref.read(uiStateProvider.notifier).setListening();
      },
      onTapUp: (_) {
        ref.read(uiStateProvider.notifier).setIdle();
      },
      onTapCancel: () {
        ref.read(uiStateProvider.notifier).setIdle();
      },
      child: _buildGlassButtonContainer(
        icon: Icons.mic_rounded,
      ),
    );
  }

  Widget _buildGlassButton({required IconData icon, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: _buildGlassButtonContainer(icon: icon),
    );
  }

  Widget _buildGlassButtonContainer({required IconData icon}) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.0,
            ),
          ),
          child: Icon(
            icon,
            color: AppColors.darkTextPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
