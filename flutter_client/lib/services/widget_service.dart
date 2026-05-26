import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import '../services/api_service.dart';
import 'debug_logger.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      final apiService = ApiService();
      final events = await apiService.fetchUpcomingEvents();
      final jsonString = jsonEncode(events);
      await HomeWidget.saveWidgetData<String>('agenda_data', jsonString);
      
      // Update Android scrollable agenda widget
      await HomeWidget.updateWidget(
        androidName: 'CortexAgendaWidgetProvider',
        name: 'CortexAgendaWidgetProvider',
      );
      
      // Also sync other widgets
      await WidgetService.syncAllWidgets(apiService);
    } catch (e) {
      DebugLogger.log('Background sync failed: $e', type: 'ERROR');
    }
    return true;
  });
}

class WidgetService {
  /// MethodChannel for iOS Live Activities (ActivityKit).
  /// This is iOS-only — calls are safely no-op'd on Android.
  static const _liveActivityChannel = MethodChannel('com.example.second_brain/live_activity');

  /// Refreshes all widgets with active data from local storage & API
  static Future<void> syncAllWidgets(ApiService apiService) async {
    try {
      DebugLogger.log('Syncing all home screen widgets...', type: 'WIDGET');
      await syncThoughtSparks(apiService);
      await syncFocusMission(apiService);
      DebugLogger.log('Widget sync completed successfully!', type: 'WIDGET');
    } catch (e) {
      DebugLogger.log('Failed to sync widgets: $e', type: 'ERROR');
    }
  }

  /// Syncs a collection of 20 random thought insights extracted from fetched notes
  static Future<void> syncThoughtSparks(ApiService apiService) async {
    try {
      final notes = await apiService.fetchNotes();
      if (notes.isEmpty) return;

      final List<String> insights = [];
      final random = Random();

      for (var note in notes) {
        final title = note['title'] ?? 'Insight';
        final fileName = note['fileName'];
        if (fileName != null) {
          try {
            final content = await apiService.fetchNoteContent(fileName);
            // Extract clean high-value sentences (e.g. key takeaways, paragraphs)
            final cleanContent = content
                .replaceAll(RegExp(r'---[\s\S]*?---'), '') // Strip frontmatter
                .replaceAll(RegExp(r'\[\[|\]\]'), '')       // Strip wiki brackets
                .trim();
            
            final sentences = cleanContent
                .split(RegExp(r'(?<=[.!?])\s+'))
                .where((s) => s.length > 20 && s.length < 150 && !s.startsWith('#') && !s.startsWith('!'))
                .toList();

            if (sentences.isNotEmpty) {
              // Grab up to 2 sentences per note
              insights.add(sentences[random.nextInt(sentences.length)]);
              if (sentences.length > 1) {
                insights.add(sentences[random.nextInt(sentences.length)]);
              }
            } else {
              // Fallback to title
              insights.add('Recall: "$title" has been archived in your vault.');
            }
          } catch (_) {
            insights.add('Knowledge node "$title" is synced and ready.');
          }
        }
      }

      // Shuffle and take top 20
      insights.shuffle();
      final finalSparks = insights.take(20).toList();

      if (finalSparks.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>('thought_sparks', jsonEncode(finalSparks));
        await HomeWidget.saveWidgetData<int>('thought_spark_index', 0);
        
        // Trigger redrawing of the Thought Spark widget
        await HomeWidget.updateWidget(
          androidName: 'ThoughtSparkWidgetProvider',
          name: 'ThoughtSparkWidgetProvider',
        );
        DebugLogger.log('Thought Sparks updated: ${finalSparks.length} cached.', type: 'WIDGET');
      }
    } catch (e) {
      DebugLogger.log('Error syncing thought sparks: $e', type: 'ERROR');
    }
  }

  /// Syncs the single most urgent upcoming event extracted by AI RAG
  static Future<void> syncFocusMission(ApiService apiService) async {
    try {
      final events = await apiService.fetchUpcomingEvents();
      if (events.isNotEmpty) {
        // Sort by date (already sorted usually)
        final urgentEvent = events.first;
        final title = urgentEvent['title'] ?? 'Upcoming Task';
        final dateStr = urgentEvent['date'] ?? ''; // e.g. "2026-05-28"
        
        var countdown = 'ACTIVE';
        if (dateStr.isNotEmpty) {
          try {
            final eventDate = DateTime.parse(dateStr);
            final difference = eventDate.difference(DateTime.now()).inDays;
            
            if (difference == 0) {
              countdown = 'TODAY';
            } else if (difference == 1) {
              countdown = 'TOMORROW';
            } else if (difference > 1) {
              countdown = 'IN $difference DAYS';
            } else {
              countdown = 'OVERDUE';
            }
          } catch (_) {}
        }

        await HomeWidget.saveWidgetData<String>('focus_title', title);
        await HomeWidget.saveWidgetData<String>('focus_time', countdown);
      } else {
        await HomeWidget.saveWidgetData<String>('focus_title', 'All Cleared. Ingest more knowledge!');
        await HomeWidget.saveWidgetData<String>('focus_time', 'NO TASKS');
      }

      // Trigger redrawing of the Focus Mission widget
      await HomeWidget.updateWidget(
        androidName: 'FocusMissionWidgetProvider',
        name: 'FocusMissionWidgetProvider',
      );
      DebugLogger.log('Focus Mission widget updated.', type: 'WIDGET');
    } catch (e) {
      DebugLogger.log('Error syncing focus mission: $e', type: 'ERROR');
    }
  }

  /// Initializes the workmanager background syncing
  static Future<void> initializeWorkmanager() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      await Workmanager().registerPeriodicTask(
        "cortex_agenda_sync_task",
        "cortexAgendaSyncTask",
        frequency: const Duration(hours: 2),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
      DebugLogger.log('Workmanager initialized for agenda syncing.', type: 'WIDGET');
    } catch (e) {
      DebugLogger.log('Failed to initialize Workmanager: $e', type: 'ERROR');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Live Activity helpers (iOS-only via custom MethodChannel)
  // On Android these are safe no-ops.
  // ─────────────────────────────────────────────────────────────

  /// Starts the Ingestion Live Activity on the iOS lock screen / Dynamic Island
  static Future<void> startIngestionLiveActivity(String url) async {
    if (!Platform.isIOS) return; // Live Activities are iOS-only
    try {
      await _liveActivityChannel.invokeMethod('startLiveActivity', {
        'title': 'Ingesting Link...',
        'url': url,
        'status': 'Processing...',
        'progress': 0.1,
      });
      DebugLogger.log('Live Activity started for: $url', type: 'WIDGET');
    } on MissingPluginException {
      // Channel not registered on this platform — ignore silently
      DebugLogger.log('Live Activity channel not available (expected on Android)', type: 'WIDGET');
    } catch (e) {
      DebugLogger.log('Failed to start Live Activity: $e', type: 'ERROR');
    }
  }

  /// Updates the Ingestion Live Activity status and progress
  static Future<void> updateIngestionLiveActivity(String url, String status, double progress) async {
    if (!Platform.isIOS) return;
    try {
      await _liveActivityChannel.invokeMethod('updateLiveActivity', {
        'title': 'Ingesting Link...',
        'url': url,
        'status': status,
        'progress': progress,
      });
    } on MissingPluginException {
      // ignore
    } catch (e) {
      DebugLogger.log('Failed to update Live Activity: $e', type: 'ERROR');
    }
  }

  /// Ends the Ingestion Live Activity
  static Future<void> endIngestionLiveActivity(String url, {required bool isSuccess, String? error}) async {
    if (!Platform.isIOS) return;
    try {
      await _liveActivityChannel.invokeMethod('endLiveActivity', {
        'title': isSuccess ? 'Ingestion Complete' : 'Ingestion Failed',
        'url': url,
        'status': isSuccess ? 'Saved to Vault' : (error ?? 'Failed'),
        'progress': isSuccess ? 1.0 : 0.0,
      });
      DebugLogger.log('Live Activity ended for: $url', type: 'WIDGET');
    } on MissingPluginException {
      // ignore
    } catch (e) {
      DebugLogger.log('Failed to end Live Activity: $e', type: 'ERROR');
    }
  }
}

