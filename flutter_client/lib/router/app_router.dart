import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/chat_screen.dart';
import '../screens/debug_logs_screen.dart';
import '../screens/note_viewer_screen.dart';
import '../screens/quick_ask_screen.dart';
import '../screens/scratchpad_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/notes_browser_screen.dart';
import '../screens/audit_dashboard_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ChatScreen(),
    ),
    GoRoute(
      path: '/scratchpad',
      builder: (context, state) => const ScratchpadScreen(),
    ),
    GoRoute(
      path: '/quick_ask',
      builder: (context, state) => const QuickAskScreen(),
    ),
    GoRoute(
      path: '/debug_logs',
      builder: (context, state) => const DebugLogsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/notes_browser',
      builder: (context, state) => const NotesBrowserScreen(),
    ),
    GoRoute(
      path: '/audit_dashboard',
      builder: (context, state) => const AuditDashboardScreen(),
    ),
    GoRoute(
      path: '/note_viewer',
      builder: (context, state) {
        final fileName = state.uri.queryParameters['fileName'] ?? '';
        return NoteLoaderScreen(fileName: fileName);
      },
    ),
  ],
);
