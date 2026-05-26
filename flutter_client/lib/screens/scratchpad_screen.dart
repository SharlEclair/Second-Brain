import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/providers.dart';
import '../services/haptic_feedback_manager.dart';

class ScratchpadScreen extends ConsumerStatefulWidget {
  const ScratchpadScreen({super.key});

  @override
  ConsumerState<ScratchpadScreen> createState() => _ScratchpadScreenState();
}

class _ScratchpadScreenState extends ConsumerState<ScratchpadScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isSaving = false;

  Future<void> _saveAndClose() async {
    if (_isSaving) return;
    final content = _textController.text.trim();
    
    if (content.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    // Immediate tactile feedback to confirm closure action
    HapticFeedbackManager.mediumImpact();

    try {
      // Pop the screen immediately for responsive interaction
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Append content to Daily Journal using the Riverpod-managed ApiService
      await ref.read(apiServiceProvider).appendToJournal(content);
      
      // Heavy tactile confirmation on save completion
      await HapticFeedbackManager.heavyImpact();
      
      Fluttertoast.showToast(
        msg: "Saved to Daily Journal 📓",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Theme.of(context).colorScheme.primary,
        textColor: Colors.white,
        fontSize: 13.0,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to save: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.redAccent,
        textColor: Colors.white,
        fontSize: 13.0,
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Premium gradient background for depth
    final bgColor1 = Theme.of(context).colorScheme.background;
    final bgColor2 = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onBackground;
    final hintColor = isDark ? Colors.white30 : Colors.black38;

    return WillPopScope(
      onWillPop: () async {
        await _saveAndClose();
        return false; // We pop manually in _saveAndClose
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgColor1, bgColor2],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Top drag bar handle and header
                GestureDetector(
                  onVerticalDragUpdate: (details) {
                    // Detect downward swipe gesture
                    if (details.delta.dy > 8) {
                      _saveAndClose();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    children: [
                      // Capsule drag handle
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                      ),
                      // Ambient header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "DAILY JOURNAL PIPELINE",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              "Swipe down to save",
                              style: TextStyle(
                                color: hintColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0, curve: Curves.easeOutCubic),
                // Fullscreen large input area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: TextField(
                      controller: _textController,
                      autofocus: true,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        height: 1.5,
                      ),
                      cursorColor: Theme.of(context).colorScheme.primary,
                      decoration: InputDecoration(
                        hintText: "What's on your mind?",
                        hintStyle: TextStyle(
                          color: hintColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                        ),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
