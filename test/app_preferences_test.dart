import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:schoolway/core/preferences/app_preferences.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('schoolway_preferences_');
    Hive.init(directory.path);
    await AppPreferencesStore.initialize();
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('defaults are safe and onboarding is shown once', () async {
    expect(AppPreferencesStore.read(), isA<AppPreferences>());
    expect(AppPreferencesStore.read().onboardingCompleted, isFalse);
    expect(AppPreferencesStore.read().themeMode, ThemeMode.system);

    await AppPreferencesStore.write(
      const AppPreferences(
        onboardingCompleted: true,
        themeMode: ThemeMode.dark,
        motionPreference: MotionPreference.reduced,
        locale: Locale('en'),
      ),
    );

    final restored = AppPreferencesStore.read();
    expect(restored.onboardingCompleted, isTrue);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.motionPreference, MotionPreference.reduced);
  });
}
