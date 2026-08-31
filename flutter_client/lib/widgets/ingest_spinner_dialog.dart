import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class IngestSpinnerDialog extends StatefulWidget {
  final String url;
  final ApiService apiService;

  const IngestSpinnerDialog({
    super.key,
    required this.url,
    required this.apiService,
  });

  @override
  State<IngestSpinnerDialog> createState() => _IngestSpinnerDialogState();
}

class _IngestSpinnerDialogState extends State<IngestSpinnerDialog> {
  String _statusMessage = "Preparing knowledge ingestion...";
  double _progress = 0.0;
  Timer? _timer;
  final bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    final target = _canonicalUrl(widget.url);
    _timer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_finished) return;
      try {
        final status = await widget.apiService.getStatus();
        final activeTasks = status['active_tasks'];
        if (activeTasks is List) {
          for (final task in activeTasks) {
            if (task is Map && _canonicalUrl((task['url'] ?? '').toString()) == target) {
              final taskStatus = task['status'] ?? 'Processing';
              final progressVal = task['progress'];
              if (mounted) {
                setState(() {
                  _statusMessage = taskStatus.toString();
                  if (progressVal is num) {
                    _progress = progressVal.toDouble() / 100.0;
                  }
                });
              }
              break;
            }
          }
        }
      } catch (_) {}
    });
  }

  String _canonicalUrl(String value) {
    var cleaned = value.trim();
    final queryIndex = cleaned.indexOf('?');
    if (queryIndex >= 0) cleaned = cleaned.substring(0, queryIndex);
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: const Color(0xEE0A0A0C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primaryColor.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "KNOWLEDGE INGESTION",
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      backgroundColor: Colors.white10,
                    ),
                  ),
                  Icon(
                    Icons.psychology,
                    size: 36,
                    color: primaryColor,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.url,
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
