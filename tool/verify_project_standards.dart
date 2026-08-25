import 'dart:io';

const contractVersion = '1';

const requiredInstructionFiles = <String>[
  'AGENTS.md',
  'lib/AGENTS.md',
  'functions/AGENTS.md',
  'test/AGENTS.md',
  'CLAUDE.md',
  'GEMINI.md',
  '.github/copilot-instructions.md',
  '.cursor/rules/schoolway.mdc',
  '.windsurf/rules/schoolway.md',
];

const requiredTemplates = <String>[
  '.ai/templates/ui-change.md',
  '.ai/templates/feature-implementation.md',
  '.ai/templates/bug-fix.md',
  '.ai/templates/security-change.md',
  '.ai/templates/data-migration.md',
];

const permanentColorFiles = <String>{
  'lib/core/theme/schoolway_theme.dart',
  'lib/core/fleet_bus_colors.dart',
  'lib/core/fleet_bus_position.dart',
  'lib/core/map/map_markers.dart',
};

void main() {
  final failures = <String>[];
  final root = Directory.current;

  for (final path in [...requiredInstructionFiles, ...requiredTemplates]) {
    if (!File(path).existsSync()) failures.add('Missing required file: $path');
  }

  for (final path in requiredInstructionFiles) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final marker = 'Agent-Contract-Version: $contractVersion';
    if (!file.readAsStringSync().contains(marker)) {
      failures.add('$path does not declare $marker');
    }
  }

  const forbiddenSecretFiles = <String>[
    'functions/serviceAccountKey.json',
    'serviceAccountKey.json',
  ];
  for (final path in forbiddenSecretFiles) {
    if (File(path).existsSync()) {
      failures.add('Forbidden credential file: $path');
    }
  }

  final allowlist = File('tool/standards_allowlist.txt')
      .readAsLinesSync()
      .map((line) => line.trim().replaceAll('\\', '/'))
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toSet();

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    if (_ignored(path)) continue;

    final lower = path.toLowerCase();
    if (lower.endsWith('.json') ||
        lower.endsWith('.js') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.md')) {
      final content = entity.readAsStringSync();
      if (path != 'tool/verify_project_standards.dart' &&
          (content.contains('-----BEGIN PRIVATE KEY-----') ||
              RegExp(r'"private_key"\s*:').hasMatch(content))) {
        failures.add('Private-key material detected in $path');
      }

      if (path.startsWith('lib/') && path.endsWith('.dart')) {
        if (path != 'lib/core/diagnostics/app_logger.dart' &&
            RegExp(
              r'\b(?:debugPrint|debugPrintStack|print)\s*\(',
            ).hasMatch(content)) {
          failures.add('Direct console logging outside AppLogger: $path');
        }
        if (RegExp(
          r'catch\s*\([^)]*\)\s*\{\s*\}',
          multiLine: true,
        ).hasMatch(content)) {
          failures.add('Empty catch block detected: $path');
        }
        if (RegExp(
          r'''Text\([^\n]*(?:\$e\b|\$error\b)|(?:_error|error|message|msg)\s*=\s*[^;]*(?:e|error)\.toString\(\)''',
          multiLine: true,
        ).hasMatch(content)) {
          failures.add('Raw exception text may reach the UI: $path');
        }
        if (RegExp(
          r'''AppLogger\.(?:debug|info|warning|error|fatal)\([\s\S]{0,400}\$(?:password|token|email|phone|name|studentId|latitude|longitude)\b''',
        ).hasMatch(content)) {
          failures.add('Sensitive value interpolated into diagnostics: $path');
        }
        final permanent = permanentColorFiles.contains(path);
        final legacy = allowlist.contains(path);
        if (!permanent &&
            !legacy &&
            RegExp(r'Color\(0x|Colors\.').hasMatch(content)) {
          failures.add('Theme-bypassing color in new UI file: $path');
        }
        if (path.startsWith('lib/features/') &&
            !legacy &&
            RegExp(
              r'''Text\(\s*(?:const\s+)?[\'\"][^\$\'\"]*[\'\"]''',
              multiLine: true,
            ).hasMatch(content)) {
          failures.add(
            'Unlocalized user-facing Text in new feature file: $path',
          );
        }
      }
    }
  }

  final manifest = File('web/manifest.json');
  if (!manifest.existsSync()) {
    failures.add('Missing web/manifest.json');
  } else {
    final content = manifest.readAsStringSync();
    if (content.contains('A new Flutter project') ||
        !content.contains('"short_name": "SchoolWay"')) {
      failures.add(
        'PWA manifest contains placeholder or inconsistent branding',
      );
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Project standards verification failed:');
    for (final failure in failures) {
      stderr.writeln(' - $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Project standards verified (Agent Contract v$contractVersion).',
  );
}

bool _ignored(String path) {
  const ignoredRoots = <String>[
    '.git/',
    '.dart_tool/',
    'build/',
    'coverage/',
    'functions/node_modules/',
    '.idea/',
  ];
  return ignoredRoots.any(path.startsWith);
}
