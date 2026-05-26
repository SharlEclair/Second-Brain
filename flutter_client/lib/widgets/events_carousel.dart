import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class EventsAgendaView extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final Function(String fileName, String title) onEventTap;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const EventsAgendaView({
    super.key,
    required this.events,
    required this.onEventTap,
    this.shrinkWrap = false,
    this.physics,
  });

  static const List<String> _months = [
    '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. Parse and sort all events by date
    final List<Map<String, dynamic>> sortedEvents = List.from(events);
    sortedEvents.sort((a, b) {
      final aDateStr = a['event_date'] ?? '';
      final bDateStr = b['event_date'] ?? '';
      if (aDateStr.isEmpty) return 1;
      if (bDateStr.isEmpty) return -1;
      try {
        final aDt = DateTime.parse(aDateStr);
        final bDt = DateTime.parse(bDateStr);
        return aDt.compareTo(bDt);
      } catch (_) {
        return 0;
      }
    });

    // 2. Group events into TODAY, TOMORROW, LATER
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final dayAfterTomorrowStart = todayStart.add(const Duration(days: 2));

    final Map<String, List<Map<String, dynamic>>> groups = {
      'TODAY': [],
      'TOMORROW': [],
      'LATER': [],
    };

    for (final event in sortedEvents) {
      final dateStr = event['event_date'] ?? '';
      if (dateStr.isEmpty) {
        groups['LATER']!.add(event);
        continue;
      }
      try {
        final dt = DateTime.parse(dateStr);
        if (dt.isBefore(tomorrowStart)) {
          // Put today and any past events under TODAY
          groups['TODAY']!.add(event);
        } else if (dt.isBefore(dayAfterTomorrowStart)) {
          groups['TOMORROW']!.add(event);
        } else {
          groups['LATER']!.add(event);
        }
      } catch (_) {
        groups['LATER']!.add(event);
      }
    }

    // Build the list of widgets
    final List<Widget> listItems = [];
    int animIndex = 0;

    void addGroupSection(String title, List<Map<String, dynamic>> groupEvents, Color accentColor) {
      if (groupEvents.isEmpty) return;

      listItems.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                  thickness: 1,
                ),
              ),
            ],
          ),
        ),
      );

      for (final event in groupEvents) {
        final index = animIndex++;
        final title = event['title'] ?? 'Untitled Event';
        final fileName = event['fileName'] ?? '';
        final eventDateStr = event['event_date'] ?? '';
        final platform = event['platform'] ?? 'local';

        String month = 'EVT';
        String day = '??';
        String timeStr = 'All Day';
        try {
          if (eventDateStr.isNotEmpty) {
            final dt = DateTime.parse(eventDateStr);
            month = _months[dt.month];
            day = dt.day.toString();
            final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
            final ampm = dt.hour >= 12 ? 'PM' : 'AM';
            final minute = dt.minute.toString().padLeft(2, '0');
            timeStr = '$hour:$minute $ampm';
          }
        } catch (_) {}

        listItems.add(
          GestureDetector(
            onTap: () => onEventTap(fileName, title),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111115) : Colors.white,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Accent left border
                      Container(
                        width: 4,
                        color: accentColor,
                      ),
                      const SizedBox(width: 12),
                      
                      // Calendar Badge
                      Center(
                        child: Container(
                          width: 52,
                          height: 52,
                          margin: const EdgeInsets.symmetric(vertical: 12.0),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF07070B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                month,
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                day,
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      
                      // Details
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time_rounded, 
                                    color: isDark ? Colors.white30 : Colors.black38, 
                                    size: 12
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: isDark ? Colors.white54 : Colors.black54,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Platform tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(4.0),
                                      border: Border.all(
                                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                                      ),
                                    ),
                                    child: Text(
                                      platform.toUpperCase(),
                                      style: TextStyle(
                                        color: isDark ? Colors.white54 : Colors.black54,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Action Chevron
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Center(
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: isDark ? Colors.white24 : Colors.black26,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .animate()
          .fadeIn(delay: Duration(milliseconds: index * 40), duration: 250.ms)
          .slideX(begin: 0.05, end: 0, duration: 300.ms, curve: Curves.easeOutQuad),
        );
      }
    }

    // Add sections in order of urgency
    addGroupSection('TODAY', groups['TODAY']!, Theme.of(context).colorScheme.primary);
    addGroupSection('TOMORROW', groups['TOMORROW']!, Colors.amber);
    addGroupSection('LATER', groups['LATER']!, Colors.grey);

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: physics ?? (shrinkWrap ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics()),
      padding: const EdgeInsets.only(bottom: 24),
      children: listItems,
    );
  }
}
