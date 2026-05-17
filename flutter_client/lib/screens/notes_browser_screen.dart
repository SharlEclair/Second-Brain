import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'note_viewer_screen.dart';

class NotesBrowserScreen extends StatefulWidget {
  const NotesBrowserScreen({super.key});

  @override
  State<NotesBrowserScreen> createState() => _NotesBrowserScreenState();
}

class _NotesBrowserScreenState extends State<NotesBrowserScreen> {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final TextEditingController _searchController = TextEditingController();
  
  List<FileSystemEntity> _localNotes = [];
  List<FileSystemEntity> _filteredNotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _searchController.addListener(_filterNotes);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    final notes = await _storageService.listLocalNotes();
    setState(() {
      _localNotes = notes;
      _filteredNotes = notes;
      _isLoading = false;
    });
  }

  void _filterNotes() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredNotes = _localNotes.where((note) {
        final fileName = note.path.split('/').last.toLowerCase();
        return fileName.contains(query);
      }).toList();
    });
  }

  Future<void> _syncWithServer() async {
    setState(() => _isLoading = true);
    try {
      final remoteNotes = await _apiService.fetchNotes();
      for (final note in remoteNotes) {
        final fileName = note['fileName'];
        if (fileName != null) {
          final content = await _apiService.fetchNoteContent(fileName);
          await _storageService.saveNote(fileName, content);
        }
      }
      await _loadNotes();
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
      setState(() => _isLoading = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('BRAIN VAULT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 14)),
        backgroundColor: const Color(0xFF111111),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 20),
            onPressed: _isLoading ? null : _syncWithServer,
            tooltip: "Sync with server",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search your knowledge...",
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 18),
                fillColor: const Color(0xFF111111),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316)))
              : _filteredNotes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open, size: 48, color: Colors.white10),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty ? "No notes saved locally" : "No matching notes found",
                          style: const TextStyle(color: Colors.white24),
                        ),
                        if (_searchController.text.isEmpty) ...[
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _syncWithServer,
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text("SYNC FROM SERVER"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF97316),
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ]
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredNotes.length,
                    itemBuilder: (context, index) {
                      final note = _filteredNotes[index];
                      final fileName = note.path.split('/').last;
                      final title = _formatTitle(fileName);
                      
                      return Card(
                        color: const Color(0xFF111111),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF222222)),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined, color: Color(0xFFF97316)),
                          title: Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                          ),
                          subtitle: Text(
                            fileName,
                            style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
                          ),
                          onTap: () async {
                            final content = await _storageService.readNote(fileName);
                            if (content != null && context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NoteViewerScreen(
                                    title: title,
                                    content: content,
                                    fileName: fileName,
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
      ),
    );
  }
}
