import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/features/auth/auth_service.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Base exception for session swapping failures.
sealed class SessionSwapException implements Exception {
  final String message;
  final Object? cause;

  const SessionSwapException(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// Thrown when the stored session token for the target account has expired or credentials missing.
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
    String? password,
  });
}

/// Production implementation of session swapping with Firebase Auth & Google Sign-In.
class DefaultSessionSwapService implements SessionSwapService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  DefaultSessionSwapService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  @override
  Future<SessionSwapResult> swapSession({
    required LinkedAccountProfile targetAccount,
    required String? currentToken,
    String? password,
  }) async {
    AppLogger.info(
      'auth.session_swap',
      'Initiating session swap to target profile: ${targetAccount.id} (${targetAccount.platform.name})',
    );

    try {
      if (targetAccount.platform == AccountPlatform.google) {
        final authService = AuthService(_auth, _googleSignIn);
        final cred = await authService.signInWithGoogle();
        final user = cred.user;
        if (user == null) {
          throw const SessionSwapExpiredException(
            'Google sign-in returned no user.',
          );
        }
        return SessionSwapResult(
          success: true,
          newSessionToken: 'session_${user.uid}',
          swappedAt: DateTime.now(),
          message: 'Switched to Google account',
        );
      } else {
        if (password == null || password.isEmpty) {
          throw const SessionSwapExpiredException(
            'Password required to authenticate account switch.',
          );
        }
        final cred = await _auth.signInWithEmailAndPassword(
          email: targetAccount.email,
          password: password,
        );
        final user = cred.user;
        if (user == null) {
          throw const SessionSwapExpiredException(
            'Authentication returned no user.',
          );
        }
        return SessionSwapResult(
          success: true,
          newSessionToken: 'session_${user.uid}',
          swappedAt: DateTime.now(),
          message: 'Switched to ${targetAccount.displayName}',
        );
      }
    } on FirebaseAuthException catch (e, st) {
      AppLogger.warning(
        'auth.session_swap',
        'Firebase Auth error during swap',
        error: e,
        stackTrace: st,
      );
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw SessionSwapUnauthorizedException('Incorrect password.', e);
      } else if (e.code == 'network-request-failed') {
        throw SessionSwapNetworkException(
          'Network connection failed. Please check your connection.',
          e,
        );
      } else {
        throw SessionSwapExpiredException(e.message ?? 'Sign-in failed.', e);
      }
    } catch (e, st) {
      AppLogger.error(
        'auth.session_swap',
        'Unexpected session swap exception',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }
}
