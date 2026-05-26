import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:second_brain/providers/providers.dart';
import 'package:second_brain/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Riverpod Providers Tests', () {
    late SharedPreferences sharedPreferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'is_light_theme': false});
      sharedPreferences = await SharedPreferences.getInstance();
    });

    test('apiServiceProvider returns ApiService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final apiService = container.read(apiServiceProvider);
      expect(apiService, isA<ApiService>());
    });

    test('themeModeProvider initializes to dark mode by default', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
      );
      addTearDown(container.dispose);

      final themeMode = container.read(themeModeProvider);
      expect(themeMode, ThemeMode.dark);
    });

    test('themeModeProvider toggles light and dark modes correctly', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(themeModeProvider.notifier);
      
      // Initial is dark
      expect(container.read(themeModeProvider), ThemeMode.dark);

      // Toggle to light
      notifier.toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(sharedPreferences.getBool('is_light_theme'), true);

      // Toggle back to dark
      notifier.toggleTheme();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(sharedPreferences.getBool('is_light_theme'), false);
    });
  });
}
