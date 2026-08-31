import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'queue_service.dart';
import 'analytics_service.dart';
import 'widget_service.dart';
import 'haptic_feedback_manager.dart';

import '../theme/design_tokens.dart';

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

      final queueItem = QueueItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'file',
        payload: sharedText,
        title: fileName,
      );
      await _queueService.addToQueue(queueItem);

      try {
        final lowerName = fileName.toLowerCase();
        if (lowerName.endsWith('.pdf') || lowerName.endsWith('.txt') || lowerName.endsWith('.md') || lowerName.endsWith('.mp3')) {
          await _apiService.uploadFile(sharedText);
          
          // Remove only on successful verification
          await _queueService.removeFromQueue(queueItem.id);

          _showToast("✓ File uploaded and ingested successfully!");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        } else {
          // File format unsupported, we can remove it as it won't ever succeed
          await _queueService.removeFromQueue(queueItem.id);
          _showToast("❌ Only PDF, TXT, MD, and MP3 files are supported");
          _showToastNotification("❌ Unsupported file format");
        }
      } catch (e) {
        _showToast("❌ Upload Error (Queued): $e");
        _showToastNotification("📌 Saved to Queue");
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
      String url = match.group(0)!;
      url = url.replaceAll(RegExp(r'[.,;!?)>\]]+$'), '');
      _showToast("⏳ Ingesting URL: $url");
      
      final isShareAct = await isShareActivity();

      final queueItem = QueueItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'url',
        payload: url,
      );
      await _queueService.addToQueue(queueItem);
      
      // Connectivity pre-check: if offline, skip API call and queue silently
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
      
      if (!isOnline) {
        // Offline: skip API call, item is already in queue
        await HapticFeedbackManager.lightImpact();
        _showToast("📌 Queued — will sync when online.");
        _showToastNotification("Cortex: Ingestion Queued 📌");
        if (isShareAct) {
          await _channel.invokeMethod('finishActivity');
        }
      } else {
        try {
          await WidgetService.startIngestionLiveActivity(url);
          await WidgetService.updateIngestionLiveActivity(url, 'Parsing URL...', 0.3);
          final result = await _apiService.ingestUrl(url);
          await WidgetService.updateIngestionLiveActivity(url, 'Saving to Vault...', 0.8);
          AnalyticsService().logIngest('url', 'share_intent', details: url);

          // Success verification - remove from queue
          await _queueService.removeFromQueue(queueItem.id);

          // Non-blocking success feedback
          await HapticFeedbackManager.mediumImpact();
          if (result['status'] == 'existing') {
            _showToast("✓ Already in your Brain Vault.");
          } else if (result['status'] == 'queued') {
            _showToast("✓ Ingestion queued in background!");
          } else {
            _showToast("✓ Successfully ingested!");
          }
          _showToastNotification("Cortex: Saved to Vault 🧠");
          await WidgetService.endIngestionLiveActivity(url, isSuccess: true);
        } catch (e) {
          AnalyticsService().logIngest('url_queue', 'share_intent', details: url);
          if (e is NetworkException) {
            _showToast("📌 Queued — will process when connected.");
            _showToastNotification("Cortex: Ingestion Queued 📌");
            await WidgetService.endIngestionLiveActivity(url, isSuccess: false, error: 'Queued (Offline)');
          } else if (e is ServerException) {
            _showToast("📌 Queued (Server Error: ${e.message})");
            _showToastNotification("Cortex: Ingestion Queued 📌");
            await WidgetService.endIngestionLiveActivity(url, isSuccess: false, error: 'Queued (Server Error)');
          } else {
            _showToast("📌 Queued (${e.toString().substring(0, (e.toString().length).clamp(0, 45))})");
            _showToastNotification("Cortex: Ingestion Queued 📌");
            await WidgetService.endIngestionLiveActivity(url, isSuccess: false, error: 'Queued');
          }
        } finally {
          if (isShareAct) {
            await _channel.invokeMethod('finishActivity');
          }
        }
      }
    } else {
      _showToast("Ingesting Shared Text Note...");
      final isShareAct = await isShareActivity();

      final queueItem = QueueItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'text',
        payload: sharedText,
      );
      await _queueService.addToQueue(queueItem);

      // Connectivity pre-check
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOnline = connectivityResult.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

      if (!isOnline) {
        await HapticFeedbackManager.lightImpact();
        _showToast("📌 Queued — will sync when online.");
        _showToastNotification("Cortex: Ingestion Queued 📌");
        if (isShareAct) {
          await _channel.invokeMethod('finishActivity');
        }
      } else {
        try {
          await _apiService.ingestRawText(sharedText);
          AnalyticsService().logIngest('text', 'share_intent');
          
          // Remove on success
          await _queueService.removeFromQueue(queueItem.id);

          await HapticFeedbackManager.mediumImpact();
          _showToast("✓ Shared text note saved successfully!");
          _showToastNotification("Cortex: Saved to Vault 🧠");
        } on NetworkException {
          _showToast("📌 Queued — will process when connected.");
          _showToastNotification("Cortex: Ingestion Queued 📌");
        } on ServerException catch (e) {
          _showToast("📌 Queued (Server Error: ${e.message})");
          _showToastNotification("Cortex: Ingestion Queued 📌");
        } catch (e) {
          _showToast("📌 Queued (Error: $e)");
          _showToastNotification("Cortex: Ingestion Queued 📌");
        } finally {
          if (isShareAct) {
            await _channel.invokeMethod('finishActivity');
          }
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
        backgroundColor: AppColors.accent,
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
      backgroundColor: AppColors.accent,
      textColor: Colors.white,
      fontSize: 13.0
    );
  }
}
