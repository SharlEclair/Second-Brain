import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class QueueService {
  static const String _keyPendingUrls = 'pending_urls';
  static const String _keyRetryCounts = 'queue_retry_counts';

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
    
    // Clean up retry count
    final retryCounts = await _getRetryCounts();
    if (retryCounts.containsKey(url)) {
      retryCounts.remove(url);
      await _saveRetryCounts(retryCounts);
    }
  }

  /// Clear the entire queue
  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendingUrls);
    await prefs.remove(_keyRetryCounts);
  }

  Future<QueueProcessResult> processQueue(ApiService api) async {
    final queue = await getQueue();
    if (queue.isEmpty) return QueueProcessResult(processed: 0, failed: 0, total: 0, errors: {}, failedPermanently: []);

    int processed = 0;
    int failed = 0;
    final total = queue.length;
    final Map<String, String> errors = {};
    final List<String> failedPermanently = [];
    final retryCounts = await _getRetryCounts();

    for (final url in List<String>.from(queue)) {
      try {
        await api.ingestUrl(url.trim());
        await removeFromQueue(url);
        processed++;
      } on ServerException catch (e) {
        _handleFailure(url, e.message, retryCounts, failedPermanently, errors);
        failed++;
      } on NetworkException catch (e) {
        _handleFailure(url, 'Network error: ${e.message}', retryCounts, failedPermanently, errors);
        failed++;
      } catch (e) {
        _handleFailure(url, e.toString(), retryCounts, failedPermanently, errors);
        failed++;
      }
    }

    await _saveRetryCounts(retryCounts);
    return QueueProcessResult(
      processed: processed, 
      failed: failed, 
      total: total, 
      errors: errors,
      failedPermanently: failedPermanently,
    );
  }

  void _handleFailure(
    String url, 
    String errorMessage, 
    Map<String, int> retryCounts, 
    List<String> failedPermanently, 
    Map<String, String> errors
  ) {
    errors[url] = errorMessage;
    retryCounts[url] = (retryCounts[url] ?? 0) + 1;
    if (retryCounts[url]! >= 3) {
      removeFromQueue(url);
      failedPermanently.add(url);
    }
  }

  Future<void> _saveQueue(List<String> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPendingUrls, jsonEncode(queue));
  }

  Future<Map<String, int>> _getRetryCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyRetryCounts);
    if (raw == null || raw.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      return decoded.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveRetryCounts(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRetryCounts, jsonEncode(counts));
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
