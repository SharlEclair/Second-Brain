import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';

class ScratchpadScreen extends StatefulWidget {
  const ScratchpadScreen({super.key});

  @override
  State<ScratchpadScreen> createState() => _ScratchpadScreenState();
}

class _ScratchpadScreenState extends State<ScratchpadScreen> {
  final TextEditingController _textController = TextEditingController();
  final ApiService _apiService = ApiService();
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
    HapticFeedback.mediumImpact();

    try {
      // Pop the screen immediately for responsive interaction
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Append content to Daily Journal
      await _apiService.appendToJournal(content);
      
      // Heavy tactile confirmation on save completion
      await HapticFeedback.heavyImpact();
      
      Fluttertoast.showToast(
        msg: "Saved to Daily Journal 📓",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFFF97316),
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
    final bgColor1 = isDark ? const Color(0xFF0E0E12) : const Color(0xFFF8FAFC);
    final bgColor2 = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
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
                            const Text(
                              "DAILY JOURNAL PIPELINE",
                              style: TextStyle(
                                color: Color(0xFFF97316),
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
                ),
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
                      cursorColor: const Color(0xFFF97316),
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
                    ),
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
