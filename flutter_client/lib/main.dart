import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/chat_screen.dart';
import 'screens/notes_browser_screen.dart';
import 'screens/debug_logs_screen.dart';
import 'screens/note_viewer_screen.dart';
import 'screens/quick_ask_screen.dart';
import 'screens/scratchpad_screen.dart';
import 'services/api_service.dart';
import 'services/queue_service.dart';
import 'services/widget_service.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';
import 'services/geofence_service.dart';
import 'services/offline_queue_service.dart';
import 'services/share_service.dart';
import 'services/clipboard_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  final prefs = await SharedPreferences.getInstance();
  final isLight = prefs.getBool('is_light_theme') ?? false;
  themeNotifier.value = isLight ? ThemeMode.light : ThemeMode.dark;
  try {
    await NotificationService().initialize(navigatorKey);
  } catch (e) {
    debugPrint("Failed to initialize NotificationService: $e");
  }
  runApp(const SecondBrainApp());
}

class SecondBrainApp extends StatefulWidget {
  const SecondBrainApp({super.key});

  @override
  State<SecondBrainApp> createState() => _SecondBrainAppState();
}

class _SecondBrainAppState extends State<SecondBrainApp> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.second_brain/actions');
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = navigatorKey;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set up MethodChannel listener for widget actions
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'triggerAction') {
        final String? action = call.arguments as String?;
        if (action != null) {
          _handleWidgetAction(action);
        }
      }
    });

    // Check for any action that launched the app on startup
    _channel.invokeMethod<String>('getPendingAction').then((action) {
      if (action != null) {
        _handleWidgetAction(action);
      }
    });

    // Sync all widgets on startup
    WidgetService.syncAllWidgets(_apiService);

    // Initialize ShareService
    ShareService.initialize(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
    );

    // Check geofences on startup
    GeofenceService.checkGeofences(_apiService);

    // Initialize connectivity listener for offline queues
    OfflineQueueService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareService.dispose();
    OfflineQueueService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ClipboardService.checkClipboardForIngest(context);
      GeofenceService.checkGeofences(_apiService);
    }
  }

  void _showToast(String message) {
    _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  void _handleWidgetAction(String action) async {
    DebugLogger.log('Triggering Widget Action: $action', type: 'WIDGET');
    
    // Pop any open sub-screens/overlays to ensure we are at the root context
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);

    switch (action) {
      case 'action/voice':
        _showToast('🎙️ Voice Assistant Mode');
        ChatScreen.widgetActionNotifier.value = 'action/voice';
        // Reset the value immediately so the listener triggers on consecutive taps
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ChatScreen.widgetActionNotifier.value = null;
        });
        break;
      case 'action/clipboard':
        _showToast('📋 Ingesting link from Clipboard...');
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && data!.text!.isNotEmpty) {
          ShareService.ingestSharedText(data.text!);
        } else {
          _showToast('❌ Clipboard is empty');
        }
        break;
      case 'action/scratchpad':
        _showToast('✏️ Launching Quick Scratchpad...');
        _navigatorKey.currentState?.push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const ScratchpadScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
          ),
        );
        break;
      case 'action/search':
        _showToast('🔍 Notes Browser focused');
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const NotesBrowserScreen(focusSearch: true))
        );
        break;
      case 'action/quick_ask':
        _showToast('🧠 Quick Ask');
        _navigatorKey.currentState?.push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black.withOpacity(0.6),
            pageBuilder: (context, _, __) => const QuickAskScreen(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Second Brain',
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFEA580C),
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
            scaffoldBackgroundColor: const Color(0xFFFAFAFA),
            useMaterial3: true,
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF0F172A),
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF97316),
              surface: Color(0xFF111111),
              onSurface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF050505),
            useMaterial3: true,
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF111111),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          home: const ChatScreen(),
          onGenerateRoute: (settings) {
            if (settings.name == '/note_viewer') {
              final fileName = settings.arguments as String;
              return MaterialPageRoute(
                builder: (context) => NoteLoaderScreen(fileName: fileName),
              );
            }
            return null;
          },
        );
      },
    );
  }
}
