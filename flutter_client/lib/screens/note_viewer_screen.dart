import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import 'dart:async';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:url_launcher/url_launcher.dart';


class NoteLoaderScreen extends StatefulWidget {
  final String fileName;

  const NoteLoaderScreen({super.key, required this.fileName});

  @override
  State<NoteLoaderScreen> createState() => _NoteLoaderScreenState();
}

class _NoteLoaderScreenState extends State<NoteLoaderScreen> {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  bool _loading = true;
  String? _error;
  String? _content;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    try {
      final localContent = await _storageService.readNote(widget.fileName);
      if (localContent != null) {
        if (mounted) {
          setState(() {
            _content = localContent;
            _loading = false;
          });
        }
        // Background fetch to update cache
        try {
          final remoteContent = await _apiService.fetchNoteContent(widget.fileName);
          await _storageService.saveNote(widget.fileName, remoteContent);
          if (mounted && _content != remoteContent) {
            setState(() {
              _content = remoteContent;
            });
          }
        } catch (_) {}
      } else {
        try {
          final content = await _apiService.fetchNoteContent(widget.fileName);
          await _storageService.saveNote(widget.fileName, content);
          if (mounted) {
            setState(() {
              _content = content;
              _loading = false;
            });
          }
        } catch (apiErr) {
          // If remote fetch fails, try to load from local Isar database cache
          final cached = await SyncService().getCachedNote(widget.fileName);
          if (cached != null && mounted) {
            setState(() {
              _content = cached.content;
              _loading = false;
            });
          } else {
            rethrow; // Rethrow original apiErr if not cached
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to load note:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    final title = widget.fileName.split('/').last.replaceAll('.md', '');
    return NoteViewerScreen(
      title: title,
      content: _content ?? '',
      fileName: widget.fileName,
    );
  }
}

class NoteViewerScreen extends StatefulWidget {
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
  State<NoteViewerScreen> createState() => _NoteViewerScreenState();
}

class _NoteViewerScreenState extends State<NoteViewerScreen> {
  late String _currentContent;
  String? _mapsApiKey;
  bool _fetchingApiKey = false;

  @override
  void initState() {
    super.initState();
    _currentContent = widget.content;
    _fetchMapsApiKey();
  }

  Future<void> _fetchMapsApiKey() async {
    if (!mounted) return;
    setState(() {
      _fetchingApiKey = true;
    });
    try {
      final config = await ApiService().fetchConfig();
      if (mounted) {
        setState(() {
          _mapsApiKey = config['maps_api_key'];
          _fetchingApiKey = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch maps API key: $e");
      if (mounted) {
        setState(() {
          _fetchingApiKey = false;
        });
      }
    }
  }

  Map<String, String> _parseFrontmatter(String md) {
    final Map<String, String> metadata = {};
    if (!md.startsWith('---')) return metadata;
    
    final parts = md.split('---');
    if (parts.length < 3) return metadata;
    
    final frontmatterText = parts[1];
    final lines = frontmatterText.split('\n');
    for (var line in lines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        metadata[key] = value;
      }
    }
    return metadata;
  }

  String _updateLocalFrontmatterCoordinates(String content, double lat, double lng) {
    final frontmatterRegex = RegExp(r"^---\s*\n(.*?)\n---\s*\n", dotAll: true);
    final match = frontmatterRegex.firstMatch(content);
    
    if (match != null) {
      final frontmatterText = match.group(1)!;
      final remaining = content.substring(match.end);
      
      final lines = frontmatterText.split('\n');
      final newLines = <String>[];
      bool latFound = false;
      bool lngFound = false;
      
      for (var line in lines) {
        if (line.trim().startsWith('latitude:')) {
          newLines.add('latitude: $lat');
          latFound = true;
        } else if (line.trim().startsWith('longitude:')) {
          newLines.add('longitude: $lng');
          lngFound = true;
        } else {
          newLines.add(line);
        }
      }
      
      if (!latFound) newLines.add('latitude: $lat');
      if (!lngFound) newLines.add('longitude: $lng');
      
      final newFrontmatter = newLines.join('\n');
      return '---\n$newFrontmatter\n---\n$remaining';
    } else {
      return '---\nlatitude: $lat\nlongitude: $lng\n---\n$content';
    }
  }

  Future<void> _openMapApp(double lat, double lng, {String? placeName}) async {
    String query;
    if (placeName != null && placeName.isNotEmpty) {
      query = Uri.encodeComponent(placeName);
    } else {
      query = '$lat,$lng';
    }
    final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$query");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not open maps application: $e")),
        );
      }
    }
  }

  Future<void> _openLocationSearch() async {
    if (_mapsApiKey == null || _mapsApiKey!.isEmpty) {
      await _fetchMapsApiKey();
      if (_mapsApiKey == null || _mapsApiKey!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Google Maps API Key is not configured. Add Maps_API_KEY to backend .env"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    final place = await showDialog<Place>(
      context: context,
      builder: (context) => PlaceSearchDialog(apiKey: _mapsApiKey!),
    );

    if (place != null && place.latLng != null && mounted) {
      final lat = place.latLng!.lat;
      final lng = place.latLng!.lng;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      try {
        await ApiService().updateNoteLocation(widget.fileName, lat, lng);
        if (mounted) {
          Navigator.pop(context); // Pop progress dialog
          
          final newContent = _updateLocalFrontmatterCoordinates(_currentContent, lat, lng);
          setState(() {
            _currentContent = newContent;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Location updated to ${place.name ?? '$lat, $lng'}"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Pop progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to update location: $e"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Widget _buildLocationBar(BuildContext context, Map<String, String> metadata, bool isDark) {
    final category = metadata['category'];
    if (category != 'Spot to Visit' && category != 'Event') {
      return const SizedBox.shrink();
    }

    final latStr = metadata['latitude'];
    final lngStr = metadata['longitude'];
    
    double? lat;
    double? lng;
    if (latStr != null && latStr != 'null') {
      lat = double.tryParse(latStr);
    }
    if (lngStr != null && lngStr != 'null') {
      lng = double.tryParse(lngStr);
    }

    final hasCoords = lat != null && lng != null;

    if (!hasCoords) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
          border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, color: isDark ? Colors.white38 : Colors.black38, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Location missing",
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _openLocationSearch,
              icon: const Icon(Icons.add_location_alt_outlined, size: 16),
              label: const Text("Set Location"),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14532D).withOpacity(0.15) : const Color(0xFFDCFCE7).withOpacity(0.5),
        border: Border(bottom: BorderSide(color: isDark ? Colors.green.withOpacity(0.2) : Colors.green.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Location set (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})",
              style: TextStyle(
                color: isDark ? Colors.green[200] : Colors.green[800],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            onPressed: _openLocationSearch,
            tooltip: "Change Location",
            color: isDark ? Colors.white60 : Colors.black54,
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: () {
              // Try to parse `locations:` from frontmatter
              String? placeName;
              final locMatch = RegExp(r'locations:\s*\n\s*-\s*([^\n]+)').firstMatch(_currentContent);
              if (locMatch != null && locMatch.group(1) != null) {
                placeName = locMatch.group(1)!.trim();
              } else {
                placeName = widget.title;
              }
              _openMapApp(lat!, lng!, placeName: placeName);
            },
            icon: const Icon(Icons.map_outlined, size: 14),
            label: const Text("Open"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metadata = _parseFrontmatter(_currentContent);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      appBar: AppBar(
        title: Text(widget.title.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: () {
              Share.share(_currentContent, subject: widget.title);
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLocationBar(context, metadata, isDark),
          Expanded(
            child: Markdown(
              data: _currentContent,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.bold, height: 1.5),
                h2: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
                h3: TextStyle(color: isDark ? Colors.white : const Color(0xFF334155), fontSize: 18, fontWeight: FontWeight.bold),
                p: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF334155), fontSize: 15, height: 1.6),
                code: TextStyle(
                  backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF1F5F9), 
                  fontFamily: 'monospace', 
                  color: Theme.of(context).colorScheme.primary,
                ),
                codeblockDecoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111111) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                ),
                blockquote: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontStyle: FontStyle.italic),
                blockquoteDecoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
                ),
                listBullet: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class PlaceSearchDialog extends StatefulWidget {
  final String apiKey;
  const PlaceSearchDialog({super.key, required this.apiKey});

  @override
  State<PlaceSearchDialog> createState() => _PlaceSearchDialogState();
}

class _PlaceSearchDialogState extends State<PlaceSearchDialog> {
  late final FlutterGooglePlacesSdk _places;
  List<AutocompletePrediction> _predictions = [];
  bool _searching = false;
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _places = FlutterGooglePlacesSdk(widget.apiKey);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.trim().isEmpty) {
        setState(() {
          _predictions = [];
        });
        return;
      }
      setState(() {
        _searching = true;
      });
      try {
        final res = await _places.findAutocompletePredictions(query);
        if (mounted) {
          setState(() {
            _predictions = res.predictions;
          });
        }
      } catch (e) {
        debugPrint("Error fetching predictions: $e");
      } finally {
        if (mounted) {
          setState(() {
            _searching = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Search Location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Type place name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _predictions.isEmpty
                  ? Center(
                      child: Text(
                        _controller.text.isEmpty
                            ? 'Search for a restaurant, venue or city...'
                            : 'No results found',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _predictions.length,
                      itemBuilder: (context, index) {
                        final pred = _predictions[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(pred.primaryText),
                          subtitle: Text(pred.secondaryText),
                          onTap: () async {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                            try {
                              final placeRes = await _places.fetchPlace(
                                pred.placeId,
                                fields: [PlaceField.Location, PlaceField.Name],
                              );
                              if (mounted) {
                                Navigator.pop(context); // Pop loading dialog
                                if (placeRes.place?.latLng != null) {
                                  Navigator.pop(context, placeRes.place);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Failed to retrieve coordinates for this place.')),
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                Navigator.pop(context); // Pop loading dialog
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
