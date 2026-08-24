import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:schoolway/l10n/app_localizations.dart';

import 'app_failure.dart';
import 'app_failure_localization.dart';
import 'app_logger.dart';

abstract final class ErrorReporter {
  static String userMessage(
    BuildContext context,
    Object error,
    StackTrace stackTrace, {
    required String category,
    String message = 'Operation failed.',
    AppFailureCategory? hint,
  }) {
    final failure = capture(
      error,
      stackTrace,
      category: category,
      message: message,
      hint: hint,
    );
    final strings = AppLocalizations.of(context);
    final localized = failure.localizedMessage(strings);
    if (failure.category != AppFailureCategory.unknown ||
        failure.incidentId == null) {
      return localized;
    }
    return '$localized ${strings.errorReference(failure.incidentId!)}';
  }

  static AppFailure capture(
    Object error,
    StackTrace stackTrace, {
    required String category,
    String message = 'Operation failed.',
    AppFailureCategory? hint,
  }) {
    final mapped = AppFailureMapper.from(error, hint: hint);
    final incident = AppLogger.error(
      category,
      message,
      error: error,
      stackTrace: stackTrace,
    );
    return mapped.withIncident(incident);
  }

  static Future<T?> guard<T>(
    Future<T> Function() operation, {
    required String category,
    String message = 'Operation failed.',
    AppFailureCategory? hint,
    void Function(AppFailure failure)? onFailure,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      final failure = capture(
        error,
        stackTrace,
        category: category,
        message: message,
        hint: hint,
      );
      onFailure?.call(failure);
      return null;
    }
  }

  static Stream<T> guardStream<T>(
    Stream<T> source, {
    required String category,
    String message = 'Stream failed.',
  }) => source.handleError((Object error, StackTrace stackTrace) {
    capture(error, stackTrace, category: category, message: message);
  });

  static Future<T> retryTransient<T>(
    Future<T> Function() operation, {
    int maximumAttempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        final failure = AppFailureMapper.from(error);
        if (!failure.retryable || attempt == maximumAttempts) rethrow;
        lastError = error;
        lastStack = stackTrace;
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (1 << (attempt - 1))),
        );
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }
}
