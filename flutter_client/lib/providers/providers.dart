import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/queue_service.dart';

// Service Providers
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final queueServiceProvider = Provider<QueueService>((ref) {
  return QueueService();
});

// SharedPreferences Provider (Needs to be overridden in main.dart)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences not initialized');
});

// Theme Mode State Notifier
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences _prefs;

  ThemeModeNotifier(this._prefs) : super(ThemeMode.dark) {
    final isLight = _prefs.getBool('is_light_theme') ?? false;
    state = isLight ? ThemeMode.light : ThemeMode.dark;
  }

  void toggleTheme() {
    if (state == ThemeMode.light) {
      state = ThemeMode.dark;
      _prefs.setBool('is_light_theme', false);
    } else {
      state = ThemeMode.light;
      _prefs.setBool('is_light_theme', true);
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});
