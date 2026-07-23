import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

import 'auth_service.dart';
import 'firebase_error_handler.dart';
import 'google_profile_completion_screen.dart';
import '../../app.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/widgets/bouncing_button.dart';
// Removed session flag flow; onboarding is shown only when user == null

InputDecoration _pillFieldDecoration({
  required String hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(fontFamily: 'Lexend'),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: Color(0xFF03045E)),
    ),
    suffixIcon: suffixIcon,
  );
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  static const routeName = '/sign-in';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
        // Reload user to get latest emailVerified status
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

        // Get the refreshed user object after reload
        final refreshedUser = FirebaseAuth.instance.currentUser;

        // Query user by authUid to get their username (document ID)
        String? username;
        Map<String, dynamic> userData = {};
        try {
          final querySnapshot = await swFirestore
              .collection('users')
              .where('authUid', isEqualTo: user.uid)
              .limit(1)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            username =
                querySnapshot.docs.first.id; // Document ID is the username
            userData = querySnapshot.docs.first.data();
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

        final existingCreatedAt = userData['createdAt'];

        // Extract name from Google user (displayName or email prefix)
        String? firstName;
        String? lastName;
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          final nameParts = user.displayName!.trim().split(' ');
          if (nameParts.isNotEmpty) {
            firstName = nameParts.first;
            lastName = nameParts.length > 1
                ? nameParts.sublist(1).join(' ')
                : null;
          }
        }

        // Check existing values to preserve user-edited names
        final existingFirstName = userData['firstName'] as String?;
        final existingLastName = userData['lastName'] as String?;
        final hasExistingFirstName =
            existingFirstName != null && existingFirstName.isNotEmpty;
        final hasExistingLastName =
            existingLastName != null && existingLastName.isNotEmpty;

        // If user exists (has username), update their data
        if (username != null) {
          // Create Firestore document update with only non-null fields
          final Map<String, dynamic> googleProfileUpdate = {
            'email': user.email,
            'lastLoginAt': FieldValue.serverTimestamp(),
          };
          // Only set createdAt if it doesn't exist (preserve original creation time)
          if (existingCreatedAt == null) {
            googleProfileUpdate['createdAt'] = FieldValue.serverTimestamp();
          }
          // Only set firstName/lastName if they don't already exist (preserve user-edited names)
          if (firstName != null &&
              firstName.isNotEmpty &&
              !hasExistingFirstName) {
            googleProfileUpdate['firstName'] = firstName;
          }
          if (lastName != null && lastName.isNotEmpty && !hasExistingLastName) {
            googleProfileUpdate['lastName'] = lastName;
          }
          // Only ever set emailVerified -> true; never overwrite an existing true with false
          // Use refreshedUser to get the latest emailVerified status
          if (refreshedUser?.emailVerified ?? false) {
            googleProfileUpdate['emailVerified'] = true;
          }

          try {
            await swFirestore
                .collection('users')
                .doc(username)
                .set(googleProfileUpdate, SetOptions(merge: true));
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
                .doc(username)
                .get();
            userData = doc.data() ?? {};
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
        }

        if (username == null || username.isEmpty) {
          username = user.email?.split('@').first ?? user.uid;
          
          final Map<String, dynamic> newUserProfile = {
            'username': username,
            'email': user.email,
            'authUid': user.uid,
            'role': '',
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
            'emailVerified': refreshedUser?.emailVerified ?? false,
          };
          if (firstName != null && firstName.isNotEmpty) {
            newUserProfile['firstName'] = firstName;
          }
          if (lastName != null && lastName.isNotEmpty) {
            newUserProfile['lastName'] = lastName;
          }

          try {
            await swFirestore.collection('users').doc(username).set(newUserProfile, SetOptions(merge: true));
            userData = newUserProfile;
          } on FirebaseException catch (e) {
            if (mounted) {
              setState(() => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e));
            }
            return;
          } catch (e) {
            if (mounted) {
              setState(() => _error = 'Failed to create user data. Please try again.');
            }
            return;
          }
        }

        // Check if required profile fields are missing
        final phoneNumber = (userData['phoneNumber'] as String?) ?? '';
        final countryCode = (userData['countryCode'] as String?) ?? '+60';
        final gender = userData['gender'] as String?;
        final birthdayTs = userData['birthday'] as Timestamp?;
        final birthday = birthdayTs?.toDate();

        if (!mounted) return;

        final missingPhone = phoneNumber.isEmpty;
        final missingGender = (gender == null || gender.isEmpty);
        final missingBirthday = (birthday == null);

        if (missingPhone ||
            missingGender ||
            missingBirthday) {
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
        MaterialPageRoute(builder: (_) => const AuthRoleGate()),
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
      String errorMessage = 'Sign in failed. ';
      if (e.toString().contains('Sign-in canceled')) {
        errorMessage = 'Sign-in was canceled.';
      } else if (e.toString().contains('No email found')) {
        errorMessage = 'No email found in Google account.';
      } else {
        errorMessage += e.toString();
      }
      if (mounted) {
        setState(() => _error = errorMessage);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onEmailSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      final cred = await service.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = cred.user;
      if (user != null) {
        // Reload user to get latest emailVerified status
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

        // Get the refreshed user object after reload
        final refreshedUser = FirebaseAuth.instance.currentUser;

        // Query to find username for this authUid and keep profile timestamps up to date
        try {
          final querySnapshot = await swFirestore
              .collection('users')
              .where('authUid', isEqualTo: user.uid)
              .limit(1)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            final username = querySnapshot.docs.first.id;

            final Map<String, dynamic> emailSignInUpdate = {
              'email': user.email,
              'lastLoginAt': FieldValue.serverTimestamp(),
            };
            // Only set to true; never write false over an admin-verified account
            // Use refreshedUser to get the latest emailVerified status
            if (refreshedUser?.emailVerified ?? false) {
              emailSignInUpdate['emailVerified'] = true;
            }

            await swFirestore
                .collection('users')
                .doc(username)
                .set(emailSignInUpdate, SetOptions(merge: true));
          } else {
            // Auto-create user document
            final username = user.email?.split('@').first ?? user.uid;
            
            final Map<String, dynamic> emailSignInUpdate = {
              'username': username,
              'email': user.email,
              'authUid': user.uid,
              'role': '',
              'isActive': true,
              'createdAt': FieldValue.serverTimestamp(),
              'lastLoginAt': FieldValue.serverTimestamp(),
              'emailVerified': refreshedUser?.emailVerified ?? false,
            };

            await swFirestore
                .collection('users')
                .doc(username)
                .set(emailSignInUpdate, SetOptions(merge: true));
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
              () => _error = 'Failed to save user data. Please try again.',
            );
          }
          return;
        }

        // Email verification is not required to proceed.
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthRoleGate()),
          (route) => false,
        );
      }
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
      if (mounted) {
        setState(
          () => _error = 'An unexpected error occurred. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email above first.');
      return;
    }
    setState(() => _error = null);
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      await service.sendPasswordReset(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
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
      if (mounted) {
        setState(
          () => _error = 'An unexpected error occurred. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: const Text(
          'Sign in',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24.0,
            24.0,
            24.0,
            24.0 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _emailController,
                decoration: _pillFieldDecoration(hintText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: _pillFieldDecoration(
                  hintText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: _busy ? null : _onForgotPassword,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: Color(0xFF0077B6),
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              BouncingButton(
                child: SizedBox(
                  width: 260,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _onEmailSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0077B6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      _busy ? 'Signing in...' : 'Sign in with Email',
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BouncingButton(
                child: _GoogleSignInButton(
                  onPressed: _busy ? null : _onGoogleSignIn,
                  isLoading: _busy,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Need an account? Please contact admin.',
                  style: const TextStyle(
                    color: Color(0xFF03045E),
                    fontFamily: 'Lexend',
                    fontSize: 14,
                  ),
                ),
              ),
            ].animate(interval: 50.ms).fade(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
          ),
        ),
      ),
    );
  }
}

/// Custom Google Sign-In button with Google logo and brand styling
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed, required this.isLoading});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style:
            OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFDADCE0), width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ).copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.white),
              overlayColor: WidgetStateProperty.all(const Color(0xFFF8F9FA)),
            ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF03045E)),
                ),
              )
            else
              _GoogleLogo(),
            const SizedBox(width: 12),
            Text(
              isLoading ? 'Signing in...' : 'Sign in with Google',
              style: const TextStyle(
                color: Color(0xFF03045E),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Lexend',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google logo widget - creates a styled "G" logo matching Google's brand
class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Try to load Google logo from assets, fallback to custom widget
    return Image.asset(
      'assets/images/google_logo.png',
      width: 20,
      height: 20,
      errorBuilder: (context, error, stackTrace) {
        // Fallback: Create Google "G" logo using CustomPaint
        return CustomPaint(
          size: const Size(20, 20),
          painter: _GoogleLogoPainter(),
        );
      },
    );
  }
}

/// Custom painter for Google "G" logo
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Draw the "G" shape using Google's brand colors
    // Blue arc (top right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.57, // -90 degrees
      1.57, // 90 degrees
      false,
      paint,
    );

    // Green arc (bottom right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0, // 0 degrees
      1.57, // 90 degrees
      false,
      paint,
    );

    // Yellow arc (bottom left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      1.57, // 90 degrees
      1.57, // 90 degrees
      false,
      paint,
    );

    // Red arc (top left - partial)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14, // 180 degrees
      1.43, // ~82 degrees
      false,
      paint,
    );

    // Draw the horizontal line (part of "G")
    paint.color = const Color(0xFF4285F4);
    paint.strokeWidth = 2.5;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + radius * 0.6, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

