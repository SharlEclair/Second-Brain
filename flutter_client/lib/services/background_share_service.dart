import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'api_service.dart';
import 'queue_service.dart';
import 'haptic_feedback_manager.dart';
import '../theme/design_tokens.dart';

class BackgroundShareService {
  static final ApiService _apiService = ApiService();
  static final QueueService _queueService = QueueService();
  static StreamSubscription? _intentDataStreamSubscription;
  static const _channel = MethodChannel('com.example.second_brain/actions');

  static void initialize() {
    // Listen for shared text/URLs when app is running or in background
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFile(value.first);
      }
    }, onError: (err) {
      debugPrint("BackgroundShareService stream error: $err");
    });

    // Check for initial shared media when app is launched from terminated state
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFile(value.first);
      }
    });
  }

  static void _handleSharedFile(SharedMediaFile file) async {
    final sharedText = file.path;
    if (sharedText.isEmpty) return;

    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = urlRegExp.firstMatch(sharedText);

    final type = match != null ? 'url' : 'text';
    final payload = match != null ? match.group(0)! : sharedText;

    final queueItem = QueueItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      payload: payload,
    );
    await _queueService.addToQueue(queueItem);

    try {
      if (type == 'url') {
        await _apiService.ingestUrl(payload);
      } else {
        await _apiService.ingestRawText(payload);
      }
      
      // Verified success - remove from queue
      await _queueService.removeFromQueue(queueItem.id);
      
      // Haptic feedback
      await HapticFeedbackManager.mediumImpact();
      
      // Visual feedback toast
      Fluttertoast.showToast(
        msg: "Cortex: Saved to Vault 🧠",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: AppColors.accent,
        textColor: Colors.white,
        fontSize: 13.0,
      );
    } catch (e) {
      debugPrint("Background ingestion error (Queued): $e");
      
      // Kept in queue, trigger light feedback
      await HapticFeedbackManager.lightImpact();
      Fluttertoast.showToast(
        msg: "Cortex: Ingestion Queued 📌",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: AppColors.accent,
        textColor: Colors.white,
        fontSize: 13.0,
      );
    } finally {
      // Close the ShareActivity if we launched from it
      try {
        final bool? isShare = await _channel.invokeMethod<bool>('isShareActivity');
        if (isShare == true) {
          await _channel.invokeMethod('finishActivity');
        }
      } catch (_) {}
    }
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
  }
}
