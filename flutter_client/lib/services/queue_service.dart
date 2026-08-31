import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'widget_service.dart';

class QueueItem {
  final String id;
  final String type; // 'url', 'text', 'file'
  final String payload; // URL, text content, or local file path
  final String? title; // Optional title/filename
  final DateTime createdAt;
  int retryCount;
  bool isFailed;
  String? error;

  QueueItem({
    required this.id,
    required this.type,
    required this.payload,
    this.title,
    DateTime? createdAt,
    this.retryCount = 0,
    this.isFailed = false,
    this.error,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'isFailed': isFailed,
    'error': error,
  };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'] ?? '',
    type: json['type'] ?? '',
    payload: json['payload'] ?? '',
    title: json['title'],
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    retryCount: json['retryCount'] ?? 0,
    isFailed: json['isFailed'] ?? false,
    error: json['error'],
  );
}

class QueueService {
  static const String _keyPendingItems = 'pending_queue_items';
  static const String _keyFailedItems = 'failed_queue_items';

  /// Add a QueueItem to the local queue
  Future<void> addToQueue(QueueItem item) async {
    final queue = await getQueue();
    // Check if item already exists by checking payload (or ID)
    if (!queue.any((element) => element.payload == item.payload)) {
      queue.add(item);
      await _saveQueue(queue);
    }
  }

  /// Get all queued items
  Future<List<QueueItem>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPendingItems);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((item) => QueueItem.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Remove a single item from the queue by ID or payload
  Future<void> removeFromQueue(String id) async {
    final queue = await getQueue();
    queue.removeWhere((item) => item.id == id || item.payload == id);
    await _saveQueue(queue);
  }

  /// Clear the entire queue
  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendingItems);
  }

  /// Get all failed queued items
  Future<List<QueueItem>> getFailedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFailedItems);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((item) => QueueItem.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save the failed queue
  Future<void> _saveFailedQueue(List<QueueItem> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(queue.map((item) => item.toJson()).toList());
    await prefs.setString(_keyFailedItems, raw);
  }

  /// Remove a single item from the failed queue by ID or payload
  Future<void> removeFromFailedQueue(String id) async {
    final queue = await getFailedQueue();
    queue.removeWhere((item) => item.id == id || item.payload == id);
    await _saveFailedQueue(queue);
  }

  /// Clear the entire failed queue
  Future<void> clearFailedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFailedItems);
  }

  /// Move a link from the failed queue back into the active pending queue
  Future<void> moveToPendingQueue(QueueItem item) async {
    await removeFromFailedQueue(item.id);
    item.isFailed = false;
    item.retryCount = 0;
    item.error = null;
    await addToQueue(item);
  }

  Future<QueueProcessResult> processQueue(ApiService api) async {
    final queue = await getQueue();
    
    if (queue.isEmpty) {
      return QueueProcessResult(processed: 0, failed: 0, total: 0, errors: {}, failedPermanently: []);
    }

    final pendingItems = queue;
    int processed = 0;
    int failed = 0;
    final total = pendingItems.length;
    final Map<String, String> errors = {};
    final List<String> failedPermanently = [];

    // Working copy of queue to update states
    final updatedQueue = List<QueueItem>.from(queue);

    for (final item in pendingItems) {
      try {
        if (item.type == 'url') {
          await WidgetService.startIngestionLiveActivity(item.payload);
          await WidgetService.updateIngestionLiveActivity(item.payload, 'Processing Queue...', 0.3);
          await api.ingestUrl(item.payload.trim());
          await WidgetService.updateIngestionLiveActivity(item.payload, 'Saving to Vault...', 0.8);
          await WidgetService.endIngestionLiveActivity(item.payload, isSuccess: true);
        } else if (item.type == 'text') {
          await api.ingestRawText(item.payload, title: item.title);
        } else if (item.type == 'file') {
          await api.uploadFile(item.payload, customFileName: item.title);
        }
        
        // Remove from persistent queue only upon verified success
        await removeFromQueue(item.id);
        updatedQueue.removeWhere((element) => element.id == item.id);
        processed++;
      } catch (e) {
        failed++;
        final errorMessage = e.toString();
        errors[item.payload] = errorMessage;
        
        // Find item in updatedQueue and increment retryCount
        final idx = updatedQueue.indexWhere((element) => element.id == item.id);
        if (idx != -1) {
          updatedQueue[idx].retryCount++;
          updatedQueue[idx].error = errorMessage;
          
          if (updatedQueue[idx].retryCount >= 5) {
            updatedQueue[idx].isFailed = true;
            failedPermanently.add(item.payload);
            
            // Save to failed queue
            final failedQueue = await getFailedQueue();
            if (!failedQueue.any((element) => element.payload == item.payload)) {
              failedQueue.add(updatedQueue[idx]);
              await _saveFailedQueue(failedQueue);
            }
            
            // Remove from updatedQueue (so it won't be saved in pending queue)
            updatedQueue.removeAt(idx);
          }
        }
        
        // Update Live Activity on error if it's a URL
        if (item.type == 'url') {
          await WidgetService.endIngestionLiveActivity(item.payload, isSuccess: false, error: 'Queue: Ingestion Failed');
        }
      }
    }

    // Save the updated queue states (with incremented retries/failed flags)
    await _saveQueue(updatedQueue);

    return QueueProcessResult(
      processed: processed, 
      failed: failed, 
      total: total, 
      errors: errors,
      failedPermanently: failedPermanently,
    );
  }

  Future<void> _saveQueue(List<QueueItem> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(queue.map((item) => item.toJson()).toList());
    await prefs.setString(_keyPendingItems, raw);
  }
}

class QueueProcessResult {
  final int processed;
  final int failed;
  final int total;
  final Map<String, String> errors;
  final List<String> failedPermanently;

  QueueProcessResult({
    required this.processed, 
    required this.failed, 
    required this.total,
    required this.errors,
    required this.failedPermanently,
  });
}
