import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/design_tokens.dart';
import '../providers/ui_state_provider.dart';
import 'multimodal_toggles.dart';

class FluidInputBar extends ConsumerStatefulWidget {
  final Function(String) onSend;

  const FluidInputBar({super.key, required this.onSend});

  @override
  ConsumerState<FluidInputBar> createState() => _FluidInputBarState();
}

class _FluidInputBarState extends ConsumerState<FluidInputBar> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();
  bool _isFocused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ref.read(uiStateProvider.notifier).setProcessing();
      widget.onSend(text);
      _controller.clear();
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            color: AppColors.darkSurface.withOpacity(0.6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    style: const TextStyle(color: AppColors.darkTextPrimary),
                    decoration: InputDecoration(
                      hintText: "What's the vibe?",
                      hintStyle: TextStyle(
                        color: AppColors.darkTextSecondary.withOpacity(0.5),
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: _hasText
                        ? _buildSendButton()
                        : MultimodalToggles(
                            onCameraPressed: () {},
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
    .animate(target: _isFocused ? 1.0 : 0.0)
    .boxShadow(
      begin: BoxShadow(
        color: Colors.black.withOpacity(0.3),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      end: BoxShadow(
        color: AppColors.neonBlue.withOpacity(0.3),
        blurRadius: 25,
        spreadRadius: 4,
        offset: const Offset(0, 0),
      ),
      duration: 350.ms,
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildSendButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleSend,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.neonBlue,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_upward_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    ).animate().scale(
          begin: const Offset(0.8, 0.8),
          duration: 200.ms,
          curve: Curves.easeOutBack,
        );
  }
}
