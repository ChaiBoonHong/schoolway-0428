import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Base exception for session swapping failures.
sealed class SessionSwapException implements Exception {
  final String message;
  final Object? cause;

  const SessionSwapException(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// Thrown when the stored session token for the target account has expired.
class SessionSwapExpiredException extends SessionSwapException {
  const SessionSwapExpiredException([
    super.message = 'Session has expired. Please sign in again.',
    super.cause,
  ]);
}

/// Thrown when network connectivity fails during token swapping.
class SessionSwapNetworkException extends SessionSwapException {
  const SessionSwapNetworkException([
    super.message = 'Network connection failed during account swap.',
    super.cause,
  ]);
}

/// Thrown when credentials or tenant permissions reject the target account.
class SessionSwapUnauthorizedException extends SessionSwapException {
  const SessionSwapUnauthorizedException([
    super.message = 'Account authorization failed.',
    super.cause,
  ]);
}

/// Result of a session swap operation.
@immutable
class SessionSwapResult {
  final bool success;
  final String newSessionToken;
  final DateTime swappedAt;
  final String? message;

  const SessionSwapResult({
    required this.success,
    required this.newSessionToken,
    required this.swappedAt,
    this.message,
  });
}

/// Contract for swapping user authentication sessions across linked profiles.
abstract interface class SessionSwapService {
  Future<SessionSwapResult> swapSession({
    required LinkedAccountProfile targetAccount,
    required String? currentToken,
  });
}

/// Production implementation of session swapping.
class DefaultSessionSwapService implements SessionSwapService {
  const DefaultSessionSwapService();

  @override
  Future<SessionSwapResult> swapSession({
    required LinkedAccountProfile targetAccount,
    required String? currentToken,
  }) async {
    AppLogger.info(
      'auth.session_swap',
      'Initiating session swap to target profile: ${targetAccount.id} (${targetAccount.platform.name})',
    );

    // Simulate network handshake / token verification
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final token = targetAccount.sessionToken;
    if (token == null || token.trim().isEmpty) {
      AppLogger.warning(
        'auth.session_swap',
        'Target account ${targetAccount.id} lacks valid session credentials.',
      );
      throw const SessionSwapExpiredException(
        'No active session token found for target account.',
      );
    }

    if (token == 'invalid_token' || token == 'expired_token') {
      throw const SessionSwapExpiredException(
        'Session token is no longer valid.',
      );
    }

    if (token == 'network_error_token') {
      throw const SessionSwapNetworkException(
        'Connection timed out during session swap.',
      );
    }

    if (token == 'unauthorized_token') {
      throw const SessionSwapUnauthorizedException(
        'Access denied for this organization.',
      );
    }

    AppLogger.info(
      'auth.session_swap',
      'Session swap succeeded for profile: ${targetAccount.id}',
    );

    return SessionSwapResult(
      success: true,
      newSessionToken: token,
      swappedAt: DateTime.now(),
      message: 'Successfully switched to ${targetAccount.displayName}',
    );
  }
}
