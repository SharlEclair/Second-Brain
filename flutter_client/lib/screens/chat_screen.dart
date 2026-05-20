import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import '../services/widget_service.dart';
import '../screens/debug_logs_screen.dart';
import 'settings_screen.dart';
import 'notes_browser_screen.dart';
import 'audit_dashboard_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  static final ValueNotifier<String?> widgetActionNotifier = ValueNotifier<String?>(null);
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ApiService _apiService = ApiService();
  final QueueService _queueService = QueueService();
  late TabController _tabController;

  bool _isLoading = false;
  bool _isIngesting = false;
  int _queueCount = 0;
  List<String> _queuedUrls = [];
  Map<String, String> _queueErrors = {};
  bool _isProcessingQueue = false;
  String _currentStatus = "";
  Timer? _statusTimer;
  String? _statusFilterUrl;
  Timer? _rawCountTimer;
  int _rawCount = 0;
  bool _isCompiling = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {}); // Refresh for FAB visibility
    });
    _refreshQueue();
    _startRawCountPolling();
    ChatScreen.widgetActionNotifier.addListener(_handleWidgetNotifier);
  }

  @override
  void dispose() {
    ChatScreen.widgetActionNotifier.removeListener(_handleWidgetNotifier);
    _statusTimer?.cancel();
    _rawCountTimer?.cancel();
    _tabController.dispose();
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _refreshQueue() async {
    final queue = await _queueService.getQueue();
    if (mounted) {
      setState(() {
        _queuedUrls = queue;
        _queueCount = queue.length;
      });
    }
  }

  Future<void> _checkRawCount() async {
    try {
      final count = await _apiService.fetchRawCount();
      if (mounted && count != _rawCount) {
        setState(() {
          _rawCount = count;
        });
      }
    } catch (_) {}
  }

  void _startRawCountPolling() {
    _checkRawCount();
    _rawCountTimer?.cancel();
    _rawCountTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _checkRawCount();
      }
    });
  }

  Future<void> _runCompile() async {
    if (_isCompiling) return;
    setState(() {
      _isCompiling = true;
    });

    try {
      await _apiService.compileInbox();
      await _checkRawCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✓ Inbox compiled successfully! Notes sorted into folders."),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to compile: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCompiling = false;
        });
      }
    }
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

  void _startStatusPolling({String? url}) {
    _statusTimer?.cancel();
    _statusFilterUrl = url;
    if (mounted) {
      setState(() => _currentStatus = "STARTING...");
    }
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final status = await _apiService.getStatus();
        final activeTasks = status['active_tasks'];
        if (activeTasks is List && activeTasks.isNotEmpty) {
          Map? selectedTask;
          if (_statusFilterUrl != null) {
            final target = _canonicalUrl(_statusFilterUrl!);
            for (final task in activeTasks) {
              if (task is Map && _canonicalUrl((task['url'] ?? '').toString()) == target) {
                selectedTask = task;
                break;
              }
            }
          }
          selectedTask ??= activeTasks.last is Map ? activeTasks.last as Map : null;
          if (mounted && selectedTask != null) {
            final progress = selectedTask['progress'];
            final progressText = progress is num ? ' ${progress.round()}%' : '';
            setState(() {
              _currentStatus = '${(selectedTask!['status'] ?? '').toString().toUpperCase()}$progressText';
            });
          }
        }
      } catch (_) {
        // Silently ignore polling errors
      }
    });
  }

  void _stopStatusPolling() {
    _statusTimer?.cancel();
    _statusFilterUrl = null;
    if (mounted) {
      setState(() {
        _currentStatus = "";
      });
    }
  }

  // --- URL Ingestion ---

  void _ingestUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isIngesting = true);
    _startStatusPolling(url: url);

    try {
      final result = await _apiService.ingestUrl(url);
      // Update widgets on success
      WidgetService.syncAllWidgets(_apiService);
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
      await _queueService.addToQueue(url);
      await _refreshQueue();
      if (mounted) {
        _urlController.clear();
        String message = '📌 Queued';
        if (e is NetworkException) {
          message = '📌 Queued — will process when connected';
        } else if (e is ServerException) {
          message = '📌 Queued (Server error: ${e.message})';
        } else {
          message = '📌 Queued (error: ${e.toString().split("\n").first})';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFF97316),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isIngesting = false);
        _stopStatusPolling();
      }
    }
  }

  void _processQueue() async {
    if (_queueCount == 0) return;

    setState(() {
      _isProcessingQueue = true;
      _queueErrors = {};
    });
    _startStatusPolling();

    try {
      final result = await _queueService.processQueue(_apiService);
      await _refreshQueue();
      // Update widgets on success
      WidgetService.syncAllWidgets(_apiService);
      if (mounted) {
        setState(() {
          _queueErrors = result.errors;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Processed ${result.processed}/${result.total}${result.failed > 0 ? " · ${result.failed} failed" : ""}'),
            backgroundColor: result.failed == 0 ? const Color(0xFF22C55E) : const Color(0xFFF97316),
          ),
        );
      }
    } catch (e) {
      DebugLogger.log("Queue processing failed: $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessingQueue = false);
        _stopStatusPolling();
      }
    }
  }

  void _removeFromQueue(String url) async {
    await _queueService.removeFromQueue(url);
    await _refreshQueue();
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
              text: "Cannot connect. Check IP in Settings.\n\n${e.toString()}",
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
                  try {
                    await _apiService.saveAnswer(title, content);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Saved successfully")),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed: $e")),
                      );
                    }
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



  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CORTEX', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 3.0, fontSize: 16)),
        backgroundColor: const Color(0xFF111111),
        shape: const Border(bottom: BorderSide(color: Color(0xFF222222), width: 1)),
        actions: [
          if (_queueCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Badge(
                label: Text('$_queueCount'),
                backgroundColor: const Color(0xFFF97316),
                child: IconButton(
                  icon: const Icon(Icons.schedule, color: Colors.white70),
                  onPressed: () => _tabController.animateTo(1),
                  tooltip: "Queued links",
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined, color: Colors.white70),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AuditDashboardScreen()));
            },
            tooltip: "Vault Audit & Hygiene",
          ),
          IconButton(
            icon: const Icon(Icons.psychology_outlined, color: Colors.white70),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const NotesBrowserScreen()));
            },
            tooltip: "Brain Vault",
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF97316),
          labelColor: const Color(0xFFF97316),
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          tabs: [
            const Tab(text: "CHAT"),
            Tab(text: "QUEUE ($_queueCount)"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatTab(),
          _buildQueueTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 1 && _queueCount > 0
          ? FloatingActionButton.extended(
              onPressed: _isProcessingQueue ? null : _processQueue,
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.black,
              icon: _isProcessingQueue 
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.bolt),
              label: Text(_isProcessingQueue 
                ? (_currentStatus.isNotEmpty ? _currentStatus : "PROCESSING...") 
                : "PROCESS ALL", 
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            )
          : null,
    );
  }

  // ===== CHAT TAB =====
  Widget _buildChatTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // --- URL Input ---
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Paste URL to ingest...",
                    hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontFamily: 'monospace', fontSize: 13),
                    fillColor: isDark ? const Color(0xFF050505) : const Color(0xFFF1F5F9),
                    filled: true,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C), width: 1),
                    ),
                    prefixIcon: IconButton(
                      icon: Icon(Icons.content_paste, color: isDark ? Colors.white30 : Colors.black38, size: 18),
                      onPressed: _pasteFromClipboard,
                    ),
                  ),
                  onSubmitted: (_) => _ingestUrl(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: (_isIngesting || _isProcessingQueue) ? null : _ingestUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: _isIngesting
                    ? Text(_currentStatus.isNotEmpty ? _currentStatus : "INGESTING...", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1))
                    : const Text("INGEST", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),

        // --- Inbox Compile Badge & Button ---
        if (_rawCount > 0 || _isCompiling)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111111) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isDark ? const Color(0xFFE55B13) : const Color(0xFFEA580C)).withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFFE55B13) : const Color(0xFFEA580C)).withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inbox,
                  color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isCompiling ? "COMPILING INBOX..." : "PENDING CLIPPINGS IN INBOX",
                        style: TextStyle(
                          color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isCompiling 
                          ? "Classifying, merging and creating indexes..." 
                          : "$_rawCount raw note(s) awaiting processing.",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _isCompiling
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316)),
                    )
                  : ElevatedButton.icon(
                      onPressed: _runCompile,
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text("COMPILE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
              ],
            ),
          ),

        // --- Messages ---
        Expanded(
          child: _messages.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.psychology, size: 48, color: Colors.white.withOpacity(0.1)),
                    const SizedBox(height: 16),
                    Text("Ask your brain anything",
                      style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14, fontFamily: 'monospace')),
                    const SizedBox(height: 4),
                    Text("or paste a URL above to ingest",
                      style: TextStyle(color: Colors.white.withOpacity(0.1), fontSize: 12, fontFamily: 'monospace')),
                  ],
                ),
              )
            : ListView.builder(
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
                        child: Text(message.text, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15)),
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
                          color: isDark ? const Color(0xFF111111) : Colors.white,
                          border: Border.all(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: message.text,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, height: 1.5),
                                code: TextStyle(
                                  backgroundColor: isDark ? Colors.black38 : const Color(0xFFF1F5F9),
                                  color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF050505) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _saveToVault(message.text),
                                  icon: Icon(
                                    Icons.auto_awesome,
                                    size: 16,
                                    color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                                  ),
                                  label: Text(
                                    "PROMOTE TO WIKI",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: (isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C)).withOpacity(0.15),
                                    shadowColor: (isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C)).withOpacity(0.2),
                                    elevation: 0,
                                    side: BorderSide(
                                      color: (isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C)).withOpacity(0.5),
                                      width: 1,
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _saveToVault(message.text),
                                  icon: Icon(Icons.bookmark_add_outlined, size: 15, color: isDark ? Colors.white54 : Colors.black54),
                                  label: Text(
                                    "Save to Vault",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white54 : Colors.black54,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isDark ? Colors.white70 : Colors.black87,
                                    side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  ),
                                ),
                              ],
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
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316))),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Color(0xFF333333))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Color(0xFF222222))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: Color(0xFFF97316), width: 1)),
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
    );
  }

  // ===== QUEUE TAB =====
  Widget _buildQueueTab() {
    return Column(
      children: [
        // Process button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF0A0A0A),
            border: Border(bottom: BorderSide(color: Color(0xFF222222))),
          ),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_isProcessingQueue || _queueCount == 0) ? null : _processQueue,
                  icon: _isProcessingQueue
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.play_arrow),
                  label: Text(
                    _isProcessingQueue ? (_currentStatus.isNotEmpty ? _currentStatus : "PROCESSING...") : "PROCESS ALL ($_queueCount)",
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _queueCount > 0 ? const Color(0xFFF97316) : const Color(0xFF333333),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _queueCount == 0
                  ? "No pending links. Share or paste URLs and they'll queue here when offline."
                  : "These links will be processed when you tap the button above.",
                style: const TextStyle(color: Colors.white30, fontSize: 11, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // Queue list
        Expanded(
          child: _queuedUrls.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox, size: 48, color: Colors.white.withOpacity(0.08)),
                    const SizedBox(height: 16),
                    Text("Queue is empty", style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 14, fontFamily: 'monospace')),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        "Share Reels or links to Second Brain while you're away. They'll appear here for batch processing.",
                        style: TextStyle(color: Colors.white.withOpacity(0.1), fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _queuedUrls.length,
                itemBuilder: (context, index) {
                  final url = _queuedUrls[index];
                  // Determine platform icon
                  IconData platformIcon = Icons.link;
                  Color platformColor = Colors.white38;
                  if (url.contains('instagram.com')) {
                    platformIcon = Icons.camera_alt;
                    platformColor = const Color(0xFFE1306C);
                  } else if (url.contains('youtube.com') || url.contains('youtu.be')) {
                    platformIcon = Icons.play_circle;
                    platformColor = const Color(0xFFFF0000);
                  } else if (url.contains('tiktok.com')) {
                    platformIcon = Icons.music_note;
                    platformColor = Colors.white70;
                  }

                  return Dismissible(
                    key: Key(url),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red.withOpacity(0.2),
                      child: const Icon(Icons.delete, color: Colors.red, size: 20),
                    ),
                    onDismissed: (_) => _removeFromQueue(url),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: _queueErrors.containsKey(url) ? Colors.red.withOpacity(0.3) : const Color(0xFF222222)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(platformIcon, color: platformColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  url,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white24, size: 16),
                                onPressed: () => _removeFromQueue(url),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          if (_queueErrors.containsKey(url))
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 32),
                              child: Text(
                                _queueErrors[url]!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  void _sendDirectMessage(String text) async {
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });

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
              text: "Cannot connect. Check IP in Settings.\n\n${e.toString()}",
              isUser: false));
          _isLoading = false;
        });
      }
    }
  }

  void _handleWidgetNotifier() {
    final action = ChatScreen.widgetActionNotifier.value;
    if (action == 'action/voice' && mounted) {
      _showVoiceModeDialog();
    }
  }

  void _showVoiceModeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return _VoiceAssistantDialog(onSend: _sendDirectMessage);
      },
    );
  }
}

class _VoiceAssistantDialog extends StatefulWidget {
  final Function(String) onSend;
  const _VoiceAssistantDialog({required this.onSend});

  @override
  State<_VoiceAssistantDialog> createState() => _VoiceAssistantDialogState();
}

class _VoiceAssistantDialogState extends State<_VoiceAssistantDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final TextEditingController _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F0F0F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
        side: const BorderSide(color: Color(0xFF222222), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "🎙️ CORTEX VOICE ASSISTANT",
              style: TextStyle(
                color: Color(0xFFF97316),
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            // Pulsing Mic Icon
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFF97316).withOpacity(0.4), width: 2),
                ),
                child: const Icon(
                  Icons.mic,
                  size: 40,
                  color: Color(0xFFF97316),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Listening...",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Use the keyboard mic to dictate, or type directly.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 20),
            // Autofocused input field to bring up keyboard instantly
            TextField(
              controller: _inputController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Speak or type your query...",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF050505),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF222222)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFF97316)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final text = _inputController.text.trim();
                    if (text.isNotEmpty) {
                      widget.onSend(text);
                    }
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Ask Cortex", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
