import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'screens/chat_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(const SecondBrainApp());
}

class SecondBrainApp extends StatefulWidget {
  const SecondBrainApp({super.key});

  @override
  State<SecondBrainApp> createState() => _SecondBrainAppState();
}

class _SecondBrainAppState extends State<SecondBrainApp> {
  late StreamSubscription _intentDataStreamSubscription;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();

    // For sharing or intent containing text (like URLs) while app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.getTextStream().listen((String value) {
      _handleSharedData(value);
    }, onError: (err) {
      debugPrint("getTextStream error: $err");
    });

    // For sharing or intent containing text while app is closed
    ReceiveSharingIntent.getInitialText().then((String? value) {
      if (value != null && value.isNotEmpty) {
        _handleSharedData(value);
      }
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  void _handleSharedData(String sharedText) async {
    if (sharedText.isEmpty) return;
    
    // Extract URL if the shared text contains context (like "Check this out https://...")
    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = urlRegExp.firstMatch(sharedText);
    if (match != null) {
      sharedText = match.group(0)!;
    }

    _showToast("Processing shared URL: $sharedText");
    
    try {
      await _apiService.ingestUrl(sharedText);
      _showToast("Successfully ingested into Second Brain!");
    } catch (e) {
      _showToast("Failed to ingest URL: Check server IP or connection.");
    }
  }

  void _showToast(String message) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Second Brain',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF97316), // Orange 500
          surface: Color(0xFF111111),
          background: Color(0xFF050505),
        ),
        scaffoldBackgroundColor: const Color(0xFF050505),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}
