import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ui_state_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/ambient_background.dart';
import '../widgets/fluid_input_bar.dart';
import '../widgets/chat_bubble.dart';

class CortexHomeScreen extends ConsumerStatefulWidget {
  const CortexHomeScreen({super.key});

  @override
  ConsumerState<CortexHomeScreen> createState() => _CortexHomeScreenState();
}

class _CortexHomeScreenState extends ConsumerState<CortexHomeScreen> {
  bool _hasStartedChat = false;
  final List<Map<String, dynamic>> _messages = [];

  void _handleSend(String text) async {
    if (!_hasStartedChat) {
      setState(() {
        _hasStartedChat = true;
      });
    }

    setState(() {
      _messages.add({'text': text, 'isUser': true});
      _messages.add({'text': '', 'isUser': false, 'isThinking': true});
    });

    ref.read(uiStateProvider.notifier).setProcessing();

    // Simulate AI thinking and response
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      ref.read(uiStateProvider.notifier).setIdle();
      setState(() {
        _messages.removeLast(); // Remove thinking message
        _messages.add({'text': "I'm picking up good vibes. How can I help you?", 'isUser': false});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground, // Fallback
      body: Stack(
        children: [
          // 1. Ambient Reactive Background
          const Positioned.fill(
            child: AmbientBackground(),
          ),

          // 2. Main Content Area
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _hasStartedChat ? _buildChatFlow() : _buildCenteredGreeting(),
                ),
                // 3. Fluid Input Engine
                FluidInputBar(onSend: _handleSend),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenteredGreeting() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Subtle 4-pointed star animation
          const Icon(
            Icons.star_border_rounded, // Approximation of 4-pointed star
            color: AppColors.neonBlue,
            size: 48,
          )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1), duration: 2.seconds)
              .fadeOut(duration: 2.seconds),
          const SizedBox(height: AppSpacing.lg),
          Text(
            "What's the vibe?",
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                ),
          ).animate().fadeIn(duration: 1.seconds).slideY(begin: 0.2, end: 0, curve: Curves.easeOut),
        ],
      ),
    );
  }

  Widget _buildChatFlow() {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return ChatBubble(
          text: msg['text'],
          isUser: msg['isUser'],
          isThinking: msg['isThinking'] ?? false,
        );
      },
    ).animate().fadeIn(duration: 300.ms);
  }
}
