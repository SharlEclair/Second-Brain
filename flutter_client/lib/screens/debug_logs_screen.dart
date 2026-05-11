import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DebugLog {
  final DateTime timestamp;
  final String message;
  final String type; // 'INFO', 'ERROR', 'NETWORK'

  DebugLog(this.message, {this.type = 'INFO'}) : timestamp = DateTime.now();
}

class DebugLogger {
  static final List<DebugLog> logs = [];
  static final ValueNotifier<int> logCount = ValueNotifier(0);

  static void log(String message, {String type = 'INFO'}) {
    logs.insert(0, DebugLog(message, type: type));
    if (logs.length > 200) logs.removeLast();
    logCount.value++;
    print('[$type] $message');
  }
}

class DebugLogsScreen extends StatelessWidget {
  const DebugLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('DEBUG LOGS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              DebugLogger.logs.clear();
              DebugLogger.logCount.value = 0;
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: DebugLogger.logCount,
        builder: (context, count, _) {
          if (DebugLogger.logs.isEmpty) {
            return const Center(child: Text('No logs yet.', style: TextStyle(color: Colors.white24)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: DebugLogger.logs.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 24),
            itemBuilder: (context, index) {
              final log = DebugLogger.logs[index];
              Color typeColor = Colors.blueAccent;
              if (log.type == 'ERROR') typeColor = Colors.redAccent;
              if (log.type == 'NETWORK') typeColor = Colors.greenAccent;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          border: Border.all(color: typeColor.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.type,
                          style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm:ss.SSS').format(log.timestamp),
                        style: const TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    log.message,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
