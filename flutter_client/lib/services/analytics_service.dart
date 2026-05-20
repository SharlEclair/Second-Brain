import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  static const String _keyLogs = 'cortex_analytics_logs';
  final ApiService _apiService = ApiService();

  Future<void> logEvent(String eventType, Map<String, dynamic> metadata) async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getStringList(_keyLogs) ?? [];
    
    final logEntry = {
      'event_type': eventType,
      'timestamp': DateTime.now().toIso8601String(),
      'metadata': metadata,
    };
    
    logsJson.add(jsonEncode(logEntry));
    await prefs.setStringList(_keyLogs, logsJson);
    
    // Trigger an asynchronous sync attempt
    syncAnalytics();
  }

  Future<List<Map<String, dynamic>>> getLocalLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final logsJson = prefs.getStringList(_keyLogs) ?? [];
    return logsJson
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
  }

  Future<void> syncAnalytics() async {
    try {
      final logs = await getLocalLogs();
      if (logs.isEmpty) return;

      final response = await _apiService.postAnalytics(logs);
      if (response['status'] == 'success') {
        // Clear logs locally upon successful sync
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_keyLogs, []);
      }
    } catch (_) {
      // Keep logs locally for next retry if sync fails
    }
  }

  Future<void> logSearch(String query) => logEvent('search', {'query': query});
  Future<void> logRead(String noteTitle) => logEvent('read', {'note_title': noteTitle});
  Future<void> logEdit(String noteTitle) => logEvent('edit', {'note_title': noteTitle});
  Future<void> logIngest(String type, String source, {String? details}) {
    return logEvent('ingest', {
      'type': type,
      'source': source,
      if (details != null) 'details': details,
    });
  }
}
