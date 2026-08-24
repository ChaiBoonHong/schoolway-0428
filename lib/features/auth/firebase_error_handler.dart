import 'package:firebase_auth/firebase_auth.dart';

/// Utility class for handling Firebase and Firestore errors with user-friendly messages
class FirebaseErrorHandler {
  /// Get user-friendly error message from Firebase Auth exceptions
  static String getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      // Authentication errors
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'The email or password you entered is incorrect. Please check your credentials and try again.';

      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';

      case 'too-many-requests':
        return 'Too many failed sign-in attempts. Please try again later.';

      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';

      // Email/Password errors
      case 'email-already-in-use':
        return 'An account with this email already exists.';

      case 'weak-password':
        return 'The password is too weak. Please use a stronger password.';

      case 'invalid-email':
        return 'The email address is invalid. Please check and try again.';

      case 'requires-recent-login':
        return 'Please sign in again to complete this action.';

      // Network errors
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';

      // Account linking errors
      case 'account-exists-with-different-credential':
        return 'An account with this email already exists with a different sign-in method. Please use the original sign-in method.';

      case 'credential-already-in-use':
        return 'This account is already linked to another user.';

      // Provider errors
      case 'invalid-verification-code':
        return 'The verification code is invalid. Please try again.';

      case 'invalid-verification-id':
        return 'The verification ID is invalid. Please request a new code.';

      // Session/Token errors
      case 'session-expired':
        return 'Your session has expired. Please sign in again.';

      case 'invalid-id-token':
        return 'Invalid authentication token. Please sign in again.';

      // Quota errors
      case 'quota-exceeded':
        return 'Service quota exceeded. Please try again later.';

      // App configuration errors
      case 'app-not-authorized':
        return 'App not authorized. Please contact support.';

      case 'invalid-api-key':
        return 'Invalid API key configuration. Please contact support.';

      // Default case - check message for common patterns
      default:
        final defaultMessage = e.message ?? e.code;
        final lowerMessage = defaultMessage.toLowerCase();

        if (lowerMessage.contains('incorrect') ||
            lowerMessage.contains('malformed') ||
            lowerMessage.contains('expired')) {
          return 'The email or password you entered is incorrect. Please check your credentials and try again.';
        } else if (lowerMessage.contains('network') ||
            lowerMessage.contains('connection')) {
          return 'Network error. Please check your internet connection and try again.';
        } else if (lowerMessage.contains('timeout')) {
          return 'Request timed out. Please check your internet connection and try again.';
        } else if (lowerMessage.contains('permission') ||
            lowerMessage.contains('denied')) {
          return 'Permission denied. Please contact support if this persists.';
        }

        return 'Sign in failed. $defaultMessage';
    }
  }

  /// Get user-friendly error message from Firestore exceptions
  static String getFirestoreErrorMessage(FirebaseException e) {
    switch (e.code) {
      // Permission errors
      case 'permission-denied':
        return 'Permission denied. You do not have access to perform this operation.';

      // Data errors
      case 'not-found':
        return 'The requested data was not found.';

      case 'already-exists':
        return 'This data already exists.';

      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('index')) {
          return 'Database index is missing or still building. '
              'Deploy Firestore indexes (firebase deploy) or use the link in the Firebase console, then retry.';
        }
        return 'Operation failed due to a precondition. Please try again.';

      case 'aborted':
        return 'Operation was aborted. Please try again.';

      // Resource errors
      case 'out-of-range':
        return 'The operation is out of range. Please contact support.';

      case 'unimplemented':
        return 'This operation is not implemented. Please contact support.';

      case 'internal':
        return 'An internal error occurred. Please try again later.';

      // Network errors
      case 'unavailable':
        return 'Service is temporarily unavailable. Please try again later.';

      case 'deadline-exceeded':
        return 'Request timed out. Please check your internet connection and try again.';

      case 'resource-exhausted':
        return 'Service resources are exhausted. Please try again later.';

      // Authentication errors
      case 'unauthenticated':
        return 'Authentication required. Please sign in again.';

      // Quota errors
      case 'quota-exceeded':
        return 'Service quota exceeded. Please try again later.';

      // Default case
      default:
        final defaultMessage = e.message ?? e.code;
        final lowerMessage = defaultMessage.toLowerCase();

        if (lowerMessage.contains('network') ||
            lowerMessage.contains('connection')) {
          return 'Network error. Please check your internet connection and try again.';
        } else if (lowerMessage.contains('timeout')) {
          return 'Request timed out. Please check your internet connection and try again.';
        } else if (lowerMessage.contains('permission') ||
            lowerMessage.contains('denied')) {
          return 'Permission denied. Please contact support if this persists.';
        }

        return 'Database error. $defaultMessage';
    }
  }
}
