import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/analytics_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../models/isar_note.dart';
import '../widgets/events_carousel.dart';
import '../widgets/library_directory_widget.dart';
import 'note_viewer_screen.dart';
import 'nearby_map_screen.dart';

class NotesBrowserScreen extends StatefulWidget {
  final bool focusSearch;
  const NotesBrowserScreen({super.key, this.focusSearch = false});

  @override
  State<NotesBrowserScreen> createState() => _NotesBrowserScreenState();
}

class _NotesBrowserScreenState extends State<NotesBrowserScreen> {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<FileSystemEntity> _localNotes = [];
  List<FileSystemEntity> _filteredNotes = [];
  List<IsarNote> _isarNotes = [];
  List<IsarNote> _filteredIsarNotes = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _loadUpcomingEvents();
    _searchController.addListener(_filterNotes);
    
    if (widget.focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final cached = await SyncService().getCachedNotes();
      setState(() {
        _isarNotes = cached;
        _filteredIsarNotes = cached;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to load notes from Isar: $e");
      final notes = await _storageService.listLocalNotes();
      setState(() {
        _localNotes = notes;
        _filteredNotes = notes;
        _isLoading = false;
      });
    }
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

  void _filterNotes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (_isarNotes.isNotEmpty) {
        _filteredIsarNotes = _isarNotes.where((note) {
          return note.title.toLowerCase().contains(query) || note.content.toLowerCase().contains(query);
        }).toList();
      } else {
        _filteredNotes = _localNotes.where((note) {
          final fileName = note.path.split('/').last.toLowerCase();
          return fileName.contains(query);
        }).toList();
      }
    });
    if (query.trim().isNotEmpty) {
      AnalyticsService().logSearch(query.trim());
    }
  }

  Future<void> _syncWithServer() async {
    setState(() => _isLoading = true);
    try {
      // Sync Down to Isar Database first
      await SyncService().syncDown();

      final prefs = await SharedPreferences.getInstance();
      final String syncMetaRaw = prefs.getString('sync_metadata') ?? '{}';
      final Map<String, dynamic> syncMeta = jsonDecode(syncMetaRaw);

      final remoteNotes = await _apiService.fetchNotes();
      bool modified = false;

      for (final note in remoteNotes) {
        final fileName = note['fileName'];
        final date = note['date'] ?? '';
        if (fileName != null) {
          final exists = await _storageService.noteExists(fileName);
          final cachedDate = syncMeta[fileName];
          
          if (!exists || cachedDate != date) {
            try {
              final content = await _apiService.fetchNoteContent(fileName);
              await _storageService.saveNote(fileName, content);
              syncMeta[fileName] = date;
              modified = true;
            } catch (e) {
              debugPrint("Failed to sync note $fileName: $e");
            }
          }
        }
      }

      if (modified) {
        await prefs.setString('sync_metadata', jsonEncode(syncMeta));
      }

      await _loadNotes();
      await _loadUpcomingEvents();
      try {
        await NotificationService.syncScheduledReminders(_apiService);
      } catch (e) {
        debugPrint("Error syncing task reminders: $e");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync complete. Local vault updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatTitle(String fileName) {
    // Remove .md and replace dashes/underscores with spaces
    return fileName
        .replaceAll('.md', '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BRAIN VAULT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 14)),
          backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            tabs: const [
              Tab(text: "LOCAL NOTES"),
              Tab(text: "LIBRARY TREE"),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.sync, size: 20),
              onPressed: _isLoading ? null : _syncWithServer,
              tooltip: "Sync with server",
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NearbyMapScreen()),
            );
          },
          backgroundColor: Theme.of(context).colorScheme.primary,
          tooltip: 'Find Nearby',
          child: const Icon(Icons.location_on),
        ),
        body: TabBarView(
          children: [
            _buildLocalVaultTab(isDark),
            const LibraryDirectoryWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalVaultTab(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Search your knowledge...",
              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
              prefixIcon: Icon(Icons.search, color: isDark ? Colors.white24 : Colors.black38, size: 18),
              fillColor: isDark ? const Color(0xFF111111) : const Color(0xFFF1F5F9),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        if (_upcomingEvents.isNotEmpty)
          EventsAgendaView(
            events: _upcomingEvents,
            shrinkWrap: true,
            onEventTap: (fileName, title) async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              setState(() => _isLoading = true);
              try {
                var content = await _storageService.readNote(fileName);
                if (content == null) {
                  content = await _apiService.fetchNoteContent(fileName);
                  await _storageService.saveNote(fileName, content);
                }
                
                if (!mounted) return;
                AnalyticsService().logRead(title);
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => NoteViewerScreen(
                      title: title,
                      content: content!,
                      fileName: fileName,
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Failed to load note: $e')),
                );
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
          ),
        Expanded(
          child: _isLoading 
            ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
            : (_isarNotes.isNotEmpty ? _filteredIsarNotes.isEmpty : _filteredNotes.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 48, color: isDark ? Colors.white10 : Colors.black12),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isEmpty ? "No notes saved locally" : "No matching notes found",
                        style: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
                      ),
                      if (_searchController.text.isEmpty) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _syncWithServer,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text("SYNC FROM SERVER"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ]
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _isarNotes.isNotEmpty ? _filteredIsarNotes.length : _filteredNotes.length,
                  itemBuilder: (context, index) {
                    final isarActive = _isarNotes.isNotEmpty;
                    final noteTitle = isarActive ? _filteredIsarNotes[index].title : _formatTitle(_filteredNotes[index].path.split('/').last);
                    final noteFileName = isarActive ? _filteredIsarNotes[index].fileName : _filteredNotes[index].path.split('/').last;
                    
                    return Card(
                      color: isDark ? const Color(0xFF111111) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.description_outlined, color: Theme.of(context).colorScheme.primary),
                        title: Text(
                          noteTitle,
                          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.w500, fontSize: 14),
                        ),
                        subtitle: Text(
                          noteFileName,
                          style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 10, fontFamily: 'monospace'),
                        ),
                        onTap: () async {
                          final content = isarActive 
                              ? _filteredIsarNotes[index].content 
                              : await _storageService.readNote(noteFileName);
                          if (content != null && context.mounted) {
                            AnalyticsService().logRead(noteTitle);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NoteViewerScreen(
                                  title: noteTitle,
                                  content: content,
                                  fileName: noteFileName,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
