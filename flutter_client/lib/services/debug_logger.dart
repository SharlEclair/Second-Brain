import 'dart:developer' as dev;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime timestamp;
  final String message;
  final String type; // 'NETWORK', 'UI', 'ERROR', 'INGEST'

  LogEntry({required this.message, required this.type}) : timestamp = DateTime.now();
}

class DebugLogger {
  static final List<LogEntry> logs = [];
  static const int maxLogs = 200;
  static final ValueNotifier<int> logCount = ValueNotifier<int>(0);

  static void log(String message, {String type = 'INFO'}) {
    final entry = LogEntry(message: message, type: type);
    logs.insert(0, entry);
    if (logs.length > maxLogs) logs.removeLast();
    
    final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp);
    dev.log('[$timeStr] [$type] $message');
    logCount.value++;
  }

  static void clear() {
    logs.clear();
    logCount.value = 0;
  }
}
