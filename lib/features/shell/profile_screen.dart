import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/widgets/app_modal_sheet.dart';

import '../auth/auth_service.dart';
import '../auth/firebase_error_handler.dart';
import 'app_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  String? _error;
  String? _info;
  bool _hasInitialized = false;
  bool _birthdayChanged = false;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  String _countryCode = '+60';
  String? _gender;
  DateTime? _birthday;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 80, 1, 1);
    final lastDate = DateTime(now.year - 3, 12, 31);
    // Use existing birthday if available, otherwise default to 18 years ago
    final initialDate =
        _birthday ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      setState(() {
        _birthday = picked;
        _birthdayChanged = true;
      });
    }
  }

  Future<void> _showEditProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            InputDecoration pillDecoration({
              required String hintText,
              Widget? suffixIcon,
            }) {
              return InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(fontFamily: 'Lexend'),
                filled: true,
                fillColor: SchoolWayTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: SchoolWayTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: SchoolWayTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: SchoolWayTheme.navy),
                ),
                suffixIcon: suffixIcon,
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    color: SchoolWayTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 52,
                            height: 4,
                            decoration: BoxDecoration(
                              color: SchoolWayTheme.navy,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).updateProfile,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: SchoolWayTheme.navy,
                          ),
                        ),
                        SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _firstName,
                                decoration: pillDecoration(
                                  hintText: AppLocalizations.of(
                                    context,
                                  ).firstName,
                                ),
                                enabled: !_busy,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _lastName,
                                decoration: pillDecoration(
                                  hintText: AppLocalizations.of(
                                    context,
                                  ).lastName,
                                ),
                                enabled: !_busy,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(_countryCode),
                                initialValue: _countryCode,
                                items: [
                                  DropdownMenuItem(
                                    value: '+60',
                                    child: Text(
                                      AppLocalizations.of(context).text60,
                                      style: TextStyle(fontFamily: 'Lexend'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: '+65',
                                    child: Text(
                                      AppLocalizations.of(context).text65,
                                      style: TextStyle(fontFamily: 'Lexend'),
                                    ),
                                  ),
                                ],
                                onChanged: _busy
                                    ? null
                                    : (v) => setSheetState(
                                        () => _countryCode = v ?? '+60',
                                      ),
                                decoration: pillDecoration(
                                  hintText: AppLocalizations.of(context).code,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _phone,
                                decoration: pillDecoration(
                                  hintText: AppLocalizations.of(
                                    context,
                                  ).phoneNumber,
                                ),
                                keyboardType: TextInputType.phone,
                                enabled: !_busy,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(_gender ?? ''),
                          initialValue: (_gender ?? '').isEmpty
                              ? null
                              : _gender,
                          items: [
                            DropdownMenuItem(
                              value: 'Male',
                              child: Text(
                                AppLocalizations.of(context).male,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Female',
                              child: Text(
                                AppLocalizations.of(context).female,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Other',
                              child: Text(
                                AppLocalizations.of(context).other,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setSheetState(() => _gender = v),
                          decoration: pillDecoration(
                            hintText: AppLocalizations.of(context).gender,
                          ),
                        ),
                        SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await _pickBirthday();
                                  if (!mounted) return;
                                  setSheetState(() {});
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SchoolWayTheme.navy,
                            side: BorderSide(color: SchoolWayTheme.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          icon: Icon(Icons.cake_outlined),
                          label: Text(
                            _birthday == null
                                ? 'Select birthday'
                                : 'Birthday: ${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _saveProfile();
                                    if (!sheetContext.mounted) return;
                                    if (_error != null) return;
                                    Navigator.of(sheetContext).pop();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SchoolWayTheme.navy,
                              foregroundColor: SchoolWayTheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              _busy ? 'SAVING...' : 'SAVE',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            AppLocalizations.of(context).cancel,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              color: SchoolWayTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final profile = await swFirestore.collection('users').doc(user.uid).get();
      if (!profile.exists) {
        setState(() => _error = 'User profile not found');
        return;
      }
      await swFirestore.collection('users').doc(user.uid).set({
        'firstName': _firstName.text.trim(),
        'lastName': _lastName.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'countryCode': _countryCode,
        'gender': (_gender ?? '').trim(),
        if (_birthday != null) 'birthday': Timestamp.fromDate(_birthday!),
      }, SetOptions(merge: true));
      setState(() {
        _info = 'Profile updated';
        // Mark as initialized so controllers sync properly after save
        _hasInitialized = true;
        // Reset birthday changed flag after successful save
        _birthdayChanged = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(
        () => _error = ErrorReporter.userMessage(
          context,
          error,
          stackTrace,
          category: 'profile',
          message: 'Profile update failed.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    final providers = user.providerData.map((p) => p.providerId).toList();
    final usesPassword = providers.contains('password');

    if (!usesPassword) {
      // For SSO users, send reset email to set a password
      final messenger = ScaffoldMessenger.of(context);
      try {
        await AuthService(
          FirebaseAuth.instance,
          GoogleSignIn.instance,
        ).sendPasswordReset(email: user.email!);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).resetEmailSent)),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'profile',
                message: 'Profile operation failed.',
              ),
            ),
          ),
        );
      }
      return;
    }

    final currentEmail = user.email!;
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    await showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: SchoolWayTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 52,
                        height: 4,
                        decoration: BoxDecoration(
                          color: SchoolWayTheme.navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context).changePassword,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: currentPassword,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).currentPassword2,
                        hintStyle: TextStyle(fontFamily: 'Lexend'),
                        filled: true,
                        fillColor: SchoolWayTheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.navy),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureCurrent = !obscureCurrent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: newPassword,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).newPassword,
                        hintStyle: TextStyle(fontFamily: 'Lexend'),
                        filled: true,
                        fillColor: SchoolWayTheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.navy),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscureNew = !obscureNew),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: confirmPassword,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).confirmPassword,
                        hintStyle: TextStyle(fontFamily: 'Lexend'),
                        filled: true,
                        fillColor: SchoolWayTheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: SchoolWayTheme.navy),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SchoolWayTheme.navy,
                          foregroundColor: SchoolWayTheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final current = currentPassword.text.trim();
                          final next = newPassword.text.trim();
                          final confirm = confirmPassword.text.trim();

                          if (current.isEmpty ||
                              next.isEmpty ||
                              confirm.isEmpty) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).pleaseFillAllFields,
                                ),
                              ),
                            );
                            return;
                          }
                          if (next.length < 6) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).newPasswordMustBeAtLeast6,
                                ),
                              ),
                            );
                            return;
                          }
                          if (next != confirm) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).passwordsDoNotMatch,
                                ),
                              ),
                            );
                            return;
                          }

                          try {
                            final cred = EmailAuthProvider.credential(
                              email: currentEmail,
                              password: current,
                            );
                            await user.reauthenticateWithCredential(cred);
                            await user.updatePassword(next);
                            if (context.mounted) navigator.pop();
                            if (context.mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).passwordUpdated,
                                  ),
                                ),
                              );
                            }
                          } on FirebaseAuthException catch (e) {
                            if (!context.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text(e.message ?? e.code)),
                            );
                          } catch (error, stackTrace) {
                            if (!context.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  ErrorReporter.userMessage(
                                    context,
                                    error,
                                    stackTrace,
                                    category: 'profile',
                                    message: 'Profile action failed.',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(
                          AppLocalizations.of(context).save2,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppLocalizations.of(context).cancel,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _changeEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    final currentEmail = user.email!;
    final passwordController = TextEditingController();
    final newEmailController = TextEditingController();
    final confirmEmailController = TextEditingController();
    bool obscurePassword = true;
    bool busy = false;
    String? error;
    String? info;

    await showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> submit() async {
            if (busy) return;
            var closed = false;

            final nextEmail = newEmailController.text.trim();
            final confirmEmail = confirmEmailController.text.trim();
            final currentPassword = passwordController.text;

            if (nextEmail.isEmpty) {
              setSheetState(() => error = 'Please enter a new email address.');
              return;
            }
            if (nextEmail != confirmEmail) {
              setSheetState(
                () => error = 'New email and confirmation email do not match.',
              );
              return;
            }
            if (currentPassword.trim().isEmpty) {
              setSheetState(
                () => error = 'Please enter your current password.',
              );
              return;
            }

            setSheetState(() {
              busy = true;
              error = null;
              info = null;
            });

            try {
              final service = AuthService(
                FirebaseAuth.instance,
                GoogleSignIn.instance,
              );
              await service.updateEmailWithReauth(
                currentEmail: currentEmail,
                currentPassword: currentPassword,
                newEmail: nextEmail,
              );

              if (!context.mounted) return;
              closed = true;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).emailUpdatedSuccessfully,
                  ),
                ),
              );
            } on FirebaseAuthException catch (e) {
              if (!context.mounted) return;
              setSheetState(
                () =>
                    error = FirebaseErrorHandler.getFirebaseAuthErrorMessage(e),
              );
            } on FirebaseException catch (e) {
              if (!context.mounted) return;
              setSheetState(
                () => error = FirebaseErrorHandler.getFirestoreErrorMessage(e),
              );
            } catch (_) {
              if (!context.mounted) return;
              setSheetState(
                () => error = 'Failed to update email. Please try again.',
              );
            } finally {
              if (!closed && context.mounted) {
                setSheetState(() => busy = false);
              }
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: SchoolWayTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 52,
                          height: 4,
                          decoration: BoxDecoration(
                            color: SchoolWayTheme.navy,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context).changeEmail2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      SizedBox(height: 16),
                      if (error != null) ...[
                        Text(
                          error!,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: SchoolWayTheme.danger,
                          ),
                        ),
                        SizedBox(height: 10),
                      ],
                      if (info != null) ...[
                        Text(
                          info!,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: SchoolWayTheme.primary,
                          ),
                        ),
                        SizedBox(height: 10),
                      ],
                      TextFormField(
                        initialValue: currentEmail,
                        readOnly: true,
                        enabled: false,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context).currentEmail2,
                          hintStyle: TextStyle(fontFamily: 'Lexend'),
                          filled: true,
                          fillColor: SchoolWayTheme.neutralSurface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: SchoolWayTheme.navy),
                          ),
                        ),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        controller: newEmailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !busy,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context).newEmail2,
                          hintStyle: TextStyle(fontFamily: 'Lexend'),
                          filled: true,
                          fillColor: SchoolWayTheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: SchoolWayTheme.navy),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        controller: confirmEmailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !busy,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(
                            context,
                          ).confirmNewEmail2,
                          hintStyle: TextStyle(fontFamily: 'Lexend'),
                          filled: true,
                          fillColor: SchoolWayTheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: SchoolWayTheme.navy),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        enabled: !busy,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(
                            context,
                          ).currentPassword2,
                          hintStyle: TextStyle(fontFamily: 'Lexend'),
                          filled: true,
                          fillColor: SchoolWayTheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: SchoolWayTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: SchoolWayTheme.navy),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setSheetState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SchoolWayTheme.navy,
                            foregroundColor: SchoolWayTheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: busy ? null : submit,
                          child: Text(
                            busy ? 'UPDATING...' : 'SAVE',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          AppLocalizations.of(context).cancel,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: SchoolWayTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        passwordController.dispose();
        newEmailController.dispose();
        confirmEmailController.dispose();
      });
    }
  }

  Future<void> _linkGoogleAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      await service.linkCurrentUserWithGoogle();
      await user.reload();
      setState(() {
        _info = 'Google account linked. You can now sign in with Google.';
      });
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'provider-already-linked':
          msg = 'Google account is already linked.';
          break;
        case 'credential-already-in-use':
          msg = 'This Google account is already linked to another user.';
          break;
        case 'account-exists-with-different-credential':
          msg = 'This Google email is already used by another sign-in method.';
          break;
        case 'operation-not-allowed':
          msg = 'Google sign-in is not enabled in Firebase.';
          break;
        default:
          msg = FirebaseErrorHandler.getFirebaseAuthErrorMessage(e);
      }
      setState(() => _error = msg);
    } catch (e) {
      setState(
        () => _error = 'Failed to link Google account. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkGoogleAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final service = AuthService(FirebaseAuth.instance, GoogleSignIn.instance);
      await service.unlinkCurrentUserFromGoogle();
      await user.reload();
      setState(() {
        _info = 'Google account unlinked.';
      });
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'no-such-provider':
          msg = 'Google account is not linked.';
          break;
        case 'requires-alternative-signin':
          msg =
              'Before unlinking Google, set a password or another sign-in method.';
          break;
        default:
          msg = FirebaseErrorHandler.getFirebaseAuthErrorMessage(e);
      }
      setState(() => _error = msg);
    } catch (_) {
      setState(
        () => _error = 'Failed to unlink Google account. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(child: Text(AppLocalizations.of(context).noUser));
    }

    final stream = swFirestore.collection('users').doc(user.uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || !snap.data!.exists) {
          return Center(
            child: Text(
              AppLocalizations.of(context).userProfileNotFound,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          );
        }
        final data = snap.data!.data()!;

        // Only update controllers if they haven't been initialized
        // This prevents overwriting user input while they're typing
        final firestoreFirstName = data['firstName'] as String? ?? '';
        final firestoreLastName = data['lastName'] as String? ?? '';
        final firestorePhone = data['phoneNumber'] as String? ?? '';

        if (!_hasInitialized) {
          _firstName.text = firestoreFirstName;
          _lastName.text = firestoreLastName;
          _phone.text = firestorePhone;
          _hasInitialized = true;
        } else {
          // Only sync from Firestore if the controller text matches what's in Firestore
          // This means the user hasn't made changes, so it's safe to update
          // If the user has typed something different, we preserve their input
          if (_firstName.text == firestoreFirstName) {
            // No user edits, safe to sync
            _firstName.text = firestoreFirstName;
          }
          if (_lastName.text == firestoreLastName) {
            // No user edits, safe to sync
            _lastName.text = firestoreLastName;
          }
          if (_phone.text == firestorePhone) {
            // No user edits, safe to sync
            _phone.text = firestorePhone;
          }
        }

        _countryCode = (data['countryCode'] as String?) ?? _countryCode;
        _gender = data['gender'] as String?;
        final birthdayTs = data['birthday'] as Timestamp?;
        final firestoreBirthday = birthdayTs?.toDate();

        // Only update birthday from Firestore if it hasn't been manually changed
        if (!_hasInitialized) {
          _birthday = firestoreBirthday;
        } else if (!_birthdayChanged) {
          // Only sync from Firestore if the user hasn't manually changed it
          _birthday = firestoreBirthday;
        }

        final fullName = '${_firstName.text.trim()} ${_lastName.text.trim()}'
            .trim();
        final displayName = fullName.isEmpty ? 'Your profile' : fullName;
        final hasGoogleLinked = user.providerData.any(
          (p) => p.providerId == 'google.com',
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppLocalizations.of(context).settings,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: SchoolWayTheme.navy,
                ),
              ),
              SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SchoolWayTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: SchoolWayTheme.accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: SchoolWayTheme.background,
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).welcome,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              color: SchoolWayTheme.neutralLabel,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: SchoolWayTheme.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context).logout,
                      onPressed: () {
                        AuthService(
                          FirebaseAuth.instance,
                          GoogleSignIn.instance,
                        ).signOut();
                      },
                      icon: Icon(Icons.logout, color: SchoolWayTheme.primary),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              if (_error != null) ...[
                _StatusBanner(message: _error!, isError: true),
                SizedBox(height: 12),
              ],
              if (_info != null) ...[
                _StatusBanner(message: _info!, isError: false),
                SizedBox(height: 12),
              ],
              _SectionCard(
                title: 'Profile',
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.person_outline,
                      title: 'User profile',
                      subtitle: 'Update your personal details',
                      onPressed: _showEditProfileSheet,
                    ),
                    SizedBox(height: 10),
                    _ActionTile(
                      icon: Icons.password_outlined,
                      title: 'Change password',
                      subtitle: 'Update your account password',
                      onPressed: _changePassword,
                    ),
                    SizedBox(height: 10),
                    _ActionTile(
                      icon: Icons.mark_email_unread_outlined,
                      title: 'Change email',
                      subtitle: 'Update your sign-in email',
                      onPressed: _changeEmail,
                    ),
                    SizedBox(height: 10),
                    _GoogleLinkButton(
                      linked: hasGoogleLinked,
                      busy: _busy,
                      onPressed: hasGoogleLinked
                          ? _unlinkGoogleAccount
                          : _linkGoogleAccount,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              _SectionCard(
                title: 'App preferences',
                child: _ActionTile(
                  icon: Icons.tune,
                  title: 'Appearance and accessibility',
                  subtitle: 'Theme, motion, language, and onboarding',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AppSettingsScreen(),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              _SectionCard(
                title: 'Session',
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          AuthService(
                            FirebaseAuth.instance,
                            GoogleSignIn.instance,
                          ).signOut();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SchoolWayTheme.danger,
                          side: BorderSide(color: SchoolWayTheme.danger),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(Icons.logout),
                        label: Text(
                          AppLocalizations.of(context).logout,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SchoolWayTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: SchoolWayTheme.accent.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: onPressed != null
              ? SchoolWayTheme.background
              : SchoolWayTheme.subtleCyanSurface,
          border: Border.all(
            color: SchoolWayTheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: SchoolWayTheme.primary),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      color: SchoolWayTheme.navy,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SchoolWayTheme.primary),
          ],
        ),
      ),
    );
  }
}

class _GoogleLinkButton extends StatelessWidget {
  const _GoogleLinkButton({
    required this.linked,
    required this.busy,
    required this.onPressed,
  });

  final bool linked;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: SchoolWayTheme.surface,
          side: BorderSide(color: SchoolWayTheme.borderStrong, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/google_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.g_mobiledata, color: SchoolWayTheme.navy),
            ),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                busy
                    ? 'Please wait...'
                    : (linked
                          ? 'Unlink with Google Account'
                          : 'Link with Google Account'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: SchoolWayTheme.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Lexend',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bgColor = isError
        ? SchoolWayTheme.danger.withValues(alpha: 0.08)
        : SchoolWayTheme.primary.withValues(alpha: 0.1);
    final borderColor = isError
        ? SchoolWayTheme.danger.withValues(alpha: 0.28)
        : SchoolWayTheme.primary.withValues(alpha: 0.3);
    final textColor = isError ? SchoolWayTheme.danger : SchoolWayTheme.primary;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textColor),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Lexend',
                color: textColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
