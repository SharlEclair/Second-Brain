import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'queue_service.dart';
import 'audio_ingest_service.dart';
import 'api_service.dart';
import 'sync_service.dart';
import 'debug_logger.dart';

class OfflineQueueService {
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static final QueueService _queueService = QueueService();
  static final ApiService _apiService = ApiService();

  static void initialize() {
    if (_subscription != null) return;

    DebugLogger.log('Initializing Offline Queue Service (Connectivity listener)...', type: 'SYSTEM');

    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      bool isConnected = results.any((result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet);

      if (isConnected) {
        DebugLogger.log('Network connected! Syncing offline queues...', type: 'SYSTEM');
        
        // Process Isar ApiRequests
        try {
          await SyncService().syncUp();
        } catch (e) {
          DebugLogger.log('Error processing Isar syncUp: $e', type: 'ERROR');
        }

        // 1. Process Unified Ingestion queue
        try {
          final res = await _queueService.processQueue(_apiService);
          if (res.processed > 0) {
            DebugLogger.log('Synced ${res.processed} pending items from queue.', type: 'SYSTEM');
          }
        } catch (e) {
          DebugLogger.log('Error processing ingestion queue: $e', type: 'ERROR');
        }

        // 2. Process Audio Ingestion queue
        try {
          await AudioIngestService.processAudioQueue();
        } catch (e) {
          DebugLogger.log('Error processing audio queue: $e', type: 'ERROR');
        }
      }
    });
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
