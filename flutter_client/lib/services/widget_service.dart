import 'dart:convert';
import 'dart:math';
import 'package:home_widget/home_widget.dart';
import '../services/api_service.dart';
import 'debug_logger.dart';

class WidgetService {

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
}
