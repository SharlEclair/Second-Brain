import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import 'settings_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ApiService _apiService = ApiService();
  final QueueService _queueService = QueueService();
  bool _isLoading = false;
  bool _isIngesting = false;
  int _queueCount = 0;
  bool _isProcessingQueue = false;
  String? _ingestStatus;

  @override
  void initState() {
    super.initState();
    _refreshQueueCount();
  }

  Future<void> _refreshQueueCount() async {
    final queue = await _queueService.getQueue();
    if (mounted) {
      setState(() => _queueCount = queue.length);
    }
  }

  // --- URL Ingestion ---

  void _ingestUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isIngesting = true;
      _ingestStatus = 'Connecting...';
    });

    try {
      final result = await _apiService.ingestUrl(url);
      if (mounted) {
        _urlController.clear();
        final status = result['status'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'existing' 
              ? '✓ Already in your Brain Vault' 
              : '✓ Successfully ingested!'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      // Network error — queue it for later
      await _queueService.addToQueue(url);
      await _refreshQueueCount();
      if (mounted) {
        _urlController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📌 Queued for later — will process when connected'),
            backgroundColor: Color(0xFFF97316),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isIngesting = false;
          _ingestStatus = null;
        });
      }
    }
  }

  void _processQueue() async {
    if (_queueCount == 0) return;
    
    setState(() => _isProcessingQueue = true);

    final result = await _queueService.processQueue(_apiService);
    await _refreshQueueCount();

    if (mounted) {
      setState(() => _isProcessingQueue = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Processed ${result.processed}/${result.total} links${result.failed > 0 ? " (${result.failed} failed, will retry)" : ""}'),
          backgroundColor: result.failed == 0 ? const Color(0xFF22C55E) : const Color(0xFFF97316),
        ),
      );
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _urlController.text = data.text!;
    }
  }

  // --- Chat ---

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _textController.clear();

    try {
      final answer = await _apiService.ask(text);
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: answer, isUser: false));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
              text: "Cannot connect to local server. Check IP address in Settings. \n\n${e.toString()}",
              isUser: false));
          _isLoading = false;
        });
      }
    }
  }

  void _saveToVault(String content) {
    String title = "";
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: const Text("Save to Vault"),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter note title",
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: const Color(0xFF050505),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: Color(0xFF333333)),
              ),
            ),
            onChanged: (val) => title = val,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                if (title.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Saving to vault...")),
                  );
                  try {
                    await _apiService.saveAnswer(title, content);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Saved successfully")),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to save: $e")),
                    );
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CORTEX_AI', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 16)),
        backgroundColor: const Color(0xFF111111),
        shape: const Border(bottom: BorderSide(color: Color(0xFF222222), width: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          )
        ],
      ),
      body: Column(
        children: [
          // --- URL Ingestion Bar ---
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              border: Border(bottom: BorderSide(color: Color(0xFF222222))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Paste URL to ingest...",
                          hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'monospace', fontSize: 13),
                          fillColor: const Color(0xFF050505),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Color(0xFF333333)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Color(0xFF222222)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(color: Color(0xFFF97316), width: 1),
                          ),
                          prefixIcon: IconButton(
                            icon: const Icon(Icons.content_paste, color: Colors.white30, size: 18),
                            onPressed: _pasteFromClipboard,
                            tooltip: "Paste from clipboard",
                          ),
                          suffixIcon: _isIngesting
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316))),
                              )
                            : IconButton(
                                icon: const Icon(Icons.send, color: Color(0xFFF97316), size: 20),
                                onPressed: _ingestUrl,
                                tooltip: "Ingest URL",
                              ),
                        ),
                        onSubmitted: (_) => _ingestUrl(),
                      ),
                    ),
                  ],
                ),
                // --- Queue Status Bar ---
                if (_queueCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, color: Color(0xFFF97316), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '$_queueCount link${_queueCount == 1 ? '' : 's'} queued',
                          style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
                        ),
                        const Spacer(),
                        _isProcessingQueue
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316)))
                          : GestureDetector(
                              onTap: _processQueue,
                              child: const Text(
                                'PROCESS NOW',
                                style: TextStyle(color: Color(0xFFF97316), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                              ),
                            ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // --- Chat Messages ---
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                if (message.isUser) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      padding: const EdgeInsets.all(12.0),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Text(
                        message.text,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  );
                } else {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      padding: const EdgeInsets.all(16.0),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: const Color(0xFF222222)),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarkdownBody(
                            data: message.text,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                              code: const TextStyle(backgroundColor: Colors.black38, color: Color(0xFFF97316)),
                              codeblockDecoration: BoxDecoration(
                                color: const Color(0xFF050505),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: const Color(0xFF222222)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _saveToVault(message.text),
                            icon: const Icon(Icons.bookmark_add, size: 16),
                            label: const Text("Save to Vault", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.primary,
                              side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 16, height: 16, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316))
                  ),
                  const SizedBox(width: 12),
                  Text("Querying Vault...", style: TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),

          // --- Chat Input ---
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              border: Border(top: BorderSide(color: Color(0xFF222222))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "ASK YOUR BRAIN...",
                      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'monospace', fontSize: 14),
                      fillColor: const Color(0xFF050505),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Color(0xFF333333)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Color(0xFF222222)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Color(0xFFF97316), width: 1),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  elevation: 0,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.send, color: Colors.black),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
