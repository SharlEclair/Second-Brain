import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/haptic_feedback_manager.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../models/isar_note.dart';
import '../screens/scanner_screen.dart';
import '../screens/scratchpad_screen.dart';
import '../screens/nearby_map_screen.dart';
import '../screens/quick_ask_screen.dart';
import '../screens/note_viewer_screen.dart';
import '../screens/chat_screen.dart';
import '../theme/design_tokens.dart';

class CommandPaletteOverlay extends StatefulWidget {
  const CommandPaletteOverlay({super.key});

  @override
  State<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends State<CommandPaletteOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SyncService _syncService = SyncService();
  final ApiService _apiService = ApiService();

  List<IsarNote> _allNotes = [];
  List<CommandItem> _commands = [];
  List<CommandItem> _filteredCommands = [];
  List<String> _allTags = [];
  List<String> _filteredTags = [];
  List<IsarNote> _filteredNotes = [];
  bool _isLoadingNotes = true;

  int _selectedIndex = 0;
  List<SelectableItem> _selectableItems = [];

  @override
  void initState() {
    super.initState();
    _setupCommands();
    _loadNotesAndTags();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _updateSelectables() {
    final List<SelectableItem> items = [];
    
    for (final cmd in _filteredCommands) {
      items.add(CommandSelectable(cmd));
    }
    
    for (final tag in _filteredTags) {
      items.add(TagSelectable(tag, () {
        _searchController.text = tag;
        _searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: tag.length),
        );
      }));
    }
    
    for (final note in _filteredNotes) {
      items.add(NoteSelectable(note, _openNote));
    }
    
    _selectableItems = items;
    if (_selectedIndex >= _selectableItems.length) {
      _selectedIndex = _selectableItems.isNotEmpty ? _selectableItems.length - 1 : 0;
    }
  }

  void _navigateDown() {
    if (_selectableItems.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + 1) % _selectableItems.length;
    });
  }

  void _navigateUp() {
    if (_selectableItems.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex - 1 + _selectableItems.length) % _selectableItems.length;
    });
  }

  void _triggerSelected() {
    if (_selectableItems.isEmpty) return;
    if (_selectedIndex >= 0 && _selectedIndex < _selectableItems.length) {
      _selectableItems[_selectedIndex].trigger(context);
    }
  }

  void _setupCommands() {
    _commands = [
      CommandItem(
        command: '/scan',
        title: 'Scan Document',
        subtitle: 'Capture receipt, recipe, or handwritten notes using scanner',
        icon: Icons.document_scanner_outlined,
        action: (context) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScannerScreen()),
          );
        },
      ),
      CommandItem(
        command: '/voice',
        title: 'Voice Assistant',
        subtitle: 'Start voice capture / talk to your second brain',
        icon: Icons.mic_none_outlined,
        action: (context) {
          Navigator.pop(context);
          ChatScreen.widgetActionNotifier.value = 'action/voice';
          // Reset notifier value immediately
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ChatScreen.widgetActionNotifier.value = null;
          });
        },
      ),
      CommandItem(
        command: '/scratchpad',
        title: 'Quick Scratchpad',
        subtitle: 'Open a distraction-free screen to quickly dump text',
        icon: Icons.edit_note_outlined,
        action: (context) {
          Navigator.pop(context);
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const ScratchpadScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = Offset(0.0, 1.0);
                const end = Offset.zero;
                const curve = Curves.easeInOutCubic;
                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                return SlideTransition(
                  position: animation.drive(tween),
                  child: child,
                );
              },
            ),
          );
        },
      ),
      CommandItem(
        command: '/map',
        title: 'Nearby Spots Map',
        subtitle: 'Explore spots to visit and events near your current location',
        icon: Icons.map_outlined,
        action: (context) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NearbyMapScreen()),
          );
        },
      ),
      CommandItem(
        command: '/ask',
        title: 'Quick Ask Dialog',
        subtitle: 'Ask Cortex a quick question over blurred overlay',
        icon: Icons.help_outline,
        action: (context) {
          Navigator.pop(context);
          Navigator.push(
            context,
            PageRouteBuilder(
              opaque: false,
              barrierColor: Colors.black.withOpacity(0.6),
              pageBuilder: (context, _, __) => const QuickAskScreen(),
            ),
          );
        },
      ),
    ];
    _filteredCommands = List.from(_commands);
    _updateSelectables();
  }

  Future<void> _loadNotesAndTags() async {
    try {
      final notes = await _syncService.getCachedNotes();
      final tagRegExp = RegExp(r'#([a-zA-Z0-9_\-]+)');
      final Set<String> tagSet = {};

      for (final note in notes) {
        final matches = tagRegExp.allMatches(note.content);
        for (final match in matches) {
          tagSet.add(match.group(0)!);
        }
      }

      setState(() {
        _allNotes = notes;
        _filteredNotes = notes;
        _allTags = tagSet.toList();
        _filteredTags = List.from(_allTags);
        _isLoadingNotes = false;
        _updateSelectables();
      });
    } catch (e) {
      debugPrint('Failed to load notes in command palette: $e');
      setState(() {
        _isLoadingNotes = false;
        _updateSelectables();
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredCommands = List.from(_commands);
        _filteredTags = List.from(_allTags);
        _filteredNotes = List.from(_allNotes);
      } else if (query.startsWith('/')) {
        // Only commands mode
        _filteredCommands = _commands.where((cmd) {
          return cmd.command.toLowerCase().contains(query) ||
              cmd.title.toLowerCase().contains(query);
        }).toList();
        _filteredTags = [];
        _filteredNotes = [];
      } else {
        // Search tags, titles, and note content
        _filteredCommands = _commands.where((cmd) {
          return cmd.title.toLowerCase().contains(query);
        }).toList();

        _filteredTags = _allTags.where((tag) {
          return tag.toLowerCase().contains(query);
        }).toList();

        _filteredNotes = _allNotes.where((note) {
          return note.title.toLowerCase().contains(query) ||
              note.fileName.toLowerCase().contains(query) ||
              note.content.toLowerCase().contains(query);
        }).toList();
      }
      _updateSelectables();
    });
  }

  Future<void> _openNote(IsarNote note) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
    );

    try {
      final content = await _apiService.fetchNoteContent(note.fileName);
      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context); // Close Command Palette
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteViewerScreen(
              title: note.title,
              content: content,
              fileName: note.fileName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load note content: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.40),
      body: Stack(
        children: [
          // 1. Frosted Glass Backdrop Blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 2. Dismiss overlay on tapping background
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // 3. Centralized Floating Search Palette Card
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Hero(
                  tag: 'command_palette',
                  child: Material(
                    color: Colors.transparent,
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (FocusNode node, KeyEvent event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            _navigateDown();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            _navigateUp();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                            _triggerSelected();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                            Navigator.pop(context);
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Container(
                        width: screenWidth * 0.92,
                        constraints: BoxConstraints(
                          maxHeight: screenHeight * 0.70,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface.withOpacity(0.6) : Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.6 : 0.15),
                              blurRadius: 30,
                              spreadRadius: 8,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            // Search field container
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Semantics(
                                      label: 'Search vault tags, notes, or type slash for commands',
                                      textField: true,
                                      child: TextField(
                                        controller: _searchController,
                                        focusNode: _searchFocusNode,
                                        onSubmitted: (_) => _triggerSelected(),
                                        textInputAction: TextInputAction.go,
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: "Search tags, note titles, or type '/' for commands...",
                                          hintStyle: TextStyle(
                                            color: isDark ? Colors.white30 : Colors.black38,
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: Icon(Icons.close, color: isDark ? Colors.white38 : Colors.black38, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                            ),

                            // Search results list
                            Flexible(
                              child: _isLoadingNotes
                                  ? Padding(
                                      padding: const EdgeInsets.all(40.0),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    )
                                  : _buildResultsList(isDark),
                            ),

                            // Sleek bottom helper info
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.02),
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Press ESC or tap background to close",
                                    style: TextStyle(
                                      color: isDark ? Colors.white30 : Colors.black38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      _buildKeyBadge("Enter", isDark),
                                      const SizedBox(width: 4),
                                      Text(
                                        "to select",
                                        style: TextStyle(
                                          color: isDark ? Colors.white30 : Colors.black38,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate()
                      .fadeIn(duration: 250.ms, curve: Curves.easeOut)
                      .slideY(begin: -0.05, end: 0, duration: 300.ms, curve: Curves.easeOutCubic)
                      .scale(begin: const Offset(0.97, 0.97), end: const Offset(1.0, 1.0), duration: 300.ms, curve: Curves.easeOutCubic),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyBadge(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black45,
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildResultsList(bool isDark) {
    final List<Widget> listItems = [];
    int itemIndex = 0;

    // 1. Add matching commands
    if (_filteredCommands.isNotEmpty) {
      listItems.add(_buildSectionHeader("COMMANDS", isDark));
      for (final cmd in _filteredCommands) {
        final currentIndex = itemIndex++;
        final isSelected = currentIndex == _selectedIndex;
        listItems.add(
          _buildPaletteTile(
            title: cmd.title,
            subtitle: cmd.subtitle,
            leadingIcon: cmd.icon,
            leadingColor: Theme.of(context).colorScheme.primary,
            trailingText: cmd.command,
            onTap: () {
              setState(() {
                _selectedIndex = currentIndex;
              });
              HapticFeedbackManager.lightImpact();
              cmd.action(context);
            },
            isDark: isDark,
            isSelected: isSelected,
          ),
        );
      }
    }

    // 2. Add matching tags
    if (_filteredTags.isNotEmpty) {
      listItems.add(_buildSectionHeader("TAGS", isDark));
      listItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filteredTags.map((tag) {
              final currentIndex = itemIndex++;
              final isSelected = currentIndex == _selectedIndex;
              return Material(
                color: Colors.transparent,
                child: Semantics(
                  label: 'Tag: ${tag.replaceFirst('#', '')}',
                  selected: isSelected,
                  hint: 'Double tap to filter by tag',
                  button: true,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIndex = currentIndex;
                      });
                      HapticFeedbackManager.lightImpact();
                      _searchController.text = tag;
                      _searchController.selection = TextSelection.fromPosition(
                        TextPosition(offset: tag.length),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? Theme.of(context).colorScheme.primary 
                            : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(isSelected ? 1.0 : 0.3),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tag,
                            size: 14,
                            color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tag.replaceFirst('#', ''),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    // 3. Add matching notes
    if (_filteredNotes.isNotEmpty) {
      listItems.add(_buildSectionHeader("VAULT NOTES", isDark));
      for (final note in _filteredNotes) {
        final currentIndex = itemIndex++;
        final isSelected = currentIndex == _selectedIndex;
        listItems.add(
          _buildPaletteTile(
            title: note.title,
            subtitle: note.fileName,
            leadingIcon: Icons.description_outlined,
            leadingColor: Theme.of(context).colorScheme.primary,
            onTap: () {
              setState(() {
                _selectedIndex = currentIndex;
              });
              _openNote(note);
            },
            isDark: isDark,
            isSelected: isSelected,
          ),
        );
      }
    }

    // 4. Fallback when nothing is found
    if (listItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 12),
            Text(
              "No results found",
              style: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: listItems,
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }

  Widget _buildPaletteTile({
    required String title,
    required String subtitle,
    required IconData leadingIcon,
    required Color leadingColor,
    String? trailingText,
    required VoidCallback onTap,
    required bool isDark,
    bool isSelected = false,
  }) {
    return Semantics(
      label: '$title, $subtitle',
      selected: isSelected,
      hint: 'Double tap to select',
      button: true,
      child: Material(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
            : Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            border: isSelected
                ? Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4))
                : const Border(left: BorderSide(color: Colors.transparent, width: 4)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(isSelected ? 16 : 20, 10, 20, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                          : leadingColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(leadingIcon, color: leadingColor, size: 18),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: isDark ? Colors.white30 : Colors.black38,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (trailingText != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        trailingText,
                        style: TextStyle(
                          color: isDark ? Colors.white30 : Colors.black38,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CommandItem {
  final String command;
  final String title;
  final String subtitle;
  final IconData icon;
  final Function(BuildContext) action;

  CommandItem({
    required this.command,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.action,
  });
}

// Selectable Item wrappers for unified list index-based keyboard focus
abstract class SelectableItem {
  void trigger(BuildContext context);
}

class CommandSelectable extends SelectableItem {
  final CommandItem commandItem;
  CommandSelectable(this.commandItem);
  @override
  void trigger(BuildContext context) {
    HapticFeedbackManager.lightImpact();
    commandItem.action(context);
  }
}

class TagSelectable extends SelectableItem {
  final String tag;
  final VoidCallback onTap;
  TagSelectable(this.tag, this.onTap);
  @override
  void trigger(BuildContext context) {
    HapticFeedbackManager.lightImpact();
    onTap();
  }
}

class NoteSelectable extends SelectableItem {
  final IsarNote note;
  final Function(IsarNote) onOpen;
  NoteSelectable(this.note, this.onOpen);
  @override
  void trigger(BuildContext context) {
    onOpen(note);
  }
}
