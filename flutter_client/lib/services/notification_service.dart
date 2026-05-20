import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../screens/debug_logs_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static late final GlobalKey<NavigatorState> navigatorKey;
  bool _initialized = false;

  Future<void> initialize(GlobalKey<NavigatorState> navKey) async {
    if (_initialized) return;
    navigatorKey = navKey;

    // 1. Initialize Local Notifications
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      tz.initializeTimeZones();

      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint("Notification clicked: ${response.payload}");
        },
      );
    } catch (e) {
      debugPrint("Failed to initialize local notifications: $e");
    }

    // 2. Initialize Firebase (will throw if Firebase options/config are missing)
    try {
      await Firebase.initializeApp();
      _initialized = true;
      DebugLogger.log('Firebase initialized successfully in NotificationService', type: 'SYSTEM');

      // Request notification permissions
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      DebugLogger.log('Notification permission status: ${settings.authorizationStatus}', type: 'SYSTEM');

      // Fetch token and register it
      await registerDevice();

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        _sendTokenToBackend(newToken);
      });

      // 1. Handle notification tap when the app is in the Background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        DebugLogger.log('Notification tapped from background!', type: 'SYSTEM');
        _handleNotificationRouting(message);
      });

      // 2. Handle notification tap when the app is completely Terminated
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          DebugLogger.log('Notification tapped from terminated state!', type: 'SYSTEM');
          Future.delayed(const Duration(milliseconds: 500), () {
            _handleNotificationRouting(message);
          });
        }
      });

      // 3. Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        DebugLogger.log('Foreground FCM received: ${message.notification?.title}', type: 'SYSTEM');
      });

    } catch (e) {
      DebugLogger.log('Firebase Initialization skipped/failed: $e', type: 'WARNING');
    }
  }

  Future<void> registerDevice() async {
    if (!_initialized) return;
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        DebugLogger.log('FCM Token: $token', type: 'SYSTEM');
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      DebugLogger.log('Error fetching FCM Token: $e', type: 'ERROR');
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('base_url');
      if (baseUrl == null || baseUrl.isEmpty) {
        DebugLogger.log('FCM Token registration deferred: baseUrl not set', type: 'SYSTEM');
        return;
      }

      String cleanBase = baseUrl.trim();
      while (cleanBase.endsWith('/')) {
        cleanBase = cleanBase.substring(0, cleanBase.length - 1);
      }

      final url = Uri.parse('$cleanBase/api/device_token');
      final deviceType = Platform.isAndroid ? 'android' : 'ios';

      DebugLogger.log('Registering FCM token to backend: $url', type: 'SYSTEM');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'token': token,
          'device': deviceType,
        }),
      );

      if (response.statusCode == 200) {
        DebugLogger.log('FCM token registered successfully with backend', type: 'SYSTEM');
      } else {
        DebugLogger.log('FCM token registration failed with status: ${response.statusCode}', type: 'ERROR');
      }
    } catch (e) {
      DebugLogger.log('Error sending FCM token to backend: $e', type: 'ERROR');
    }
  }

  void _handleNotificationRouting(RemoteMessage message) {
    if (message.data.containsKey('route') && message.data['route'] == '/note') {
      final fileName = message.data['fileName'];
      if (fileName != null && fileName.isNotEmpty) {
        navigatorKey.currentState?.pushNamed(
          '/note_viewer', 
          arguments: fileName,
        );
      }
    }
  }

  static Future<void> syncScheduledReminders(ApiService apiService) async {
    try {
      final response = await apiService.getTasks();
      await _notificationsPlugin.cancelAll();

      int notificationId = 0;
      for (final task in response) {
        if (task is! Map) continue;
        final String? text = task['text'];
        final String? dueDateStr = task['due_date'];
        final bool completed = task['completed'] ?? false;

        if (text == null || dueDateStr == null || completed) continue;

        final dateParts = dueDateStr.split('-');
        if (dateParts.length != 3) continue;

        final year = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final day = int.tryParse(dateParts[2]);

        if (year == null || month == null || day == null) continue;

        final scheduledTime = DateTime(year, month, day, 9, 0);
        if (scheduledTime.isBefore(DateTime.now())) {
          continue;
        }

        final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'second_brain_tasks',
          'Second Brain Task Reminders',
          channelDescription: 'Reminders for checklist items extracted from Second Brain notes.',
          importance: Importance.high,
          priority: Priority.high,
        );

        const NotificationDetails details = NotificationDetails(android: androidDetails);

        await _notificationsPlugin.zonedSchedule(
          id: notificationId++,
          title: 'Task Reminder',
          body: text,
          scheduledDate: tzScheduledTime,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
      debugPrint("Synced $notificationId task reminders successfully.");
    } catch (e) {
      debugPrint("Error syncing task reminders: $e");
    }
  }

  static Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'geofence_channel',
      'Geofence Alerts',
      channelDescription: 'Alerts when near saved spots to visit',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: payload,
    );
  }
}
