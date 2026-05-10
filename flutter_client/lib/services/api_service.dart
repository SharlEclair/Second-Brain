import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Custom exception to distinguish network errors from server errors
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => message;
}

class ServerException implements Exception {
  final String message;
  final int statusCode;
  ServerException(this.message, this.statusCode);
  @override
  String toString() => message;
}

class ApiService {
  static const String _keyBaseUrl = 'base_url';

  Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl);
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
  }

  Future<String> _buildUrl(String endpoint) async {
    final baseUrl = await getBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw ServerException('Backend URL is not set. Please set it in Settings.', 0);
    }
    // Remove all trailing slashes from base
    String cleanBase = baseUrl.trim();
    while (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }
    // Ensure endpoint starts with a single slash
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    
    return '$cleanBase$cleanEndpoint';
  }

  /// Quick connectivity check — returns error message if failed, null if success
  Future<String?> checkConnectivity() async {
    try {
      final apiUrl = await _buildUrl('/api/health');
      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return null;
      return 'Server returned ${response.statusCode}';
    } on TimeoutException {
      return 'Connection timed out (15s)';
    } on SocketException catch (e) {
      return 'Network unreachable: ${e.message}';
    } catch (e) {
      return e.toString();
    }
  }

  @Deprecated('Use checkConnectivity instead')
  Future<bool> isReachable() async {
    final err = await checkConnectivity();
    return err == null;
  }

  Future<Map<String, dynamic>> ingestUrl(String url) async {
    final apiUrl = await _buildUrl('/api/ingest');
    
    http.Response response;
    try {
      response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      ).timeout(const Duration(seconds: 180));
    } on SocketException catch (e) {
      throw NetworkException('Cannot reach server: $e');
    } on HttpException catch (e) {
      throw NetworkException('HTTP error: $e');
    } on TimeoutException {
      throw NetworkException('Connection timed out');
    } catch (e) {
      // Check if it's a network-level error
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Connection reset') ||
          e.toString().contains('No route to host') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('timed out') ||
          e.toString().contains('TimeoutException')) {
        throw NetworkException('Network error: $e');
      }
      throw NetworkException('Connection failed: $e');
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      // Server returned an error — this is NOT a network issue, don't queue
      String errorMsg;
      try {
        final body = jsonDecode(response.body);
        errorMsg = body['detail'] ?? body['error'] ?? body['message'] ?? 'Unknown server error';
      } catch (_) {
        errorMsg = 'Server error (${response.statusCode})';
      }
      throw ServerException(errorMsg, response.statusCode);
    }
  }

  Future<String> ask(String query) async {
    final apiUrl = await _buildUrl('/api/chat');
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': query}),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['answer'] ?? json['response'] ?? '';
    } else {
      throw Exception('Failed to get answer: ${response.statusCode}');
    }
  }

  Future<void> saveAnswer(String title, String content) async {
    final apiUrl = await _buildUrl('/api/save_answer');
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': title, 'content': content}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to save answer: ${response.statusCode}');
    }
  }

  Future<void> syncVault() async {
    final apiUrl = await _buildUrl('/api/sync');
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Failed to sync: ${response.statusCode}');
    }
  }
}
