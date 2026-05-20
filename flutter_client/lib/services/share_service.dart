import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'api_service.dart';
import 'queue_service.dart';
import 'analytics_service.dart';
import '../widgets/ingest_spinner_dialog.dart';

class ShareService {
  static final ApiService _apiService = ApiService();
  static final QueueService _queueService = QueueService();
  
  static late final GlobalKey<NavigatorState> _navigatorKey;
  static late final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  
  static StreamSubscription? _intentDataStreamSubscription;
  static Timer? _sharedStatusTimer;
  static String _lastSharedStatus = "";

  static void initialize({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
  }) {
    _navigatorKey = navigatorKey;
    _scaffoldMessengerKey = scaffoldMessengerKey;

    // For sharing or intent containing text/files while app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final file = value.first;
        if (file.type == SharedMediaType.text || 
            file.type == SharedMediaType.url || 
            file.type == SharedMediaType.file) {
          ingestSharedText(file.path, isFile: file.type == SharedMediaType.file);
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
          ingestSharedText(file.path, isFile: file.type == SharedMediaType.file);
        }
      }
    });
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
    _sharedStatusTimer?.cancel();
  }

  static String _canonicalUrl(String value) {
    var cleaned = value.trim();
    final queryIndex = cleaned.indexOf('?');
    if (queryIndex >= 0) cleaned = cleaned.substring(0, queryIndex);
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  static void _startSharedStatusPolling(String url) {
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
      } catch (_) {}
    });
  }

  static void _stopSharedStatusPolling() {
    _sharedStatusTimer?.cancel();
    _sharedStatusTimer = null;
    _lastSharedStatus = "";
  }

  static void ingestSharedText(String sharedText, {bool isFile = false}) async {
    if (sharedText.isEmpty) return;

    if (isFile) {
      final fileName = sharedText.split('/').last;
      _showToast("Sharing File: $fileName");
      try {
        final lowerName = fileName.toLowerCase();
        if (lowerName.endsWith('.pdf') || lowerName.endsWith('.txt') || lowerName.endsWith('.md') || lowerName.endsWith('.mp3')) {
          await _apiService.uploadFile(sharedText);
          _showToast("✓ File uploaded and ingested successfully!");
        } else {
          _showToast("❌ Only PDF, TXT, MD, and MP3 files are supported");
        }
      } catch (e) {
        _showToast("❌ Upload Error: $e");
      }
      return;
    }
    
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
        await QueueService().addToQueue(url);
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
      _showToast("Ingesting Shared Text Note...");
      try {
        await _apiService.ingestRawText(sharedText);
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

  static void _showToast(String message) {
    _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        backgroundColor: const Color(0xFFF97316),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
