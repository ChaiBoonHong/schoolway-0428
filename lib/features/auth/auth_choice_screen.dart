import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

import 'auth_service.dart';
import 'sign_in_screen.dart';
import 'google_profile_completion_screen.dart';
import 'firebase_error_handler.dart';
import '../../app.dart';

class AuthChoiceScreen extends StatefulWidget {
  const AuthChoiceScreen({super.key});

  static const routeName = '/auth-choice';

  @override
  State<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends State<AuthChoiceScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _onGoogleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      final cred = await service.signInWithGoogle();
      final user = cred.user;
      if (user != null) {
        try {
          await user.reload();
        } on FirebaseAuthException catch (e) {
          if (mounted) {
            setState(
              () =>
                  _error = FirebaseErrorHandler.getFirebaseAuthErrorMessage(e),
            );
          }
          return;
        } catch (e) {
          if (mounted) {
            setState(
              () => _error =
                  'Failed to reload user information. Please try again.',
            );
          }
          return;
        }

        String? firstName;
        String? lastName;

        String? username;
        Map<String, dynamic> data = {};
        try {
          final profile = await swFirestore
              .collection('users')
              .doc(user.uid)
              .get();
          if (profile.exists) {
            data = profile.data()!;
            username = data['username'] as String?;
          }
        } on FirebaseException catch (e) {
          if (mounted) {
            setState(
              () => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e),
            );
          }
          return;
        } catch (e) {
          if (mounted) {
            setState(
              () => _error = 'Failed to load user data. Please try again.',
            );
          }
          return;
        }

        // Check existing values to preserve user-edited names
        final existingFirstName = data['firstName'] as String?;
        final existingLastName = data['lastName'] as String?;
        final hasExistingFirstName =
            existingFirstName != null && existingFirstName.isNotEmpty;
        final hasExistingLastName =
            existingLastName != null && existingLastName.isNotEmpty;

        if (user.displayName != null && user.displayName!.isNotEmpty) {
          final parts = user.displayName!.trim().split(' ');
          if (parts.isNotEmpty) {
            firstName = parts.first;
            lastName = parts.length > 1 ? parts.sublist(1).join(' ') : null;
          }
        }

        // If user exists (has username), update their data
        if (username != null) {
          final update = <String, dynamic>{
            'email': user.email,
            'lastLoginAt': FieldValue.serverTimestamp(),
          };
          // Only set firstName/lastName if they don't already exist (preserve user-edited names)
          if (firstName != null &&
              firstName.isNotEmpty &&
              !hasExistingFirstName) {
            update['firstName'] = firstName;
          }
          if (lastName != null && lastName.isNotEmpty && !hasExistingLastName) {
            update['lastName'] = lastName;
          }
          if (user.emailVerified) {
            update['emailVerified'] = true;
          }

          try {
            await swFirestore
                .collection('users')
                .doc(user.uid)
                .set(update, SetOptions(merge: true));
          } on FirebaseException catch (e) {
            if (mounted) {
              setState(
                () => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e),
              );
            }
            return;
          } catch (e) {
            if (mounted) {
              setState(
                () => _error = 'Failed to save user data. Please try again.',
              );
            }
            return;
          }

          // Reload user data
          try {
            final doc = await swFirestore
                .collection('users')
                .doc(user.uid)
                .get();
            data = doc.data() ?? {};
          } on FirebaseException catch (e) {
            if (mounted) {
              setState(
                () => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e),
              );
            }
            return;
          } catch (e) {
            if (mounted) {
              setState(
                () => _error = 'Failed to load user data. Please try again.',
              );
            }
            return;
          }
        }

        if (username == null || username.isEmpty) {
          try {
            await FirebaseAuth.instance.signOut();
          } on FirebaseAuthException catch (e) {
            debugPrint('Error during sign out: ${e.message}');
          } catch (e) {
            debugPrint('Error during sign out: $e');
          }
          if (mounted) {
            setState(
              () => _error =
                  'No account was found for this Google login. Please contact admin to get your account.',
            );
          }
          return;
        }

        final phoneNumber = (data['phoneNumber'] as String?) ?? '';
        final countryCode = (data['countryCode'] as String?) ?? '+60';
        final gender = data['gender'] as String?;
        final birthdayTs = data['birthday'] as Timestamp?;
        final birthday = birthdayTs?.toDate();

        if (!mounted) return;
        final missingPhone = phoneNumber.isEmpty;
        final missingGender = (gender == null || gender.isEmpty);
        final missingBirthday = (birthday == null);
        if (missingPhone || missingGender || missingBirthday) {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => GoogleProfileCompletionScreen(
                userId: user.uid,
                existingPhoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
                existingCountryCode: countryCode,
                existingGender: gender,
                existingBirthday: birthday,
                existingUsername: username,
              ),
            ),
          );
          if (result != true) {
            try {
              await FirebaseAuth.instance.signOut();
            } on FirebaseAuthException catch (e) {
              // Log error but continue with sign-out flow
              debugPrint('Error during sign out: ${e.message}');
            } catch (e) {
              // Log error but continue with sign-out flow
              debugPrint('Error during sign out: $e');
            }
            if (mounted) {
              setState(
                () => _error =
                    'Profile completion required. Please sign in again.',
              );
            }
            return;
          }
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthRoleGate()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = FirebaseErrorHandler.getFirebaseAuthErrorMessage(e),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e),
        );
      }
    } catch (e) {
      String msg = 'Sign in failed. ';
      if (e.toString().contains('Sign-in canceled')) {
        msg = 'Sign-in was canceled.';
      } else {
        msg += e.toString();
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: AppBar(
        backgroundColor: SchoolWayTheme.background,
        elevation: 0,
        foregroundColor: SchoolWayTheme.navy,
        title: Text(
          AppLocalizations.of(context).welcomeTitle,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: SchoolWayTheme.navy,
          ),
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                _error!,
                style: TextStyle(color: SchoolWayTheme.danger),
              ),
            ),
          Spacer(),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SignInScreen(),
                                  ),
                                ),
                          icon: Icon(
                            Icons.email_outlined,
                            color: SchoolWayTheme.surface,
                          ),
                          label: Text(
                            AppLocalizations.of(context).signIn,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SchoolWayTheme.primary,
                            foregroundColor: SchoolWayTheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _onGoogleSignIn,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: SchoolWayTheme.surface,
                      side: BorderSide(
                        color: SchoolWayTheme.borderStrong,
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GoogleLogo(),
                        SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context).signInWithGoogle,
                          style: TextStyle(
                            color: SchoolWayTheme.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Lexend',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).needAnAccountPleaseContactAdmin,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: SchoolWayTheme.navy,
                    fontFamily: 'Lexend',
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/google_logo.png',
      width: 20,
      height: 20,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.g_mobiledata, color: SchoolWayTheme.navy, size: 24);
      },
    );
  }
}
