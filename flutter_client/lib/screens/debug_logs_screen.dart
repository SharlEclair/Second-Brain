import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/debug_logger.dart';

class DebugLogsScreen extends StatelessWidget {
  const DebugLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF050505) : const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('DEBUG LOGS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, color: Colors.blueAccent),
            tooltip: 'Copy all logs',
            onPressed: () {
              final allLogs = DebugLogger.logs
                  .map((l) => '[${l.type}] ${DateFormat('HH:mm:ss').format(l.timestamp)}: ${l.message}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: allLogs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All logs copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              DebugLogger.clear();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: DebugLogger.logCount,
        builder: (context, count, _) {
          if (DebugLogger.logs.isEmpty) {
            return Center(child: Text('No logs yet.', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: DebugLogger.logs.length,
            separatorBuilder: (context, index) => Divider(color: isDark ? Colors.white10 : Colors.black12, height: 24),
            itemBuilder: (context, index) {
              final log = DebugLogger.logs[index];
              Color typeColor = Colors.blueAccent;
              if (log.type == 'ERROR') typeColor = Colors.redAccent;
              if (log.type == 'NETWORK') typeColor = isDark ? Colors.greenAccent : const Color(0xFF16A34A);

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
                        style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 10),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.copy, size: 14, color: isDark ? Colors.white54 : Colors.black54),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          final formatted = '[${log.type}] ${DateFormat('HH:mm:ss').format(log.timestamp)}: ${log.message}';
                          Clipboard.setData(ClipboardData(text: formatted));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Log copied to clipboard'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    log.message,
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13, fontFamily: 'monospace'),
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
