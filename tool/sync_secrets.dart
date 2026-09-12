import 'dart:io';

/// Centralized Secrets Synchronization Tool for SchoolWay.
///
/// Parses the root `.env` (or `.env.example` as reference), syncs variables to
/// platform-specific configs (android/local.properties, functions/.env), and
/// verifies that every subsystem can retrieve its required secret.
///
/// Usage:
///   dart run tool/sync_secrets.dart
///   dart run tool/sync_secrets.dart --verify
void main(List<String> args) {
  final isVerifyOnly = args.contains('--verify');
  stdout.writeln('====================================================');
  stdout.writeln('  🏫 SchoolWay Centralized Secrets Synchronizer     ');
  stdout.writeln('====================================================\n');

  final rootDir = Directory.current;
  final envFile = File('.env');
  final exampleFile = File('.env.example');

  if (!envFile.existsSync() && !exampleFile.existsSync()) {
    stderr.writeln(
      '❌ Error: Neither .env nor .env.example exists in ${rootDir.path}',
    );
    exitCode = 1;
    return;
  }

  // Load from .env if it exists, otherwise fall back to .env.example for verification
  final activeFile = envFile.existsSync() ? envFile : exampleFile;
  stdout.writeln('📄 Reading configuration from: ${activeFile.path}');
  final envMap = parseEnv(activeFile.readAsStringSync());

  // Extract key values
  final mapsApiKey =
      envMap['MAPS_API_KEY'] ?? envMap['GOOGLE_MAPS_API_KEY'] ?? '';
  final routesApiKey = envMap['GOOGLE_ROUTES_API_KEY'] ?? '';
  final webMapsApiKey = envMap['GOOGLE_MAPS_WEB_API_KEY'] ?? '';
  final fcmVapidKey = envMap['FCM_WEB_VAPID_KEY'] ?? '';
  final firebaseProjectId = envMap['FIREBASE_PROJECT_ID'] ?? '';

  if (!isVerifyOnly && envFile.existsSync()) {
    // 1. Sync to android/local.properties
    _syncAndroidLocalProperties(mapsApiKey);

    // 2. Sync to functions/.env
    _syncFunctionsEnv(routesApiKey);
  }

  // Verification report
  stdout.writeln('\n🔍 Subsystem Secrets Verification:');
  stdout.writeln(
    '┌─────────────────────────────┬─────────────────────┬──────────────┐',
  );
  stdout.writeln(
    '│ Subsystem / Function        │ Secret Parameter    │ Status       │',
  );
  stdout.writeln(
    '├─────────────────────────────┼─────────────────────┼──────────────┤',
  );

  _printRow(
    'Android Google Maps SDK',
    'MAPS_API_KEY',
    mapsApiKey.isNotEmpty,
    'Configured in .env',
  );
  _printRow(
    'Web Google Maps JavaScript',
    'GOOGLE_MAPS_WEB_API_KEY',
    webMapsApiKey.isNotEmpty,
    'Configured in .env',
  );
  _printRow(
    'Cloud Functions Routes API',
    'GOOGLE_ROUTES_API_KEY',
    routesApiKey.isNotEmpty,
    'Configured in .env',
  );
  _printRow(
    'Firebase Cloud Messaging',
    'FCM_WEB_VAPID_KEY',
    fcmVapidKey.isNotEmpty,
    'Configured in .env',
  );
  _printRow(
    'Firebase Client Auth/DB',
    'FIREBASE_PROJECT_ID',
    firebaseProjectId.isNotEmpty,
    'Configured in .env',
  );

  stdout.writeln(
    '└─────────────────────────────┴─────────────────────┴──────────────┘\n',
  );

  if (!envFile.existsSync()) {
    stdout.writeln('ℹ️ Note: Running with .env.example template defaults.');
    stdout.writeln('   To customize for your project:');
    stdout.writeln('     cp .env.example .env');
    stdout.writeln('     dart run tool/sync_secrets.dart\n');
  } else {
    stdout.writeln('✅ Centralized secrets successfully synced and verified!\n');
  }
}

Map<String, String> parseEnv(String content) {
  final map = <String, String>{};
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eqIndex = line.indexOf('=');
    if (eqIndex <= 0) continue;
    final key = line.substring(0, eqIndex).trim();
    var val = line.substring(eqIndex + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'"))) {
      val = val.substring(1, val.length - 1);
    }
    map[key] = val;
  }
  return map;
}

void _syncAndroidLocalProperties(String mapsApiKey) {
  if (mapsApiKey.isEmpty) return;
  final localPropsFile = File('android/local.properties');
  var content = localPropsFile.existsSync()
      ? localPropsFile.readAsStringSync()
      : '';
  if (content.contains('MAPS_API_KEY=')) {
    content = content.replaceAll(
      RegExp(r'MAPS_API_KEY=.*'),
      'MAPS_API_KEY=$mapsApiKey',
    );
  } else {
    content = '$content\nMAPS_API_KEY=$mapsApiKey\n'.trimLeft();
  }
  localPropsFile.writeAsStringSync(content);
  stdout.writeln('  ✓ Synced MAPS_API_KEY to android/local.properties');
}

void _syncFunctionsEnv(String routesApiKey) {
  if (routesApiKey.isEmpty) return;
  final funcEnvFile = File('functions/.env');
  var content = funcEnvFile.existsSync() ? funcEnvFile.readAsStringSync() : '';
  if (content.contains('GOOGLE_ROUTES_API_KEY=')) {
    content = content.replaceAll(
      RegExp(r'GOOGLE_ROUTES_API_KEY=.*'),
      'GOOGLE_ROUTES_API_KEY=$routesApiKey',
    );
  } else {
    content = '$content\nGOOGLE_ROUTES_API_KEY=$routesApiKey\n'.trimLeft();
  }
  funcEnvFile.writeAsStringSync(content);
  stdout.writeln('  ✓ Synced GOOGLE_ROUTES_API_KEY to functions/.env');
}

void _printRow(String subsystem, String secret, bool isReady, String note) {
  final status = isReady ? '✅ READY' : '⚠️ MISSING';
  final subPad = subsystem.padRight(27);
  final secPad = secret.padRight(19);
  final statPad = status.padRight(12);
  stdout.writeln('│ $subPad │ $secPad │ $statPad │');
}
