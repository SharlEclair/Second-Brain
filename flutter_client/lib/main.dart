import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'screens/chat_screen.dart';
import 'services/api_service.dart';
import 'services/queue_service.dart';

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
  final QueueService _queueService = QueueService();

  @override
  void initState() {
    super.initState();

    // For sharing or intent containing text (like URLs) while app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final file = value.first;
        if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
          _handleSharedData(file.path);
        }
      }
    }, onError: (err) {
      debugPrint("getMediaStream error: $err");
    });

    // For sharing or intent containing text while app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final file = value.first;
        if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
          _handleSharedData(file.path);
        }
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

    _showToast("Processing: $sharedText");
    
    try {
      final result = await _apiService.ingestUrl(sharedText);
      if (result['status'] == 'existing') {
        _showToast("✓ Already in your Brain Vault.");
      } else {
        _showToast("✓ Successfully ingested!");
      }
    } catch (e) {
      // Network error — save to local queue for later processing
      await _queueService.addToQueue(sharedText);
      _showToast("📌 Saved to queue — will process when connected.");
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
        ),
        scaffoldBackgroundColor: const Color(0xFF050505),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}
