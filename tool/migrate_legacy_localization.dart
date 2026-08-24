import 'dart:convert';
import 'dart:io';

void main() {
  final arbFile = File('lib/l10n/app_en.arb');
  final arb = (jsonDecode(arbFile.readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final valueToKey = <String, String>{
    for (final entry in arb.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        entry.value as String: entry.key,
  };
  final usedKeys = arb.keys.toSet();
  var changedFiles = 0;
  var addedStrings = 0;

  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    var source = entity.readAsStringSync();
    final original = source;

    String localize(String raw) {
      final value = _decode(raw);
      final existing = valueToKey[value];
      if (existing != null) return existing;
      var key = _keyFor(value);
      var suffix = 2;
      while (usedKeys.contains(key)) {
        key = '${_keyFor(value)}$suffix';
        suffix++;
      }
      usedKeys.add(key);
      valueToKey[value] = key;
      arb[key] = value;
      addedStrings++;
      return key;
    }

    source = source.replaceAllMapped(
      RegExp(r"(?:const\s+)?Text\(\s*'((?:\\.|[^'\\])*)'"),
      (match) {
        final raw = match.group(1)!;
        if (raw.contains(r'$')) return match.group(0)!;
        return 'Text(AppLocalizations.of(context).${localize(raw)}';
      },
    );
    source = source.replaceAllMapped(
      RegExp(r'(?:const\s+)?Text\(\s*"((?:\\.|[^"\\])*)"'),
      (match) {
        final raw = match.group(1)!;
        if (raw.contains(r'$')) return match.group(0)!;
        return 'Text(AppLocalizations.of(context).${localize(raw)}';
      },
    );

    for (final argument in [
      'tooltip',
      'labelText',
      'hintText',
      'helperText',
      'semanticLabel',
    ]) {
      source = source.replaceAllMapped(
        RegExp("($argument\\s*:\\s*)'((?:\\\\.|[^'\\\\])*)'"),
        (match) {
          final raw = match.group(2)!;
          if (raw.contains(r'$')) return match.group(0)!;
          return '${match.group(1)}AppLocalizations.of(context).${localize(raw)}';
        },
      );
      source = source.replaceAllMapped(
        RegExp('($argument\\s*:\\s*)"((?:\\\\.|[^"\\\\])*)"'),
        (match) {
          final raw = match.group(2)!;
          if (raw.contains(r'$')) return match.group(0)!;
          return '${match.group(1)}AppLocalizations.of(context).${localize(raw)}';
        },
      );
    }

    if (source == original) continue;
    if (!source.startsWith('part of ') &&
        !source.contains('package:schoolway/l10n/app_localizations.dart')) {
      source =
          "import 'package:schoolway/l10n/app_localizations.dart';\n$source";
    }
    entity.writeAsStringSync(source);
    changedFiles++;
  }

  // Admin tab files are parts and share their imports with AdminHome.
  final adminHome = File('lib/features/admin/admin_home.dart');
  var adminSource = adminHome.readAsStringSync();
  if (!adminSource.contains('package:schoolway/l10n/app_localizations.dart')) {
    adminSource =
        "import 'package:schoolway/l10n/app_localizations.dart';\n$adminSource";
    adminHome.writeAsStringSync(adminSource);
  }

  final sorted = <String, dynamic>{
    '@@locale': arb['@@locale'] ?? 'en',
    for (final key
        in arb.keys.where((key) => key != '@@locale').toList()..sort())
      key: arb[key],
  };
  arbFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
  stdout.writeln('Localized $addedStrings strings across $changedFiles files.');
}

String _decode(String raw) => raw
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\\', r'\');

String _keyFor(String value) {
  final words = RegExp(
    r'[A-Za-z0-9]+',
  ).allMatches(value).map((match) => match.group(0)!).take(7).toList();
  if (words.isEmpty) return 'legacyText';
  final first = words.first.toLowerCase();
  final rest = words
      .skip(1)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      );
  var key = '$first${rest.join()}';
  if (RegExp(r'^[0-9]').hasMatch(key)) key = 'text$key';
  if (_dartKeywords.contains(key)) key = '${key}Label';
  return key;
}

const _dartKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};
