import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

import 'auth_service.dart';
import 'firebase_error_handler.dart';
import 'google_profile_completion_screen.dart';
import '../../app.dart';
// On sign up, proceed to auth gate; onboarding is for unauthenticated only

InputDecoration _pillFieldDecoration({
  required String hintText,
  String? prefixText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(fontFamily: 'Lexend'),
    prefixText: prefixText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
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
  );
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _usernameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  DateTime? _birthday;
  String _countryCode = '+60'; // Default to Malaysia
  String? _gender;

  // Common country codes
  final Map<String, String> _countryCodes = {
    'Malaysia': '+60',
    'Singapore': '+65',
  };

  Future<bool> _isUsernameAvailable(String username) async {
    try {
      // Check if a document with this username (as ID) already exists
      final doc = await swFirestore
          .collection('users')
          .doc(username)
          .get();
      return !doc.exists;
    } catch (e) {
      return false;
    }
  }

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

        final existingFirstName = userData['firstName'] as String?;
        final existingLastName = userData['lastName'] as String?;
        final hasExistingFirstName =
            existingFirstName != null && existingFirstName.isNotEmpty;
        final hasExistingLastName =
            existingLastName != null && existingLastName.isNotEmpty;

        String? firstName;
        String? lastName;
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
          if (user.emailVerified) update['emailVerified'] = true;

          try {
            await swFirestore
                .collection('users')
                .doc(username)
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
                () => _error = 'Failed to load user data. Please try again.',
              );
            }
            return;
          }
        }

        final phoneNumber = (userData['phoneNumber'] as String?) ?? '';
        final countryCode = (userData['countryCode'] as String?) ?? '+60';
        final gender = userData['gender'] as String?;
        final birthdayTs = userData['birthday'] as Timestamp?;
        final birthday = birthdayTs?.toDate();

        if (!mounted) return;
        final missingPhone = phoneNumber.isEmpty;
        final missingGender = (gender == null || gender.isEmpty);
        final missingBirthday = (birthday == null);
        final missingUsername = (username == null || username.isEmpty);
        if (missingPhone ||
            missingGender ||
            missingBirthday ||
            missingUsername) {
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
      if (mounted) {
        setState(
          () => _error = 'An unexpected error occurred. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onEmailSignUp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      final cred = await service.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = cred.user;
      if (user != null) {
        // Check if username is available
        final username = _usernameController.text.trim();
        final isAvailable = await _isUsernameAvailable(username);
        if (!isAvailable) {
          if (mounted) {
            setState(
              () =>
                  _error = 'Username is already taken. Please choose another.',
            );
          }
          return;
        }

        try {
          final batch = swFirestore.batch();
          final userRef = swFirestore.collection('users').doc(username);
          final roleRef = swFirestore.collection('user_roles').doc(user.uid);

          batch.set(userRef, {
                'authUid': user.uid,
                'firstName': _firstNameController.text.trim(),
                'lastName': _lastNameController.text.trim(),
                'gender': _gender,
                'birthday': _birthday != null
                    ? Timestamp.fromDate(_birthday!)
                    : null,
                'countryCode': _countryCode,
                'phoneNumber': _phoneController.text.trim(),
                'email': user.email,
                'emailVerified': user.emailVerified,
                'createdAt': FieldValue.serverTimestamp(),
                'role': null,
              }, SetOptions(merge: true));

          batch.set(roleRef, {
            'username': username,
            'role': null,
          }, SetOptions(merge: true));

          await batch.commit();
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
      if (mounted) {
        setState(
          () => _error = 'An unexpected error occurred. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          'Create account',
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
                controller: _usernameController,
                decoration: _pillFieldDecoration(hintText: 'Username'),
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _firstNameController,
                decoration: _pillFieldDecoration(hintText: 'First Name'),
                textCapitalization: TextCapitalization.words,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lastNameController,
                decoration: _pillFieldDecoration(hintText: 'Last Name'),
                textCapitalization: TextCapitalization.words,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_gender),
                initialValue: _gender,
                decoration: _pillFieldDecoration(hintText: 'Gender'),
                hint: const Text('Select Gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() => _gender = value);
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _countryCode,
                      decoration: _pillFieldDecoration(hintText: 'Country'),
                      items: _countryCodes.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.value,
                          child: Text(
                            '${entry.key} ${entry.value}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _countryCode = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _phoneController,
                      decoration: _pillFieldDecoration(
                        hintText: 'Phone Number',
                        prefixText: _countryCode,
                      ),
                      keyboardType: TextInputType.phone,
                      enabled: !_busy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(
                              now.year - 18,
                              now.month,
                              now.day,
                            ),
                            firstDate: DateTime(1900),
                            lastDate: now,
                          );
                          if (picked != null) {
                            setState(() => _birthday = picked);
                          }
                        },
                  child: Text(
                    _birthday == null
                        ? 'Select Birthday'
                        : 'Birthday: ${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                  hintText: 'Password (min 6 chars)',
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
              SizedBox(
                width: 260,
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (_usernameController.text.trim().isEmpty ||
                              _firstNameController.text.trim().isEmpty ||
                              _lastNameController.text.trim().isEmpty ||
                              _phoneController.text.trim().isEmpty ||
                              _gender == null ||
                              _birthday == null ||
                              _emailController.text.trim().isEmpty ||
                              _passwordController.text.isEmpty) {
                            setState(
                              () => _error =
                                  'Please fill in all fields, including username, gender and birthday.',
                            );
                            return;
                          }
                          await _onEmailSignUp();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    _busy ? 'Creating...' : 'Sign up with Email',
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _busy ? null : _onGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFDADCE0), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      // Use original Google logo asset without tint
                      Image(
                        image: AssetImage('assets/images/google_logo.png'),
                        width: 20,
                        height: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: TextStyle(
                          color: Color(0xFF03045E),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Lexend',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

