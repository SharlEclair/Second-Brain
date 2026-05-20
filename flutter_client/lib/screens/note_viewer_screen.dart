import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

class NoteViewerScreen extends StatelessWidget {
  final String title;
  final String content;
  final String fileName;

  const NoteViewerScreen({
    super.key,
    required this.title,
    required this.content,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(title.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: () {
              Share.share(content, subject: title);
            },
          ),
        ],
      ),
      body: Markdown(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          h1: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold, height: 1.5),
          h2: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
          h3: TextStyle(color: isDark ? Colors.white : const Color(0xFF334155), fontSize: 18, fontWeight: FontWeight.bold),
          p: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF334155), fontSize: 15, height: 1.6),
          code: TextStyle(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF1F5F9), 
            fontFamily: 'monospace', 
            color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C)
          ),
          codeblockDecoration: BoxDecoration(
            color: isDark ? const Color(0xFF111111) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
          ),
          blockquote: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontStyle: FontStyle.italic),
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C), width: 4)),
          ),
          listBullet: TextStyle(color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C)),
        ),
      ),
    );
  }
}
