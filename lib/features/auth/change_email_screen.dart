import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';
import 'firebase_error_handler.dart';

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key, this.initialEmail});

  static const routeName = '/change-email';

  final String? initialEmail;

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  late final TextEditingController _currentEmailController;
  final _passwordController = TextEditingController();
  final _newEmailController = TextEditingController();
  final _confirmEmailController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    String? currentEmail;
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      currentEmail = widget.initialEmail!;
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email != null) {
        currentEmail = user!.email!;
      }
    }
    _currentEmailController = TextEditingController(text: currentEmail ?? '');
  }

  @override
  void dispose() {
    _currentEmailController.dispose();
    _passwordController.dispose();
    _newEmailController.dispose();
    _confirmEmailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_newEmailController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a new email address.');
      return;
    }
    if (_newEmailController.text.trim() !=
        _confirmEmailController.text.trim()) {
      setState(() => _error = 'New email and confirmation email do not match.');
      return;
    }
    final currentEmail = _currentEmailController.text.trim();
    if (currentEmail.isEmpty) {
      setState(() => _error = 'Current email not found.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      await service.updateEmailWithReauth(
        currentEmail: currentEmail,
        currentPassword: _passwordController.text,
        newEmail: _newEmailController.text.trim(),
      );

      if (mounted) {
        setState(() => _info = 'Email updated successfully.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: const Text(
          'Change email',
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
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_info != null) ...[
                Text(
                  _info!,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Color(0xFF0077B6),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Current email (read-only)
              TextField(
                controller: _currentEmailController,
                decoration: const InputDecoration(
                  labelText: 'Current email',
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: false,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  color: Color(0xFF0077B6),
                ),
              ),
              const SizedBox(height: 12),
              // New email
              TextField(
                controller: _newEmailController,
                decoration: const InputDecoration(labelText: 'New email'),
                keyboardType: TextInputType.emailAddress,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              // Confirm new email
              TextField(
                controller: _confirmEmailController,
                decoration: const InputDecoration(
                  labelText: 'Confirm new email',
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              // Current password
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Current password',
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
              const SizedBox(height: 24),
              // Update button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    _busy ? 'Updating...' : 'Update email',
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
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

