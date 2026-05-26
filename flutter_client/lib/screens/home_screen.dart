import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/ui_state_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/ambient_background.dart';
import '../widgets/fluid_input_bar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/result_card.dart';
import '../widgets/horizontal_data_scroller.dart';
import '../widgets/command_palette_overlay.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final List<Map<String, dynamic>> _messages = [];
  bool _chatStarted = false;

  void _handleSendMessage(String text) async {
    setState(() {
      _chatStarted = true;
      _messages.add({'text': text, 'isUser': true});
    });

    // Simulate AI thinking
    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() {
        _messages.add({
          'text': "Here are the top results for your query:",
          'isUser': false,
          'isCard': true,
        });
      });
      ref.read(uiStateProvider.notifier).setIdle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(uiStateProvider);
    final isProcessing = uiState == UiState.processing;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 2. Middle Layer: Content Area (Greeting or Chat Feed)
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: Stack(
                    children: [
                      _buildCenteredGreeting(),
                      if (_chatStarted)
                        _buildChatFeed(isProcessing),
                    ],
                  ),
                ),

                // 3. Top Layer: Input Bar
                FluidInputBar(
                  onSend: _handleSendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'CORTEX',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.darkTextPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.search_rounded, color: Colors.white70),
                onPressed: () {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: "CommandPalette",
                    barrierColor: Colors.black.withOpacity(0.40),
                    transitionDuration: const Duration(milliseconds: 250),
                    pageBuilder: (context, anim1, anim2) => const CommandPaletteOverlay(),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                onPressed: () => GoRouter.of(context).push('/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCenteredGreeting() {
    return IgnorePointer(
      ignoring: _chatStarted,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Sparkling 4-pointed star (Gemini Style)
            Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.neonBlue,
              size: 56,
            )
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.1, 1.1),
              duration: 1200.ms,
              curve: Curves.easeInOut,
            )
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(
              colors: [
                AppColors.neonBlue,
                AppColors.neonPurple,
                AppColors.neonGreen,
              ],
              duration: 2.5.seconds,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "What's the vibe, Ashwin?",
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: AppColors.darkTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ).animate().fadeIn(duration: 800.ms).slideY(
                  begin: 0.1,
                  end: 0,
                  curve: Curves.easeOutCubic,
                  duration: 600.ms,
                ),
          ],
        ),
      ),
    )
    .animate(target: _chatStarted ? 1.0 : 0.0)
    .fadeOut(duration: 400.ms, curve: Curves.easeOutCubic)
    .slideY(end: -0.15, duration: 400.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildChatFeed(bool isProcessing) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.lg,
      ),
      itemCount: _messages.length + (isProcessing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const TypingIndicator();
        }
        final message = _messages[index];
        if (message['isCard'] == true) {
          return ResultCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message['text'] as String,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.darkTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                HorizontalDataScroller(
                  filters: const ["Overview", "Vibe", "Details"],
                  items: List.generate(5, (idx) {
                    return Container(
                      width: 120,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurfaceSecondary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            idx == 0
                                ? Icons.auto_awesome
                                : idx == 1
                                    ? Icons.bolt
                                    : Icons.insights,
                            color: AppColors.neonBlue,
                            size: 24,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            idx == 0
                                ? "Ambient"
                                : idx == 1
                                    ? "Active"
                                    : "Insights",
                            style: const TextStyle(
                              color: AppColors.darkTextPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        }
        return ChatBubble(
          text: message['text'] as String,
          isUser: message['isUser'] as bool,
        );
      },
    ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOutCubic);
  }
}
