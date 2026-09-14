import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/diagnostics/app_failure.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/diagnostic_retention.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';

void main() {
  group('DiagnosticRedactor', () {
    test('removes prohibited sensitive patterns', () {
      final input = [
        'email parent@example.com',
        'password=hunter2',
        'token=abc123',
        'Authorization: Bearer abc.def.ghi',
        'phone +60 12-345 6789',
        'location 3.139000, 101.686900',
        'student STU-12345',
      ].join(' ');

      final result = DiagnosticRedactor.sanitize(input);

      expect(result, isNot(contains('parent@example.com')));
      expect(result, isNot(contains('hunter2')));
      expect(result, isNot(contains('abc123')));
      expect(result, isNot(contains('+60 12-345 6789')));
      expect(result, isNot(contains('3.139000, 101.686900')));
      expect(result, isNot(contains('STU-12345')));
    });

    test('bounds persisted text', () {
      expect(
        DiagnosticRedactor.sanitize(
          'ordinary diagnostic message',
          maximumLength: 10,
        ),
        'ordinary d...[TRUNCATED]',
      );
    });
  });

  group('diagnostic retention', () {
    test('expires old and malformed events', () {
      final now = DateTime.utc(2026, 8, 24);
      final content = [
        '{"timestamp":"2026-08-01T00:00:00.000Z","message":"old"}',
        'malformed',
        '{"timestamp":"2026-08-23T00:00:00.000Z","message":"new"}',
      ].join('\n');

      final result = retainDiagnosticLines(
        content,
        now: now,
        maximumAge: const Duration(days: 7),
        maximumBytes: 1024,
      );

      expect(result, contains('"new"'));
      expect(result, isNot(contains('"old"')));
      expect(result, isNot(contains('malformed')));
    });

    test('removes oldest events first to enforce byte limit', () {
      final content = [
        '{"timestamp":"2026-08-22T00:00:00.000Z","message":"first"}',
        '{"timestamp":"2026-08-23T00:00:00.000Z","message":"second"}',
      ].join('\n');

      final result = retainDiagnosticLines(
        content,
        now: DateTime.utc(2026, 8, 24),
        maximumAge: const Duration(days: 7),
        maximumBytes: 70,
      );

      expect(result, isNot(contains('first')));
      expect(result, contains('second'));
    });
  });

  group('AppFailureMapper', () {
    test('classifies authorization without retry', () {
      final failure = AppFailureMapper.from(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );
      expect(failure.category, AppFailureCategory.authorization);
      expect(failure.retryable, isFalse);
    });

    test('classifies timeouts as retryable', () {
      final failure = AppFailureMapper.from(TimeoutException('timeout'));
      expect(failure.category, AppFailureCategory.timeout);
      expect(failure.retryable, isTrue);
    });

    test(
      'classifies location-related failed-precondition as location error',
      () {
        final failure = AppFailureMapper.from(
          FirebaseException(
            plugin: 'cloud_functions',
            code: 'failed-precondition',
            message: 'The attendance GPS fix is stale.',
          ),
        );
        expect(failure.category, AppFailureCategory.location);
        expect(failure.retryable, isFalse);
      },
    );

    test('classifies accuracy invalid-argument as location error', () {
      final failure = AppFailureMapper.from(
        FirebaseException(
          plugin: 'cloud_functions',
          code: 'invalid-argument',
          message: 'accuracy is invalid.',
        ),
      );
      expect(failure.category, AppFailureCategory.location);
      expect(failure.retryable, isFalse);
    });

    test('classifies other invalid-argument as validation error', () {
      final failure = AppFailureMapper.from(
        FirebaseException(
          plugin: 'cloud_functions',
          code: 'invalid-argument',
          message: 'studentId is invalid.',
        ),
      );
      expect(failure.category, AppFailureCategory.validation);
      expect(failure.retryable, isFalse);
    });
  });

  test('transient retry is capped and succeeds', () async {
    var attempts = 0;
    final result = await ErrorReporter.retryTransient(() async {
      attempts++;
      if (attempts < 3) throw TimeoutException('temporary');
      return 'done';
    });
    expect(result, 'done');
    expect(attempts, 3);
  });
}
