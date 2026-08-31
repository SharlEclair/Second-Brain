import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:window_manager/window_manager.dart';
import 'theme/app_theme.dart';
import 'router/app_router.dart';
import 'providers/providers.dart';
import 'screens/chat_screen.dart';
import 'screens/scratchpad_screen.dart';
import 'screens/quick_ask_screen.dart';
import 'widgets/command_palette_overlay.dart';
import 'services/widget_service.dart';
import 'services/widget_sync_service.dart';
import 'services/notification_service.dart';
import 'services/geofence_service.dart';
import 'services/offline_queue_service.dart';
import 'services/share_service.dart';
import 'services/clipboard_service.dart';
import 'services/background_share_service.dart';
import 'services/debug_logger.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  
  // Custom Window dressing for desktop targets
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await flutter_acrylic.Window.initialize();
    } catch (e) {
      debugPrint("Failed to initialize flutter_acrylic: $e");
    }

    try {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1200, 800),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        if (Platform.isWindows) {
          await flutter_acrylic.Window.setEffect(
            effect: flutter_acrylic.WindowEffect.mica,
            color: const Color(0x00000000),
          );
        }
      });
    } catch (e) {
      debugPrint("Failed to initialize window_manager: $e");
    }
  }

  final prefs = await SharedPreferences.getInstance();
  
  try {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await NotificationService().initialize(rootNavigatorKey);
    }
  } catch (e) {
    debugPrint("Failed to initialize NotificationService: $e");
  }
  
  try {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await WidgetSyncService.initialize();
    }
  } catch (e) {
    debugPrint("Failed to initialize WidgetSyncService: $e");
  }
  
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const SecondBrainApp(),
    ),
  );
}

class SecondBrainApp extends ConsumerStatefulWidget {
  const SecondBrainApp({super.key});

  @override
  ConsumerState<SecondBrainApp> createState() => _SecondBrainAppState();
}

class _SecondBrainAppState extends ConsumerState<SecondBrainApp> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.second_brain/actions');
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final apiService = ref.read(apiServiceProvider);

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
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
      WidgetService.syncAllWidgets(apiService);

      // Initialize ShareService and BackgroundShareService
      ShareService.initialize(
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: _scaffoldMessengerKey,
      );
      BackgroundShareService.initialize();

      // Check geofences on startup
      GeofenceService.checkGeofences(apiService);
    }

    // Initialize connectivity listener for offline queues
    OfflineQueueService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      ShareService.dispose();
    }
    OfflineQueueService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        ClipboardService.checkClipboardForIngest(context);
        GeofenceService.checkGeofences(ref.read(apiServiceProvider));
      }
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
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);

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
        appRouter.push('/scratchpad');
        break;
      case 'action/search':
        _showToast('🔍 Command Palette opened');
        rootNavigatorKey.currentState?.push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black.withOpacity(0.40),
            pageBuilder: (context, _, __) => const CommandPaletteOverlay(),
          ),
        );
        break;
      case 'action/quick_ask':
        _showToast('🧠 Quick Ask');
        appRouter.push('/quick_ask');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Second Brain',
      routerConfig: appRouter,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: currentMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
    );
  }
}
