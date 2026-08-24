import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/core/preferences/app_preferences.dart';
import 'package:schoolway/features/shell/onboarding_screen.dart';
import 'package:schoolway/l10n/app_localizations.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final preferences = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.appearance,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            initialValue: preferences.themeMode,
            decoration: InputDecoration(labelText: strings.theme),
            items: [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text(strings.themeSystem),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text(strings.themeLight),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text(strings.themeDark),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(appPreferencesProvider.notifier).setThemeMode(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<MotionPreference>(
            initialValue: preferences.motionPreference,
            decoration: InputDecoration(labelText: strings.motion),
            items: [
              DropdownMenuItem(
                value: MotionPreference.system,
                child: Text(strings.motionSystem),
              ),
              DropdownMenuItem(
                value: MotionPreference.reduced,
                child: Text(strings.motionReduced),
              ),
              DropdownMenuItem(
                value: MotionPreference.full,
                child: Text(strings.motionFull),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(appPreferencesProvider.notifier)
                    .setMotionPreference(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: preferences.locale.languageCode,
            decoration: InputDecoration(labelText: strings.language),
            items: [
              DropdownMenuItem(value: 'en', child: Text(strings.english)),
            ],
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(appPreferencesProvider.notifier)
                    .setLocale(Locale(value));
              }
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.slideshow_outlined),
            label: Text(strings.viewOnboardingAgain),
            onPressed: () async {
              await ref
                  .read(appPreferencesProvider.notifier)
                  .showOnboardingAgain();
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
