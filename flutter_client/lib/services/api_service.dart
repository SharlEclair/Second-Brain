import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
      throw Exception('Backend URL is not set. Please set it in Settings.');
    }
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanBase$endpoint';
  }

  Future<Map<String, dynamic>> ingestUrl(String url) async {
    final apiUrl = await _buildUrl('/api/ingest');
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    ).timeout(const Duration(seconds: 180));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception('Failed to ingest URL: $error');
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
