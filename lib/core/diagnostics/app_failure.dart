import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import 'failure_platform.dart';

enum AppFailureCategory {
  authentication,
  authorization,
  validation,
  network,
  timeout,
  unavailable,
  storage,
  location,
  nfc,
  notification,
  conflict,
  notFound,
  unknown,
}

class AppFailure {
  const AppFailure({
    required this.category,
    required this.messageKey,
    required this.retryable,
    this.incidentId,
  });

  final AppFailureCategory category;
  final String messageKey;
  final bool retryable;
  final String? incidentId;

  AppFailure withIncident(String id) => AppFailure(
    category: category,
    messageKey: messageKey,
    retryable: retryable,
    incidentId: id,
  );
}

abstract final class AppFailureMapper {
  static AppFailure from(Object error, {AppFailureCategory? hint}) {
    if (error is FirebaseAuthException) {
      if (error.code == 'network-request-failed') return _network;
      if (error.code == 'too-many-requests') return _unavailable;
      if (error.code == 'user-disabled' ||
          error.code == 'invalid-credential' ||
          error.code == 'wrong-password' ||
          error.code == 'user-not-found' ||
          error.code == 'requires-recent-login') {
        return const AppFailure(
          category: AppFailureCategory.authentication,
          messageKey: 'authentication',
          retryable: false,
        );
      }
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
        case 'unauthenticated':
          return const AppFailure(
            category: AppFailureCategory.authorization,
            messageKey: 'authorization',
            retryable: false,
          );
        case 'unavailable':
        case 'resource-exhausted':
          return _unavailable;
        case 'deadline-exceeded':
          return _timeout;
        case 'not-found':
          return const AppFailure(
            category: AppFailureCategory.notFound,
            messageKey: 'notFound',
            retryable: false,
          );
        case 'already-exists':
          return const AppFailure(
            category: AppFailureCategory.conflict,
            messageKey: 'conflict',
            retryable: false,
          );
      }
    }
    if (error is TimeoutException) return _timeout;
    if (isNetworkFailure(error)) return _network;
    if (isStorageFailure(error)) {
      return const AppFailure(
        category: AppFailureCategory.storage,
        messageKey: 'storage',
        retryable: false,
      );
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('permission')) {
        return const AppFailure(
          category: AppFailureCategory.authorization,
          messageKey: 'authorization',
          retryable: false,
        );
      }
      if (code.contains('nfc')) {
        return const AppFailure(
          category: AppFailureCategory.nfc,
          messageKey: 'nfc',
          retryable: false,
        );
      }
      if (code.contains('location')) {
        return const AppFailure(
          category: AppFailureCategory.location,
          messageKey: 'location',
          retryable: false,
        );
      }
    }
    if (error is FormatException || error is ArgumentError) {
      return const AppFailure(
        category: AppFailureCategory.validation,
        messageKey: 'validation',
        retryable: false,
      );
    }
    return AppFailure(
      category: hint ?? AppFailureCategory.unknown,
      messageKey: hint?.name ?? 'unknown',
      retryable:
          hint == AppFailureCategory.network ||
          hint == AppFailureCategory.timeout ||
          hint == AppFailureCategory.unavailable,
    );
  }

  static const _network = AppFailure(
    category: AppFailureCategory.network,
    messageKey: 'network',
    retryable: true,
  );
  static const _timeout = AppFailure(
    category: AppFailureCategory.timeout,
    messageKey: 'timeout',
    retryable: true,
  );
  static const _unavailable = AppFailure(
    category: AppFailureCategory.unavailable,
    messageKey: 'unavailable',
    retryable: true,
  );
}
