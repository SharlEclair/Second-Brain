import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'screens/chat_screen.dart';
import 'screens/debug_logs_screen.dart';
import 'services/api_service.dart';
import 'services/queue_service.dart';
import 'services/widget_service.dart';

void main() {
  runApp(const SecondBrainApp());
}

class SecondBrainApp extends StatefulWidget {
  const SecondBrainApp({super.key});

  @override
  State<SecondBrainApp> createState() => _SecondBrainAppState();
}

class _SecondBrainAppState extends State<SecondBrainApp> {
  static const _channel = MethodChannel('com.example.second_brain/actions');
  late StreamSubscription _intentDataStreamSubscription;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final ApiService _apiService = ApiService();
  final QueueService _queueService = QueueService();
  Timer? _sharedStatusTimer;
  String _lastSharedStatus = "";

  @override
  void initState() {
    super.initState();

    // Set up MethodChannel listener for widget actions
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'triggerAction') {
        final String? action = call.arguments as String?;
        if (action != null) {
          _handleWidgetAction(action);
        }
      }
    });

    // Check for any action that launched the app on startup
    _channel.invokeMethod<String>('getPendingAction').then((action) {
      if (action != null) {
        _handleWidgetAction(action);
      }
    });

    // Sync all widgets on startup
    WidgetService.syncAllWidgets(_apiService);

    // For sharing or intent containing text/files while app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final file = value.first;
        if (file.type == SharedMediaType.text || 
            file.type == SharedMediaType.url || 
            file.type == SharedMediaType.file) {
          _handleSharedData(file.path, isFile: file.type == SharedMediaType.file);
        }
      }
    }, onError: (err) {
      debugPrint("getMediaStream error: $err");
    });

    // For sharing or intent containing text/files while app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final file = value.first;
        if (file.type == SharedMediaType.text || 
            file.type == SharedMediaType.url || 
            file.type == SharedMediaType.file) {
          _handleSharedData(file.path, isFile: file.type == SharedMediaType.file);
        }
      }
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    _sharedStatusTimer?.cancel();
    super.dispose();
  }

  String _canonicalUrl(String value) {
    var cleaned = value.trim();
    final queryIndex = cleaned.indexOf('?');
    if (queryIndex >= 0) cleaned = cleaned.substring(0, queryIndex);
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  void _startSharedStatusPolling(String url) {
    _sharedStatusTimer?.cancel();
    _lastSharedStatus = "";
    final target = _canonicalUrl(url);
    _sharedStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final status = await _apiService.getStatus();
        final activeTasks = status['active_tasks'];
        if (activeTasks is! List) return;

        for (final task in activeTasks) {
          if (task is Map && _canonicalUrl((task['url'] ?? '').toString()) == target) {
            final progress = task['progress'];
            final progressText = progress is num ? ' ${progress.round()}%' : '';
            final message = '${(task['status'] ?? 'Processing').toString()}$progressText';
            if (message != _lastSharedStatus) {
              _lastSharedStatus = message;
              _showToast(message);
            }
            return;
          }
        }
      } catch (_) {
        // Status polling is best-effort for shared intents.
      }
    });
  }

  void _stopSharedStatusPolling() {
    _sharedStatusTimer?.cancel();
    _sharedStatusTimer = null;
    _lastSharedStatus = "";
  }

  void _handleSharedData(String sharedText, {bool isFile = false}) async {
    if (sharedText.isEmpty) return;

    if (isFile) {
      final fileName = sharedText.split('/').last;
      _showToast("Sharing File: $fileName");
      try {
        final lowerName = fileName.toLowerCase();
        if (lowerName.endsWith('.pdf') || lowerName.endsWith('.txt') || lowerName.endsWith('.md')) {
          final result = await _apiService.uploadFile(sharedText);
          _showToast("✓ File uploaded and ingested successfully!");
        } else {
          _showToast("❌ Only PDF, TXT, and MD files are supported");
        }
      } catch (e) {
        _showToast("❌ Upload Error: $e");
      }
      return;
    }
    
    // Extract URL if the shared text contains context (like "Check this out https://...")
    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = urlRegExp.firstMatch(sharedText);
    
    if (match != null) {
      final url = match.group(0)!;
      _showToast("Ingesting URL: $url");
      _startSharedStatusPolling(url);
      
      try {
        final result = await _apiService.ingestUrl(url);
        if (result['status'] == 'existing') {
          _showToast("✓ Already in your Brain Vault.");
        } else {
          _showToast("✓ Successfully ingested!");
        }
      } catch (e) {
        await _queueService.addToQueue(url);
        if (e is NetworkException) {
          _showToast("📌 Queued — will process when connected.");
        } else if (e is ServerException) {
          _showToast("📌 Queued (Server Error: ${e.message})");
        } else {
          _showToast("📌 Queued (${e.toString().substring(0, (e.toString().length).clamp(0, 45))})");
        }
      } finally {
        _stopSharedStatusPolling();
      }
    } else {
      // It is raw text without a URL!
      _showToast("Ingesting Shared Text Note...");
      try {
        final result = await _apiService.ingestRawText(sharedText);
        _showToast("✓ Shared text note saved successfully!");
      } on NetworkException {
        _showToast("❌ Offline: Can't ingest raw text now.");
      } on ServerException catch (e) {
        _showToast("❌ Error: ${e.message}");
      } catch (e) {
        _showToast("❌ Error: $e");
      }
    }
  }

  void _showToast(String message) {
    _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  void _handleWidgetAction(String action) async {
    DebugLogger.log('Triggering Widget Action: $action', type: 'WIDGET');
    
    switch (action) {
      case 'action/voice':
        _showToast('🎙️ Widget Shortcut: RAG Voice Chat focused.');
        // Bring app to foreground and show a friendly toast
        break;
      case 'action/clipboard':
        _showToast('📋 Widget Shortcut: Ingesting link from Clipboard...');
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && data!.text!.isNotEmpty) {
          _handleSharedData(data.text!);
        } else {
          _showToast('❌ Clipboard is empty');
        }
        break;
      case 'action/scratchpad':
        _showToast('✏️ Widget Shortcut: Launching Quick Scratchpad...');
        // We defer layout opening slightly to ensure context is ready
        Future.delayed(const Duration(milliseconds: 300), () => _showScratchpadDialog());
        break;
      case 'action/search':
        _showToast('🔍 Widget Shortcut: Focus Search Vault...');
        break;
    }
  }

  void _showScratchpadDialog() {
    final textController = TextEditingController();
    final titleController = TextEditingController();
    final BuildContext? dialogContext = _scaffoldMessengerKey.currentContext;
    if (dialogContext == null) return;

    showDialog(
      context: dialogContext,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: const BorderSide(color: Color(0xFF333333)),
          ),
          title: const Text("🧠 QUICK_SCRATCHPAD", style: TextStyle(color: Color(0xFFF97316), fontWeight: FontWeight.bold, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Title (Optional)...",
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF050505),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color(0xFF222222)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color(0xFFF97316)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Type note content here...",
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF050505),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color(0xFF222222)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Color(0xFFF97316)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final content = textController.text.trim();
                final title = titleController.text.trim();
                Navigator.pop(context);
                if (content.isNotEmpty) {
                  _showToast("Saving note to Vault...");
                  try {
                    await _apiService.ingestRawText(content, title: title.isNotEmpty ? title : null);
                    _showToast("✓ Note successfully archived!");
                    // Trigger a sync of widgets
                    WidgetService.syncAllWidgets(_apiService);
                  } catch (e) {
                    _showToast("❌ Failed to save note: $e");
                  }
                }
              },
              child: const Text("Save Note", style: TextStyle(color: Color(0xFFF97316), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
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
