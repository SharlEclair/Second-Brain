import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'share_service.dart';

class ClipboardService {
  static String? _lastCheckedClipboardUrl;

  static Future<void> checkClipboardForIngest(BuildContext context) async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!.trim();
        final urlPattern = RegExp(
          r'^(https?:\/\/[^\s$.?#].[^\s]*)$',
          caseSensitive: false,
        );
        if (urlPattern.hasMatch(text)) {
          if (text != _lastCheckedClipboardUrl) {
            _lastCheckedClipboardUrl = text;
            _showClipboardIngestSheet(context, text);
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking clipboard: $e");
    }
  }

  static void _showClipboardIngestSheet(BuildContext context, String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xE61E1E2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.link, color: Colors.blueAccent),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Link Detected in Clipboard",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        "Dismiss",
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ShareService.ingestSharedText(url);
                      },
                      child: const Text("Ingest Link"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
