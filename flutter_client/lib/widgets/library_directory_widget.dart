import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../screens/note_viewer_screen.dart';

class LibraryDirectoryWidget extends StatefulWidget {
  const LibraryDirectoryWidget({super.key});

  @override
  State<LibraryDirectoryWidget> createState() => _LibraryDirectoryWidgetState();
}

class _LibraryDirectoryWidgetState extends State<LibraryDirectoryWidget> {
  final ApiService _apiService = ApiService();
  List<CategoryData> _categories = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMasterIndex();
  }

  Future<void> _loadMasterIndex() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final content = await _apiService.fetchNoteContent('_master-index.md');
      final parsed = _parseMasterIndex(content);
      setState(() {
        _categories = parsed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load directory: $e';
        _isLoading = false;
      });
    }
  }

  List<CategoryData> _parseMasterIndex(String content) {
    final List<CategoryData> list = [];
    final lines = content.split('\n');
    final categoryRegExp = RegExp(r'-\s*\*\*\[\[([^/|\]]+)/_index\|([^\]]+)\]\]\*\*(?::\s*(\d+)\s*articles)?');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final match = categoryRegExp.firstMatch(line);
      if (match != null) {
        final path = match.group(1)!;
        final name = match.group(2)!;
        final countStr = match.group(3);
        final count = countStr != null ? int.tryParse(countStr) ?? 0 : 0;
        
        // Peek at next line for description
        String description = "";
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.startsWith('*') && nextLine.endsWith('*')) {
            description = nextLine.substring(1, nextLine.length - 1);
          }
        }

        list.add(CategoryData(
          path: path,
          name: name,
          articleCount: count,
          description: description,
        ));
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadMasterIndex,
                icon: const Icon(Icons.refresh),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Text(
          'No folders in directory',
          style: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFF97316),
      onRefresh: _loadMasterIndex,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return CategoryExpansionTile(category: category, apiService: _apiService);
        },
      ),
    );
  }
}

class CategoryData {
  final String path;
  final String name;
  final int articleCount;
  final String description;

  CategoryData({
    required this.path,
    required this.name,
    required this.articleCount,
    required this.description,
  });
}

class CategoryExpansionTile extends StatefulWidget {
  final CategoryData category;
  final ApiService apiService;

  const CategoryExpansionTile({
    super.key,
    required this.category,
    required this.apiService,
  });

  @override
  State<CategoryExpansionTile> createState() => _CategoryExpansionTileState();
}

class _CategoryExpansionTileState extends State<CategoryExpansionTile> {
  List<NoteItem> _notes = [];
  bool _isLoadingNotes = false;
  bool _isLoaded = false;
  String? _error;

  Future<void> _loadCategoryNotes() async {
    if (_isLoaded || _isLoadingNotes) return;

    setState(() {
      _isLoadingNotes = true;
      _error = null;
    });

    try {
      final content = await widget.apiService.fetchNoteContent('${widget.category.path}/_index.md');
      final notes = _parseCategoryIndex(content);
      setState(() {
        _notes = notes;
        _isLoadingNotes = false;
        _isLoaded = true;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoadingNotes = false;
      });
    }
  }

  List<NoteItem> _parseCategoryIndex(String content) {
    final List<NoteItem> list = [];
    final lines = content.split('\n');
    final articleRegExp = RegExp(r'-\s*\[\[([^\]]+)\]\](?::\s*(.*))?');

    for (final line in lines) {
      final match = articleRegExp.firstMatch(line.trim());
      if (match != null) {
        final title = match.group(1)!;
        final description = match.group(2) ?? '';
        list.add(NoteItem(title: title, description: description));
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0),
        ),
      ),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded) {
            _loadCategoryNotes();
          }
        },
        leading: Icon(
          Icons.folder_special,
          color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.category.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (widget.category.articleCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C)).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${widget.category.articleCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                  ),
                ),
              ),
          ],
        ),
        subtitle: widget.category.description.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  widget.category.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white30 : Colors.black45,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : null,
        children: [
          if (_isLoadingNotes)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316)),
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            )
          else if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No articles in this category.',
                style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 12),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                final fileRelativePath = '${widget.category.path}/${note.title}.md';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                  leading: const Icon(Icons.article_outlined, size: 18, color: Colors.blueAccent),
                  title: Text(
                    note.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  subtitle: note.description.isNotEmpty
                      ? Text(
                          note.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white30 : Colors.black45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () async {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFF97316)),
                      ),
                    );

                    try {
                      final content = await widget.apiService.fetchNoteContent(fileRelativePath);
                      if (context.mounted) {
                        Navigator.pop(context); // Close loading dialog
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NoteViewerScreen(
                              title: note.title,
                              content: content,
                              fileName: fileRelativePath,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.pop(context); // Close loading dialog
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to load note: $e')),
                        );
                      }
                    }
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class NoteItem {
  final String title;
  final String description;

  NoteItem({required this.title, required this.description});
}
