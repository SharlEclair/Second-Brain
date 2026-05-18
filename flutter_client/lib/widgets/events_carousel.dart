import 'package:flutter/material.dart';

class EventsCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final Function(String fileName, String title) onEventTap;

  const EventsCarousel({
    super.key,
    required this.events,
    required this.onEventTap,
  });

  static const List<String> _months = [
    '', 'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(Icons.calendar_month, color: Color(0xFFF97316), size: 16),
              SizedBox(width: 8),
              Text(
                'UPCOMING EVENTS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              final String title = event['title'] ?? 'Untitled Event';
              final String fileName = event['fileName'] ?? '';
              final String eventDateStr = event['event_date'] ?? '';
              final String platform = event['platform'] ?? 'local';

              // Parse event date
              String month = 'EVT';
              String day = '??';
              String timeStr = 'All Day';
              try {
                if (eventDateStr.isNotEmpty) {
                  final dt = DateTime.parse(eventDateStr);
                  month = _months[dt.month];
                  day = dt.day.toString();
                  // Format time
                  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
                  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
                  final minute = dt.minute.toString().padLeft(2, '0');
                  timeStr = '$hour:$minute $ampm';
                }
              } catch (_) {}

              return GestureDetector(
                onTap: () => onEventTap(fileName, title),
                child: Container(
                  width: 240,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: const Color(0xFF222222)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      // Calendar Badge
                      Container(
                        width: 50,
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF050505),
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(color: const Color(0xFF1A1A1A)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              month,
                              style: const TextStyle(
                                color: Color(0xFFF97316),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              day,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, color: Colors.white24, size: 10),
                                const SizedBox(width: 3),
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Platform tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Text(
                                platform.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
