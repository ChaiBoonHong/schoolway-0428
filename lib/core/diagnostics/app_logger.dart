import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'diagnostic_event.dart';
import 'diagnostic_store.dart';

abstract final class AppLogger {
  static const maximumMemoryEvents = 100;
  static final DiagnosticStore _store = createDiagnosticStore();
  static final List<String> _memoryFallback = [];
  static final String _sessionId = _randomId('SESSION', 8);
  static Future<void> _pending = Future.value();
  static String _appVersion = 'unknown';
  static String? _latestIncidentId;
  static bool _initialized = false;
  static bool _handlingFailure = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final package = await PackageInfo.fromPlatform();
      _appVersion = '${package.version}+${package.buildNumber}';
      await _store.initialize();
      _initialized = true;
      info('lifecycle', 'Diagnostic logging initialized.');
    } catch (error, stackTrace) {
      _fallback('Logger initialization failed', error, stackTrace);
    }
  }

  static void debug(String category, String message) =>
      _record(AppLogLevel.debug, category, message);

  static void info(String category, String message) =>
      _record(AppLogLevel.info, category, message);

  static void warning(
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _record(
    AppLogLevel.warning,
    category,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  static String error(
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final incidentId = _randomId('SW', 6);
    _latestIncidentId = incidentId;
    _record(
      AppLogLevel.error,
      category,
      message,
      error: error,
      stackTrace: stackTrace,
      incidentId: incidentId,
    );
    return incidentId;
  }

  static String fatal(
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final incidentId = _randomId('SW', 6);
    _latestIncidentId = incidentId;
    _record(
      AppLogLevel.fatal,
      category,
      message,
      error: error,
      stackTrace: stackTrace,
      incidentId: incidentId,
    );
    return incidentId;
  }

  static void _record(
    AppLogLevel level,
    String category,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? incidentId,
  }) {
    final event = DiagnosticEvent(
      timestamp: DateTime.now().toUtc(),
      level: level,
      category: DiagnosticRedactor.sanitize(category),
      message: DiagnosticRedactor.sanitize(message),
      sessionId: _sessionId,
      appVersion: _appVersion,
      platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      incidentId: incidentId,
      errorType: error?.runtimeType.toString(),
      stackTrace: stackTrace == null
          ? null
          : DiagnosticRedactor.sanitize(
              stackTrace.toString(),
              maximumLength: 12000,
            ),
    );
    final line = event.toJsonLine();
    _pending = _pending.then((_) async {
      try {
        await _store.append(line);
      } catch (writeError, writeStack) {
        _memoryFallback.add(line);
        if (_memoryFallback.length > maximumMemoryEvents) {
          _memoryFallback.removeAt(0);
        }
        _fallback('Diagnostic write failed', writeError, writeStack);
      }
    });
  }

  static Future<String> read() async {
    await _pending;
    var persisted = '';
    if (_initialized) {
      try {
        persisted = await _store.read();
      } catch (error, stackTrace) {
        _fallback('Diagnostic read failed', error, stackTrace);
      }
    }
    return [
      persisted.trim(),
      ..._memoryFallback,
    ].where((part) => part.isNotEmpty).join('\n');
  }

  static Future<String?> export() async {
    final content = await read();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    if (!_initialized) return null;
    try {
      return await _store.export(
        content,
        'schoolway-diagnostics-$timestamp.jsonl',
      );
    } catch (error, stackTrace) {
      _fallback('Diagnostic export failed', error, stackTrace);
      return null;
    }
  }

  static Future<void> clear() async {
    await _pending;
    if (_initialized) {
      try {
        await _store.clear();
      } catch (error, stackTrace) {
        _fallback('Diagnostic clear failed', error, stackTrace);
      }
    }
    _memoryFallback.clear();
    _latestIncidentId = null;
  }

  static Future<DiagnosticSummary> summary() async {
    final content = await read();
    final bytes = utf8.encode(content).length;
    DateTime? oldest;
    DateTime? newest;
    String? latestPersistedIncident;
    var count = 0;
    for (final line in const LineSplitter().convert(content)) {
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final timestamp = DateTime.parse(json['timestamp'] as String);
        oldest = oldest == null || timestamp.isBefore(oldest)
            ? timestamp
            : oldest;
        newest = newest == null || timestamp.isAfter(newest)
            ? timestamp
            : newest;
        final incident = json['incidentId'] as String?;
        if (incident != null && incident.isNotEmpty) {
          latestPersistedIncident = incident;
        }
        count++;
      } catch (_) {
        // Invalid diagnostic lines are ignored and never re-exported as events.
      }
    }
    return DiagnosticSummary(
      bytes: bytes,
      eventCount: count,
      oldest: oldest,
      newest: newest,
      latestIncidentId: _latestIncidentId ?? latestPersistedIncident,
    );
  }

  static String _randomId(String prefix, int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final value = List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return '$prefix-$value';
  }

  static void _fallback(String message, Object error, StackTrace stackTrace) {
    if (_handlingFailure) return;
    _handlingFailure = true;
    debugPrint('$message: ${error.runtimeType}');
    debugPrintStack(stackTrace: stackTrace);
    _handlingFailure = false;
  }
}

abstract final class DiagnosticRedactor {
  static String sanitize(String input, {int maximumLength = 4000}) {
    var value = input;
    value = value.replaceAll(
      RegExp(
        r'(password|passwd|secret|token|authorization|api[_-]?key)\s*[:=]\s*[^\s,;}]+',
        caseSensitive: false,
      ),
      r'$1=[REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'bearer\s+[a-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
      '[REDACTED_EMAIL]',
    );
    value = value.replaceAll(
      RegExp(r'(?<![A-Za-z0-9])\+?\d[\d\s().-]{7,}\d'),
      '[REDACTED_NUMBER]',
    );
    value = value.replaceAll(
      RegExp(r'(?<!\d)-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}(?!\d)'),
      '[REDACTED_LOCATION]',
    );
    value = value.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
      '[REDACTED_JWT]',
    );
    value = value.replaceAll(
      RegExp(r'\b(?:STU[-_][A-Za-z0-9-]+|[A-Za-z0-9_-]{80,})\b'),
      '[REDACTED_ID]',
    );
    return value.length <= maximumLength
        ? value
        : '${value.substring(0, maximumLength)}...[TRUNCATED]';
  }
}
