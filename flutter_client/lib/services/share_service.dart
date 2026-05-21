import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
  static const _channel = MethodChannel('com.example.second_brain/actions');

  static Future<bool> isShareActivity() async {
    try {
      final bool? isShare = await _channel.invokeMethod<bool>('isShareActivity');
      return isShare ?? false;
    } catch (_) {
      return false;
    }
  }

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
  }

  static void ingestSharedText(String sharedText, {bool isFile = false}) async {
    if (sharedText.isEmpty) return;

    if (isFile) {
      final fileName = sharedText.split('/').last;
      _showToast("Sharing File: $fileName");
      final isShareAct = await isShareActivity();
      try {
        final lowerName = fileName.toLowerCase();
        if (lowerName.endsWith('.pdf') || lowerName.endsWith('.txt') || lowerName.endsWith('.md') || lowerName.endsWith('.mp3')) {
          await _apiService.uploadFile(sharedText);
          _showToast("✓ File uploaded and ingested successfully!");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        } else {
          _showToast("❌ Only PDF, TXT, MD, and MP3 files are supported");
          _showToastNotification("❌ Unsupported file format");
        }
      } catch (e) {
        _showToast("❌ Upload Error: $e");
        _showToastNotification("❌ Upload Error");
      } finally {
        if (isShareAct) {
          await _channel.invokeMethod('finishActivity');
        }
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
      final isShareAct = await isShareActivity();
      
      if (!isShareAct && context != null) {
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
          _showToastNotification("Cortex: Saved to Vault 🧠");
        } else {
          _showToast("✓ Successfully ingested!");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        }
      } catch (e) {
        await _queueService.addToQueue(url);
        AnalyticsService().logIngest('url_queue', 'share_intent', details: url);
        if (e is NetworkException) {
          _showToast("📌 Queued — will process when connected.");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        } else if (e is ServerException) {
          _showToast("📌 Queued (Server Error: ${e.message})");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        } else {
          _showToast("📌 Queued (${e.toString().substring(0, (e.toString().length).clamp(0, 45))})");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        }
      } finally {
        if (dialogOpen && _navigatorKey.currentContext != null) {
          Navigator.of(_navigatorKey.currentContext!).pop();
        }
        if (isShareAct) {
          await _channel.invokeMethod('finishActivity');
        }
      }
    } else {
      _showToast("Ingesting Shared Text Note...");
      final isShareAct = await isShareActivity();
      try {
        await _apiService.ingestRawText(sharedText);
        AnalyticsService().logIngest('text', 'share_intent');
        _showToast("✓ Shared text note saved successfully!");
        _showToastNotification("Cortex: Saved to Vault 🧠");
      } on NetworkException {
        _showToast("❌ Offline: Can't ingest raw text now.");
        _showToastNotification("❌ Offline: Can't ingest raw text now.");
      } on ServerException catch (e) {
        _showToast("❌ Error: ${e.message}");
        _showToastNotification("❌ Error: ${e.message}");
      } catch (e) {
        _showToast("❌ Error: $e");
        _showToastNotification("❌ Error: $e");
      } finally {
        if (isShareAct) {
          await _channel.invokeMethod('finishActivity');
        }
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

  static void _showToastNotification(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: const Color(0xFFF97316),
      textColor: Colors.white,
      fontSize: 13.0
    );
  }
}
