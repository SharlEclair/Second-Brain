import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/api_service.dart';
import '../services/debug_logger.dart';

class QuickAskScreen extends StatefulWidget {
  const QuickAskScreen({super.key});

  @override
  State<QuickAskScreen> createState() => _QuickAskScreenState();
}

class _QuickAskScreenState extends State<QuickAskScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ApiService _apiService = ApiService();
  String _response = "";
  bool _isLoading = false;

  Future<void> _submitQuery() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _response = "";
    });

    try {
      DebugLogger.log('Quick Ask querying: $query', type: 'SYSTEM');
      final result = await _apiService.ask(query);
      if (mounted) {
        setState(() {
          _response = result.isNotEmpty ? result : "No answer received.";
        });
      }
    } catch (e) {
      DebugLogger.log('Quick Ask failed: $e', type: 'ERROR');
      if (mounted) {
        setState(() {
          _response = "Error: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.60),
      body: Stack(
        children: [
          // Backdrop blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          
          // Outer tap area to close
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // Dialog body
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "🧠 CORTEX QUICK ASK",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          fontSize: 14,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_isLoading || _response.isNotEmpty) ...[
                    Flexible(
                      child: SingleChildScrollView(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: _isLoading
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      "Consulting Brain Vault...",
                                      style: TextStyle(color: Colors.white60, fontSize: 13),
                                    ),
                                  ],
                                )
                              : Text(
                                  _response,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: "What do you want to recall?",
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF050505),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF222222)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF222222)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1),
                            ),
                          ),
                          onSubmitted: (_) => _submitQuery(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
                        onPressed: _submitQuery,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
