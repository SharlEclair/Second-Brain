import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/chat_screen.dart';
import 'screens/notes_browser_screen.dart';
import 'screens/debug_logs_screen.dart';
import 'services/api_service.dart';
import 'services/queue_service.dart';
import 'services/widget_service.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  final prefs = await SharedPreferences.getInstance();
  final isLight = prefs.getBool('is_light_theme') ?? false;
  themeNotifier.value = isLight ? ThemeMode.light : ThemeMode.dark;
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint("Failed to initialize NotificationService: $e");
  }
  runApp(const SecondBrainApp());
}

class SecondBrainApp extends StatefulWidget {
  const SecondBrainApp({super.key});

  @override
  State<SecondBrainApp> createState() => _SecondBrainAppState();
}

class _SecondBrainAppState extends State<SecondBrainApp> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.second_brain/actions');
  late StreamSubscription _intentDataStreamSubscription;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String? _lastCheckedClipboardUrl;
  final ApiService _apiService = ApiService();
  final QueueService _queueService = QueueService();
  Timer? _sharedStatusTimer;
  String _lastSharedStatus = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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
    WidgetsBinding.instance.removeObserver(this);
    _intentDataStreamSubscription.cancel();
    _sharedStatusTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForIngest();
    }
  }

  Future<void> _checkClipboardForIngest() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        final urlPattern = RegExp(
          r'^(https?:\/\/[^\s$.?#].[^\s]*)$',
          caseSensitive: false,
        );
        if (urlPattern.hasMatch(text)) {
          if (text != _lastCheckedClipboardUrl) {
            _lastCheckedClipboardUrl = text;
            _showClipboardIngestSheet(text);
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking clipboard: $e");
    }
  }

  void _showClipboardIngestSheet(String url) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xE61E1E2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.link, color: Colors.blueAccent),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Link Detected in Clipboard",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        "Dismiss",
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleSharedData(url);
                      },
                      child: const Text("Ingest Link"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
        if (lowerName.endsWith('.pdf') || lowerName.endsWith('.txt') || lowerName.endsWith('.md') || lowerName.endsWith('.mp3')) {
          final result = await _apiService.uploadFile(sharedText);
          _showToast("✓ File uploaded and ingested successfully!");
        } else {
          _showToast("❌ Only PDF, TXT, MD, and MP3 files are supported");
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
      
      final context = _navigatorKey.currentContext;
      bool dialogOpen = false;
      if (context != null) {
        dialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => IngestSpinnerDialog(url: url, apiService: _apiService),
        ).then((_) {
          dialogOpen = false;
        });
      }
      
      try {
        final result = await _apiService.ingestUrl(url);
        AnalyticsService().logIngest('url', 'share_intent', details: url);
        if (result['status'] == 'existing') {
          _showToast("✓ Already in your Brain Vault.");
        } else {
          _showToast("✓ Successfully ingested!");
        }
      } catch (e) {
        await _queueService.addToQueue(url);
        AnalyticsService().logIngest('url_queue', 'share_intent', details: url);
        if (e is NetworkException) {
          _showToast("📌 Queued — will process when connected.");
        } else if (e is ServerException) {
          _showToast("📌 Queued (Server Error: ${e.message})");
        } else {
          _showToast("📌 Queued (${e.toString().substring(0, (e.toString().length).clamp(0, 45))})");
        }
      } finally {
        if (dialogOpen && _navigatorKey.currentContext != null) {
          Navigator.of(_navigatorKey.currentContext!).pop();
        }
      }
    } else {
      // It is raw text without a URL!
      _showToast("Ingesting Shared Text Note...");
      try {
        final result = await _apiService.ingestRawText(sharedText);
        AnalyticsService().logIngest('text', 'share_intent');
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
    
    // Pop any open sub-screens/overlays to ensure we are at the root context
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);

    switch (action) {
      case 'action/voice':
        _showToast('🎙️ Voice Assistant Mode');
        ChatScreen.widgetActionNotifier.value = 'action/voice';
        // Reset the value immediately so the listener triggers on consecutive taps
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ChatScreen.widgetActionNotifier.value = null;
        });
        break;
      case 'action/clipboard':
        _showToast('📋 Ingesting link from Clipboard...');
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && data!.text!.isNotEmpty) {
          _handleSharedData(data.text!);
        } else {
          _showToast('❌ Clipboard is empty');
        }
        break;
      case 'action/scratchpad':
        _showToast('✏️ Launching Quick Scratchpad...');
        Future.delayed(const Duration(milliseconds: 300), () => _showScratchpadDialog());
        break;
      case 'action/search':
        _showToast('🔍 Notes Browser focused');
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const NotesBrowserScreen(focusSearch: true))
        );
        break;
    }
  }

  void _showScratchpadDialog() {
    final textController = TextEditingController();
    final titleController = TextEditingController();
    final BuildContext? dialogContext = _navigatorKey.currentContext;
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
                    AnalyticsService().logIngest('scratchpad', 'in_app', details: title.isNotEmpty ? title : 'Scratchpad Note');
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Second Brain',
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFEA580C),
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
            scaffoldBackgroundColor: const Color(0xFFFAFAFA),
            useMaterial3: true,
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF97316),
              surface: Color(0xFF111111),
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF050505),
            useMaterial3: true,
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF111111),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          home: const ChatScreen(),
        );
      },
    );
  }
}

class IngestSpinnerDialog extends StatefulWidget {
  final String url;
  final ApiService apiService;

  const IngestSpinnerDialog({
    super.key,
    required this.url,
    required this.apiService,
  });

  @override
  State<IngestSpinnerDialog> createState() => _IngestSpinnerDialogState();
}

class _IngestSpinnerDialogState extends State<IngestSpinnerDialog> {
  String _statusMessage = "Preparing knowledge ingestion...";
  double _progress = 0.0;
  Timer? _timer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    final target = _canonicalUrl(widget.url);
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_finished) return;
      try {
        final status = await widget.apiService.getStatus();
        final activeTasks = status['active_tasks'];
        if (activeTasks is List) {
          for (final task in activeTasks) {
            if (task is Map && _canonicalUrl((task['url'] ?? '').toString()) == target) {
              final taskStatus = task['status'] ?? 'Processing';
              final progressVal = task['progress'];
              if (mounted) {
                setState(() {
                  _statusMessage = taskStatus.toString();
                  if (progressVal is num) {
                    _progress = progressVal.toDouble() / 100.0;
                  }
                });
              }
              break;
            }
          }
        }
      } catch (_) {}
    });
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: const Color(0xEE0A0A0C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEA580C).withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "KNOWLEDGE INGESTION",
                style: TextStyle(
                  color: Color(0xFFEA580C),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      strokeWidth: 4,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEA580C)),
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  const Icon(
                    Icons.psychology,
                    size: 36,
                    color: Color(0xFFEA580C),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.url,
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
