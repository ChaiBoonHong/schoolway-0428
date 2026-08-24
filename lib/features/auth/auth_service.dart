import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

class AuthService {
  AuthService(this._auth, this._googleSignIn);

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  static Future<void>? _googleInitFuture;

  Future<void> _ensureGoogleInitialized() {
    return _googleInitFuture ??= _googleSignIn.initialize();
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final UserCredential cred;
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        cred = await _auth.signInWithPopup(provider);
      } else {
        await _ensureGoogleInitialized();
        final googleUser = await _googleSignIn.authenticate();

        final googleAuth = googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        cred = await _auth.signInWithCredential(credential);
      }

      // Authenticate first so Firestore reads are authorized by rules
      final newUser = cred.user;
      if (newUser == null) {
        throw FirebaseAuthException(
          code: 'no-current-user',
          message: 'Google sign-in returned no user',
        );
      }

      final profile = await swFirestore
          .collection('users')
          .doc(newUser.uid)
          .get();
      if (profile.exists) {
        await swFirestore.collection('users').doc(newUser.uid).update({
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
      }
      // If no document exists, the user will be directed to profile completion screen

      return cred;
    } on FirebaseAuthException catch (e) {
      // If account exists with different provider, handle error
      if (e.code == 'account-exists-with-different-credential') {
        throw FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          message:
              'An account with this email already exists. Please sign in with your email/password first, then link Google in settings.',
        );
      }
      rethrow;
    }
  }

  Future<UserCredential> linkCurrentUserWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user',
      );
    }
    final alreadyLinked = user.providerData.any(
      (p) => p.providerId == 'google.com',
    );
    if (alreadyLinked) {
      throw FirebaseAuthException(
        code: 'provider-already-linked',
        message: 'Google account is already linked.',
      );
    }

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      return user.linkWithPopup(provider);
    }

    await _ensureGoogleInitialized();
    final googleUser = await _googleSignIn.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return user.linkWithCredential(credential);
  }

  Future<void> unlinkCurrentUserFromGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user',
      );
    }
    final hasGoogle = user.providerData.any(
      (p) => p.providerId == 'google.com',
    );
    if (!hasGoogle) {
      throw FirebaseAuthException(
        code: 'no-such-provider',
        message: 'Google account is not linked.',
      );
    }
    final hasPassword = user.providerData.any(
      (p) => p.providerId == 'password',
    );
    final hasAnotherProvider = user.providerData.any(
      (p) => p.providerId != 'google.com',
    );
    if (!hasPassword && !hasAnotherProvider) {
      throw FirebaseAuthException(
        code: 'requires-alternative-signin',
        message:
            'Set a password or another sign-in method before unlinking Google.',
      );
    }
    await user.unlink('google.com');
    if (!kIsWeb) {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _ensureGoogleInitialized();
    await _googleSignIn.signOut();
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> sendPasswordReset({required String email}) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> updateEmailWithReauth({
    required String currentEmail,
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: currentEmail,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.verifyBeforeUpdateEmail(newEmail);
  }
}
