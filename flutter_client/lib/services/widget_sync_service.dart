import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'api_service.dart';
import 'debug_logger.dart';

@pragma('vm:entry-point')
void widgetSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      final apiService = ApiService();
      final events = await apiService.fetchUpcomingEvents();
      final jsonString = jsonEncode(events);
      
      // Save JSON string under 'agenda_data' key
      await HomeWidget.saveWidgetData<String>('agenda_data', jsonString);
      
      // Redraw FocusMissionWidgetProvider
      await HomeWidget.updateWidget(
        androidName: 'FocusMissionWidgetProvider',
        name: 'FocusMissionWidgetProvider',
      );
      
      DebugLogger.log('Background widget sync task executed successfully.', type: 'WIDGET');
    } catch (e) {
      DebugLogger.log('Background widget sync task failed: $e', type: 'ERROR');
    }
    return true;
  });
}

class WidgetSyncService {
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        widgetSyncCallbackDispatcher,
        isInDebugMode: false,
      );
      
      // Register periodic fetch task every 2 hours
      await Workmanager().registerPeriodicTask(
        "widget_agenda_sync_task",
        "widgetAgendaSyncTask",
        frequency: const Duration(hours: 2),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
      DebugLogger.log('Workmanager initialized for agenda widget sync.', type: 'WIDGET');
    } catch (e) {
      DebugLogger.log('Failed to initialize Workmanager for agenda: $e', type: 'ERROR');
    }
  }
}
