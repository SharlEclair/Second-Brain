import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_logger.dart';

class AudioIngestService {
  static Future<bool> uploadAudio(String filePath) async {
    await queueAudioUpload(filePath);
    final success = await _uploadAudioRaw(filePath);
    if (success) {
      await dequeueAudioUpload(filePath);
    }
    return success;
  }

  static Future<bool> _uploadAudioRaw(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('base_url');
      if (baseUrl == null || baseUrl.isEmpty) {
        DebugLogger.log('Audio upload failed: baseUrl not set', type: 'ERROR');
        return false;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        DebugLogger.log('Audio file does not exist: $filePath', type: 'ERROR');
        return false;
      }

      final url = Uri.parse('$baseUrl/api/upload');
      final request = http.MultipartRequest('POST', url)
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      DebugLogger.log('Uploading audio to backend: ${file.path}', type: 'SYSTEM');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        DebugLogger.log('Audio uploaded and ingested successfully', type: 'SYSTEM');
        try {
          await file.delete();
        } catch (_) {}
        return true;
      } else {
        DebugLogger.log('Audio upload failed with status: ${response.statusCode}, body: ${response.body}', type: 'ERROR');
        return false;
      }
    } catch (e) {
      DebugLogger.log('Error uploading audio: $e', type: 'ERROR');
      return false;
    }
  }

  static Future<void> queueAudioUpload(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> queue = prefs.getStringList('pending_audio_uploads') ?? [];
      if (!queue.contains(filePath)) {
        queue.add(filePath);
        await prefs.setStringList('pending_audio_uploads', queue);
        DebugLogger.log('Queued audio file for offline upload: $filePath', type: 'STORAGE');
      }
    } catch (e) {
      DebugLogger.log('Failed to queue audio upload: $e', type: 'ERROR');
    }
  }

  static Future<void> dequeueAudioUpload(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> queue = prefs.getStringList('pending_audio_uploads') ?? [];
      if (queue.contains(filePath)) {
        queue.remove(filePath);
        await prefs.setStringList('pending_audio_uploads', queue);
        DebugLogger.log('Removed audio file from queue: $filePath', type: 'STORAGE');
      }
    } catch (e) {
      DebugLogger.log('Failed to dequeue audio upload: $e', type: 'ERROR');
    }
  }

  static Future<void> processAudioQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> queue = prefs.getStringList('pending_audio_uploads') ?? [];
      if (queue.isEmpty) return;

      DebugLogger.log('Processing queued offline audio uploads: ${queue.length} items', type: 'SYSTEM');
      final List<String> succeeded = [];

      for (final filePath in queue) {
        final file = File(filePath);
        if (!await file.exists()) {
          succeeded.add(filePath); // File no longer exists, consider it processed
          continue;
        }
        final success = await _uploadAudioRaw(filePath);
        if (success) {
          succeeded.add(filePath);
        }
      }

      if (succeeded.isNotEmpty) {
        final List<String> remaining = queue.where((p) => !succeeded.contains(p)).toList();
        await prefs.setStringList('pending_audio_uploads', remaining);
        DebugLogger.log('Processed audio queue: ${succeeded.length} succeeded, ${remaining.length} remaining', type: 'SYSTEM');
      }
    } catch (e) {
      DebugLogger.log('Error processing audio queue: $e', type: 'ERROR');
    }
  }
}
