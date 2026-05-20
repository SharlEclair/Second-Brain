import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'api_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
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
}
