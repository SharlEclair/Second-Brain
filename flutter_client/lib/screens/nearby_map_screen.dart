import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';
import 'note_viewer_screen.dart';

class NearbyMapScreen extends StatefulWidget {
  const NearbyMapScreen({super.key});

  @override
  State<NearbyMapScreen> createState() => _NearbyMapScreenState();
}

class _NearbyMapScreenState extends State<NearbyMapScreen> {
  final ApiService _apiService = ApiService();
  GoogleMapController? _mapController;
  Position? _currentPosition;
  List<Map<String, dynamic>> _nearbySpots = [];
  bool _isLoading = true;
  final Set<Marker> _markers = {};

  static const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#121212"
      }
    ]
  },
  {
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#212121"
      }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9e9e9e"
      }
    ]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#bdbdbd"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#181818"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#616161"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#1b1b1b"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.fill",
    "stylers": [
      {
        "color": "#2c2c2c"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#8a8a8a"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#373737"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#3c3c3c"
      }
    ]
  },
  {
    "featureType": "road.highway.controlled_access",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#4e4e4e"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#616161"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#000000"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#3d3d3d"
      }
    ]
  }
]
''';

  @override
  void initState() {
    super.initState();
    _initLocationAndFetchNearby();
  }

  Future<void> _initLocationAndFetchNearby() async {
    bool serviceEnabled;
    LocationPermission permission;

    setState(() {
      _isLoading = true;
    });

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });

      await _fetchNearby(position.latitude, position.longitude);
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString(),
        backgroundColor: Colors.redAccent,
        gravity: ToastGravity.BOTTOM,
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchNearby(double lat, double lng) async {
    try {
      final spots = await _apiService.fetchNearby(lat, lng);
      setState(() {
        _nearbySpots = spots;
        _isLoading = false;
      });
      _updateMarkers();
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Failed to load nearby places: $e",
        backgroundColor: Colors.redAccent,
        gravity: ToastGravity.BOTTOM,
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateMarkers() {
    setState(() {
      _markers.clear();
      
      // Add current location marker
      if (_currentPosition != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId("current_location"),
            position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: "My Location"),
          ),
        );
      }

      // Add spots markers
      for (final spot in _nearbySpots) {
        final double? lat = spot['latitude'];
        final double? lng = spot['longitude'];
        if (lat != null && lng != null) {
          _markers.add(
            Marker(
              markerId: MarkerId("${spot['place_name']}_${spot['source_note']}"),
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(
                title: spot['place_name'],
                snippet: "${spot['type']} • ${spot['distance_km']} km away",
                onTap: () => _openNote(spot),
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _openNote(Map<String, dynamic> spot) async {
    final fileName = spot['source_note'];
    final title = spot['note_title'] ?? spot['place_name'];
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFF97316))),
    );

    try {
      final content = await _apiService.fetchNoteContent(fileName);
      if (mounted) {
        Navigator.pop(context); // Close dialog
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
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        Fluttertoast.showToast(
          msg: "Failed to open note: $e",
          backgroundColor: Colors.red,
          gravity: ToastGravity.BOTTOM,
        );
      }
    }
  }

  Future<void> _hideLocation(Map<String, dynamic> spot) async {
    final fileName = spot['source_note'];
    final placeName = spot['place_name'];
    
    // Heavy haptics trigger
    HapticFeedback.heavyImpact();

    setState(() {
      _nearbySpots.remove(spot);
      _updateMarkers();
    });

    final success = await _apiService.hideLocation(fileName, name: placeName);
    if (success) {
      Fluttertoast.showToast(
        msg: "Hidden: $placeName",
        backgroundColor: const Color(0xFFF97316),
        textColor: Colors.white,
        gravity: ToastGravity.BOTTOM,
      );
    } else {
      // Revert if failed
      Fluttertoast.showToast(
        msg: "Failed to hide location on server",
        backgroundColor: Colors.redAccent,
        gravity: ToastGravity.BOTTOM,
      );
      _initLocationAndFetchNearby();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initialCameraPosition = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(-37.8136, 144.9631); // Default to Melbourne

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "NEARBY SPOTS",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            fontSize: 14,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.black45,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Google Map
          _isLoading && _currentPosition == null
              ? Container(
                  color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF97316)),
                  ),
                )
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialCameraPosition,
                    zoom: 14.0,
                  ),
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  style: _darkMapStyle,
                  markers: _markers,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
          
          // 2. Loading Indicator Overlay
          if (_isLoading && _currentPosition != null)
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFF97316),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Updating nearby spots...",
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 3. Draggable Scrollable Sheet at the bottom
          if (!_isLoading || _nearbySpots.isNotEmpty)
            DraggableScrollableSheet(
              initialChildSize: 0.3,
              minChildSize: 0.15,
              maxChildSize: 0.8,
              builder: (BuildContext context, ScrollController scrollController) {
                // Group nearby spots by category
                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final spot in _nearbySpots) {
                  final cat = spot['category'] ?? spot['type'] ?? 'Spot to Visit';
                  grouped.putIfAbsent(cat, () => []).add(spot);
                }

                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111115) : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      // Drag handle bar
                      Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "EXPLORE NEARBY",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                color: isDark ? Colors.white30 : Colors.black38,
                              ),
                            ),
                            Text(
                              "${_nearbySpots.length} spots found",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF97316),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(height: 16),
                      
                      Expanded(
                        child: _nearbySpots.isEmpty
                            ? Center(
                                child: Text(
                                  "No nearby spots found.",
                                  style: TextStyle(
                                    color: isDark ? Colors.white24 : Colors.black38,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: grouped.keys.length,
                                itemBuilder: (context, sectionIndex) {
                                  final sectionKey = grouped.keys.elementAt(sectionIndex);
                                  final sectionSpots = grouped[sectionKey]!;

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Section Header
                                      Padding(
                                        padding: const EdgeInsets.only(left: 12, top: 12, bottom: 6),
                                        child: Text(
                                          sectionKey.toUpperCase(),
                                          style: const TextStyle(
                                            color: Color(0xFFF97316),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                      // Items in section
                                      ...sectionSpots.map((spot) {
                                        return Dismissible(
                                          key: Key("${spot['place_name']}_${spot['source_note']}"),
                                          direction: DismissDirection.endToStart,
                                          background: Container(
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 20),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.visibility_off_outlined,
                                              color: Colors.white,
                                            ),
                                          ),
                                          onDismissed: (direction) {
                                            _hideLocation(spot);
                                          },
                                          child: Card(
                                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                            color: isDark ? const Color(0xFF1E1E24) : const Color(0xFFF1F5F9),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: ListTile(
                                              leading: const Icon(
                                                Icons.location_pin,
                                                color: Color(0xFFF97316),
                                              ),
                                              title: Text(
                                                spot['place_name'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              subtitle: Text(
                                                "${spot['note_title'] ?? 'Note'} • ${spot['distance_km']} km away",
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.open_in_new, size: 18),
                                                onPressed: () => _openNote(spot),
                                                tooltip: "Open Note",
                                              ),
                                              onTap: () {
                                                // Pan map to location
                                                final double? lat = spot['latitude'];
                                                final double? lng = spot['longitude'];
                                                if (lat != null && lng != null && _mapController != null) {
                                                  _mapController!.animateCamera(
                                                    CameraUpdate.newLatLngZoom(
                                                      LatLng(lat, lng),
                                                      16.0,
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
