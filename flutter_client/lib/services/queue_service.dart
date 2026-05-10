import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class QueueService {
  static const String _keyPendingUrls = 'pending_urls';

  /// Add a URL to the local queue
  Future<void> addToQueue(String url) async {
    final queue = await getQueue();
    if (!queue.contains(url)) {
      queue.add(url);
      await _saveQueue(queue);
    }
  }

  /// Get all queued URLs
  Future<List<String>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPendingUrls);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  /// Remove a single URL from the queue
  Future<void> removeFromQueue(String url) async {
    final queue = await getQueue();
    queue.remove(url);
    await _saveQueue(queue);
  }

  /// Clear the entire queue
  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendingUrls);
  }

  /// Process the entire queue. Returns a summary of results.
  Future<QueueProcessResult> processQueue(ApiService api) async {
    final queue = await getQueue();
    if (queue.isEmpty) return QueueProcessResult(processed: 0, failed: 0, total: 0, errors: {});

    int processed = 0;
    int failed = 0;
    final total = queue.length;
    final Map<String, String> errors = {};

    for (final url in List<String>.from(queue)) {
      try {
        await api.ingestUrl(url.trim());
        await removeFromQueue(url);
        processed++;
      } on ServerException catch (e) {
        failed++;
        errors[url] = e.message;
      } on NetworkException catch (e) {
        failed++;
        errors[url] = 'Network error: ${e.message}';
      } catch (e) {
        failed++;
        errors[url] = e.toString();
      }
    }

    return QueueProcessResult(processed: processed, failed: failed, total: total, errors: errors);
  }

  Future<void> _saveQueue(List<String> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPendingUrls, jsonEncode(queue));
  }
}

class QueueProcessResult {
  final int processed;
  final int failed;
  final int total;
  final Map<String, String> errors;

  QueueProcessResult({
    required this.processed, 
    required this.failed, 
    required this.total,
    required this.errors,
  });
}
