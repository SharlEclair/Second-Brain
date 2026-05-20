import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'debug_logger.dart';

class GeofenceService {
  static Future<void> checkGeofences(ApiService apiService) async {
    try {
      DebugLogger.log('Starting geofence checks...', type: 'GPS');

      // 1. Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          DebugLogger.log('Location permissions denied.', type: 'GPS');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        DebugLogger.log('Location permissions permanently denied.', type: 'GPS');
        return;
      }

      // 2. Get current position
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      DebugLogger.log('Current coordinates: lat=${position.latitude}, lng=${position.longitude}', type: 'GPS');

      // 3. Fetch geofenced spots
      final spots = await apiService.fetchGeofences();
      if (spots.isEmpty) {
        DebugLogger.log('No geofenced spots synced from backend.', type: 'GPS');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final String nowStr = DateTime.now().toIso8601String().substring(0, 10); // Date part only "YYYY-MM-DD"

      int notificationId = 9000;
      for (final spot in spots) {
        final title = spot['title'] ?? 'Spot';
        final fileName = spot['fileName'] ?? '';
        final double? lat = spot['latitude'] != null ? double.tryParse(spot['latitude'].toString()) : null;
        final double? lng = spot['longitude'] != null ? double.tryParse(spot['longitude'].toString()) : null;

        if (lat != null && lng != null) {
          final double distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            lat,
            lng,
          );

          DebugLogger.log('Distance to "$title": ${distance.toStringAsFixed(1)}m', type: 'GPS');

          if (distance <= 500.0) {
            // Check cooldown to prevent notification spamming (e.g. notify once per day per spot)
            final String cooldownKey = 'geofence_notified_${title}_$nowStr';
            final alreadyNotified = prefs.getBool(cooldownKey) ?? false;

            if (!alreadyNotified) {
              DebugLogger.log('Breaching geofence for "$title"! Triggering notification...', type: 'GPS');
              
              await NotificationService.showImmediateNotification(
                id: notificationId++,
                title: '📍 Spot to Visit Nearby!',
                body: 'You are close to "$title". Tap to review your note!',
                payload: fileName,
              );

              await prefs.setBool(cooldownKey, true);
            }
          }
        }
      }
    } catch (e) {
      DebugLogger.log('Error checking geofences: $e', type: 'ERROR');
    }
  }
}
