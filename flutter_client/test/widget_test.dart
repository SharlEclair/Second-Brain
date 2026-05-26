import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:second_brain/main.dart';
import 'package:second_brain/providers/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App builds without crashing smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'is_light_theme': false});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const SecondBrainApp(),
      ),
    );

    // Verify app builds
    expect(find.byType(SecondBrainApp), findsOneWidget);
  });
}
