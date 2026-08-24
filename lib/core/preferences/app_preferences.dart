import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum MotionPreference { system, reduced, full }

@immutable
class AppPreferences {
  const AppPreferences({
    required this.onboardingCompleted,
    required this.themeMode,
    required this.motionPreference,
    required this.locale,
  });

  const AppPreferences.defaults()
    : onboardingCompleted = false,
      themeMode = ThemeMode.system,
      motionPreference = MotionPreference.system,
      locale = const Locale('en');

  final bool onboardingCompleted;
  final ThemeMode themeMode;
  final MotionPreference motionPreference;
  final Locale locale;

  AppPreferences copyWith({
    bool? onboardingCompleted,
    ThemeMode? themeMode,
    MotionPreference? motionPreference,
    Locale? locale,
  }) => AppPreferences(
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    themeMode: themeMode ?? this.themeMode,
    motionPreference: motionPreference ?? this.motionPreference,
    locale: locale ?? this.locale,
  );
}

abstract final class AppPreferencesStore {
  static const boxName = 'app_preferences';
  static late Box<dynamic> _box;

  static Future<void> initialize() async {
    _box = await Hive.openBox<dynamic>(boxName);
  }

  static AppPreferences read() {
    final themeName = _box.get('themeMode', defaultValue: 'system') as String;
    final motionName =
        _box.get('motionPreference', defaultValue: 'system') as String;
    return AppPreferences(
      onboardingCompleted:
          _box.get('onboardingCompleted', defaultValue: false) as bool,
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      motionPreference: MotionPreference.values.firstWhere(
        (value) => value.name == motionName,
        orElse: () => MotionPreference.system,
      ),
      locale: Locale(_box.get('locale', defaultValue: 'en') as String),
    );
  }

  static Future<void> write(AppPreferences value) async {
    await _box.putAll({
      'onboardingCompleted': value.onboardingCompleted,
      'themeMode': value.themeMode.name,
      'motionPreference': value.motionPreference.name,
      'locale': value.locale.languageCode,
    });
  }
}

class AppPreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => AppPreferencesStore.read();

  Future<void> _save(AppPreferences next) async {
    state = next;
    await AppPreferencesStore.write(next);
  }

  Future<void> completeOnboarding() =>
      _save(state.copyWith(onboardingCompleted: true));

  Future<void> showOnboardingAgain() =>
      _save(state.copyWith(onboardingCompleted: false));

  Future<void> setThemeMode(ThemeMode value) =>
      _save(state.copyWith(themeMode: value));

  Future<void> setMotionPreference(MotionPreference value) =>
      _save(state.copyWith(motionPreference: value));

  Future<void> setLocale(Locale value) => _save(state.copyWith(locale: value));
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferences>(
      AppPreferencesNotifier.new,
    );
