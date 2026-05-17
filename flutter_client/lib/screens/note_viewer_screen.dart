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
    return Scaffold(
      appBar: AppBar(
        title: Text(title.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: const Color(0xFF111111),
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
          h1: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.5),
          h2: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
          h3: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          p: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6),
          code: const TextStyle(backgroundColor: Color(0xFF1A1A1A), fontFamily: 'monospace', color: Color(0xFFF97316)),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF222222)),
          ),
          blockquote: const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
          blockquoteDecoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFFF97316), width: 4)),
          ),
          listBullet: const TextStyle(color: Color(0xFFF97316)),
        ),
      ),
    );
  }
}
