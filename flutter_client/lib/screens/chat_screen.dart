import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../providers/ui_state_provider.dart';
import '../services/widget_service.dart';
import '../screens/debug_logs_screen.dart';
import '../services/debug_logger.dart';
import 'settings_screen.dart';
import 'notes_browser_screen.dart';
import 'audit_dashboard_screen.dart';
import 'note_viewer_screen.dart';
import 'quick_ask_screen.dart';
import 'scanner_screen.dart';
import '../services/storage_service.dart';
import '../widgets/brain_dump_button.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import '../services/audio_ingest_service.dart';
import '../widgets/events_carousel.dart';
import '../widgets/library_directory_widget.dart';
import '../widgets/command_palette_overlay.dart';
import '../services/haptic_feedback_manager.dart';

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends ConsumerStatefulWidget {
  static final ValueNotifier<String?> widgetActionNotifier = ValueNotifier<String?>(null);
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final List<ChatMessage> _messages = [];
  late final ApiService _apiService;
  late final QueueService _queueService;
  int _selectedIndex = 1; // 0: Calendar, 1: Efforts, 2: Atlas
  bool _isSpeedDialOpen = false;
  bool _isBrainDumping = false;

  bool _isLoading = false;
  bool _isIngesting = false;
  int _queueCount = 0;
  List<QueueItem> _queuedUrls = [];
  Map<String, String> _queueErrors = {};
  bool _isProcessingQueue = false;
  String _currentStatus = "";
  Timer? _statusTimer;
  String? _statusFilterUrl;
  Timer? _rawCountTimer;
  int _rawCount = 0;
  bool _isCompiling = false;
  List<Map<String, dynamic>> _upcomingEvents = [];
  StateSetter? _queueBottomSheetStateSetter;

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
      _queueBottomSheetStateSetter?.call(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _apiService = ref.read(apiServiceProvider);
    _queueService = ref.read(queueServiceProvider);
    _refreshQueue();
    _startRawCountPolling();
    _loadUpcomingEvents();
    ChatScreen.widgetActionNotifier.addListener(_handleWidgetNotifier);
  }

  @override
  void dispose() {
    ChatScreen.widgetActionNotifier.removeListener(_handleWidgetNotifier);
    _statusTimer?.cancel();
    _rawCountTimer?.cancel();
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

  Future<void> _loadUpcomingEvents() async {
    try {
      final events = await _apiService.fetchUpcomingEvents();
      if (mounted) {
        setState(() {
          _upcomingEvents = events;
        });
      }
    } catch (_) {
      // Best-effort load
    }
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

  Future<void> _scanDocument() async {
    try {
      final List<String>? pictures = await CunningDocumentScanner.getPictures();
      if (pictures == null || pictures.isEmpty) return;
      if (!mounted) return;

      setState(() => _isIngesting = true);
      _startStatusPolling();

      int successCount = 0;
      for (final path in pictures) {
        final success = await AudioIngestService.uploadAudio(path);
        if (success) {
          successCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanned and uploaded $successCount/${pictures.length} document page(s).'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      DebugLogger.log('Scanning failed: $e', type: 'ERROR');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan error: $e'),
            backgroundColor: const Color(0xFFEF4444),
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

  // --- URL Ingestion ---

  void _ingestUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final queueItem = QueueItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'url',
      payload: url,
    );
    await _queueService.addToQueue(queueItem);
    await _refreshQueue();

    setState(() => _isIngesting = true);
    _startStatusPolling(url: url);
    ref.read(uiStateProvider.notifier).setProcessing();

    try {
      await WidgetService.startIngestionLiveActivity(url);
      await WidgetService.updateIngestionLiveActivity(url, 'Parsing URL...', 0.3);
      final result = await _apiService.ingestUrl(url);
      await WidgetService.updateIngestionLiveActivity(url, 'Saving to Vault...', 0.8);
      // Update widgets on success
      WidgetService.syncAllWidgets(_apiService);
      await WidgetService.endIngestionLiveActivity(url, isSuccess: true);
      
      // Verified success - remove from local queue
      await _queueService.removeFromQueue(queueItem.id);
      await _refreshQueue();

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
      ref.read(uiStateProvider.notifier).setIdle();
    } catch (e) {
      ref.read(uiStateProvider.notifier).setError();
      Future.delayed(const Duration(seconds: 3), () {
        ref.read(uiStateProvider.notifier).setIdle();
      });

      // Kept in queue on error
      if (e is NetworkException) {
        await WidgetService.endIngestionLiveActivity(url, isSuccess: false, error: 'Queued (Offline)');
      } else if (e is ServerException) {
        await WidgetService.endIngestionLiveActivity(url, isSuccess: false, error: 'Queued (Server error)');
      } else {
        await WidgetService.endIngestionLiveActivity(url, isSuccess: false, error: 'Queued');
      }
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
            backgroundColor: Theme.of(context).colorScheme.primary,
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
    ref.read(uiStateProvider.notifier).setProcessing();

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
            backgroundColor: result.failed == 0 ? const Color(0xFF22C55E) : Theme.of(context).colorScheme.primary,
          ),
        );
      }
      if (result.failed > 0) {
        ref.read(uiStateProvider.notifier).setError();
        Future.delayed(const Duration(seconds: 3), () {
          ref.read(uiStateProvider.notifier).setIdle();
        });
      } else {
        ref.read(uiStateProvider.notifier).setIdle();
      }
    } catch (e) {
      DebugLogger.log("Queue processing failed: $e");
      ref.read(uiStateProvider.notifier).setError();
      Future.delayed(const Duration(seconds: 3), () {
        ref.read(uiStateProvider.notifier).setIdle();
      });
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
    if (!mounted) return;
    if (data?.text != null && data!.text!.isNotEmpty) {
      _urlController.text = data.text!;
    }
  }

  void _showCommandPalette() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "CommandPalette",
      barrierColor: Colors.black.withOpacity(0.40),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const CommandPaletteOverlay(),
    );
  }

  // --- Chat ---

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    HapticFeedbackManager.mediumImpact();

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) {
          final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
          if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyP) {
            _showCommandPalette();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.slash) {
            if (_textController.text.isEmpty) {
              _showCommandPalette();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.schedule, color: Colors.white70),
                    onPressed: _showQueueBottomSheet,
                    tooltip: "Queued links",
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white70),
              onPressed: _showCommandPalette,
              tooltip: "Command Palette",
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white70),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
              },
            )
          ],
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildCalendarTab(),
            _buildEffortsTab(),
            _buildAtlasTab(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(0xFF111111),
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.white38,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Calendar'),
            BottomNavigationBarItem(icon: Icon(Icons.bolt), label: 'Efforts'),
            BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Atlas'),
          ],
        ),
        floatingActionButton: _isBrainDumping
            ? BrainDumpButton(
                onComplete: () {
                  setState(() {
                    _isBrainDumping = false;
                  });
                },
              )
            : _buildSpeedDial(isDark),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildCalendarTab() {
    if (_upcomingEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 48, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              "No upcoming events",
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }
    return EventsAgendaView(
      events: _upcomingEvents,
      onEventTap: (fileName, title) async {
        setState(() => _isLoading = true);
        try {
          final storage = StorageService();
          var content = await storage.readNote(fileName);
          if (content == null) {
            content = await _apiService.fetchNoteContent(fileName);
            await storage.saveNote(fileName, content);
          }
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoteViewerScreen(
                  title: title,
                  content: content!,
                  fileName: fileName,
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to load note: $e')),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      },
    );
  }

  Widget _buildAtlasTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotesBrowserScreen()),
                    );
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text("BROWSE NOTES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
                    foregroundColor: isDark ? Colors.white : Colors.black,
                    side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AuditDashboardScreen()),
                    );
                  },
                  icon: const Icon(Icons.analytics, size: 18),
                  label: const Text("AUDIT VAULT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
                    foregroundColor: isDark ? Colors.white : Colors.black,
                    side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF222222), height: 1),
        const Expanded(
          child: LibraryDirectoryWidget(),
        ),
      ],
    );
  }

  Widget _buildSpeedDial(bool isDark) {
    if (!_isSpeedDialOpen) {
      return FloatingActionButton(
        onPressed: () {
          setState(() {
            _isSpeedDialOpen = true;
          });
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.black),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.small(
          heroTag: "fab1",
          backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
          onPressed: () {
            setState(() {
              _isSpeedDialOpen = false;
              _isBrainDumping = true;
            });
          },
          child: Icon(Icons.mic, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: "fab2",
          backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
          onPressed: () {
            setState(() { _isSpeedDialOpen = false; });
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ScannerScreen()));
          },
          child: Icon(Icons.document_scanner, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: "fab3",
          backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
          onPressed: () {
            setState(() { _isSpeedDialOpen = false; });
            Navigator.push(context, MaterialPageRoute(builder: (context) => const QuickAskScreen()));
          },
          child: Icon(Icons.text_fields, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: "fab_main",
          onPressed: () {
            setState(() {
              _isSpeedDialOpen = false;
            });
          },
          backgroundColor: const Color(0xFF111111),
          child: const Icon(Icons.close, color: Colors.white),
        ),
      ],
    );
  }

  // ===== EFFORTS TAB =====
  Widget _buildEffortsTab() {
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
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1),
                    ),
                    prefixIcon: IconButton(
                      icon: Icon(Icons.content_paste, color: isDark ? Colors.white30 : Colors.black38, size: 18),
                      onPressed: _pasteFromClipboard,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.document_scanner_outlined, color: isDark ? Colors.white30 : Colors.black38, size: 18),
                      onPressed: _scanDocument,
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
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
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inbox,
                  color: Theme.of(context).colorScheme.primary,
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
                          color: Theme.of(context).colorScheme.primary,
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
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                    )
                  : ElevatedButton.icon(
                      onPressed: _runCompile,
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text("COMPILE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
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
                                  color: Theme.of(context).colorScheme.primary,
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
                                    color: Theme.of(context).colorScheme.primary,
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
                                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                    shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                    elevation: 0,
                                    side: BorderSide(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
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
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 12),
                Text("Querying Vault...", style: TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),

        // --- Chat Input ---
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: "ASK YOUR BRAIN...",
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3), fontFamily: 'monospace', fontSize: 14),
                    fillColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF0F0F2),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16.0), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
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

  void _showQueueBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _queueBottomSheetStateSetter = setModalState;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111111) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "QUEUED LINKS",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              fontSize: 13,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF222222), height: 1),
                    // Process button
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8FAFC),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: (_isProcessingQueue || _queueCount == 0) ? null : _processQueue,
                              icon: _isProcessingQueue
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                              label: Text(
                                _isProcessingQueue
                                  ? (_currentStatus.isNotEmpty ? _currentStatus : "PROCESSING...")
                                  : "PROCESS ALL ($_queueCount)",
                                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _queueCount > 0
                                  ? Theme.of(context).colorScheme.primary
                                  : (isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                                foregroundColor: isDark ? Colors.black : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _queueCount == 0
                              ? "No pending links. Share or paste URLs and they'll queue here when offline."
                              : "These links will be processed when you tap the button above.",
                            style: TextStyle(
                              color: isDark ? Colors.white30 : Colors.black38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    // Queue list
                    Flexible(
                      child: _queuedUrls.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(40.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox, size: 48, color: isDark ? Colors.white10 : Colors.black12),
                                const SizedBox(height: 16),
                                Text(
                                  "Queue is empty",
                                  style: TextStyle(
                                    color: isDark ? Colors.white24 : Colors.black38,
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _queuedUrls.length,
                              itemBuilder: (context, index) {
                                final item = _queuedUrls[index];
                                final displayName = item.title ?? item.payload;
                                IconData platformIcon = Icons.link;
                                Color platformColor = isDark ? Colors.white38 : Colors.black38;
                                
                                if (item.type == 'url') {
                                  if (item.payload.contains('instagram.com')) {
                                    platformIcon = Icons.camera_alt;
                                    platformColor = const Color(0xFFE1306C);
                                  } else if (item.payload.contains('youtube.com') || item.payload.contains('youtu.be')) {
                                    platformIcon = Icons.play_circle;
                                    platformColor = const Color(0xFFFF0000);
                                  } else if (item.payload.contains('tiktok.com')) {
                                    platformIcon = Icons.music_note;
                                    platformColor = isDark ? Colors.white70 : Colors.black54;
                                  }
                                } else if (item.type == 'text') {
                                  platformIcon = Icons.note_alt;
                                  platformColor = Colors.blueAccent;
                                } else if (item.type == 'file') {
                                  platformIcon = Icons.file_present;
                                  platformColor = Colors.orangeAccent;
                                }

                                return Dismissible(
                                  key: Key(item.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    color: Colors.red.withOpacity(0.2),
                                    child: const Icon(Icons.delete, color: Colors.red, size: 20),
                                  ),
                                  onDismissed: (_) => _removeFromQueue(item.id),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF1F5F9),
                                      border: Border.all(
                                        color: _queueErrors.containsKey(item.payload)
                                          ? Colors.red.withOpacity(0.3)
                                          : (isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                                      ),
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
                                                displayName,
                                                style: TextStyle(
                                                  color: isDark ? Colors.white70 : Colors.black87,
                                                  fontSize: 12,
                                                  fontFamily: 'monospace',
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.close, color: isDark ? Colors.white24 : Colors.black26, size: 16),
                                              onPressed: () => _removeFromQueue(item.id),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                        if (_queueErrors.containsKey(item.payload))
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8, left: 32),
                                            child: Text(
                                              _queueErrors[item.payload]!,
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
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _queueBottomSheetStateSetter = null;
    });
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
            Text(
              "🎙️ CORTEX VOICE ASSISTANT",
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
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
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), width: 2),
                ),
                child: Icon(
                  Icons.mic,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
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
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
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
