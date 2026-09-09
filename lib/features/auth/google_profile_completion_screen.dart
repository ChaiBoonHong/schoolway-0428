import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

import 'firebase_error_handler.dart';

class GoogleProfileCompletionScreen extends StatefulWidget {
  const GoogleProfileCompletionScreen({
    super.key,
    required this.userId,
    this.existingPhoneNumber,
    this.existingCountryCode,
    this.existingGender,
    this.existingBirthday,
    this.existingUsername,
  });

  final String userId;
  final String? existingPhoneNumber;
  final String? existingCountryCode;
  final String? existingGender;
  final DateTime? existingBirthday;
  final String? existingUsername;

  @override
  State<GoogleProfileCompletionScreen> createState() =>
      _GoogleProfileCompletionScreenState();
}

class _GoogleProfileCompletionScreenState
    extends State<GoogleProfileCompletionScreen> {
  bool _busy = false;
  String? _error;
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;
  late String _countryCode;
  String? _gender;
  DateTime? _birthday;

  final Map<String, String> _countryCodes = {
    'Malaysia': '+60',
    'Singapore': '+65',
  };

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.existingUsername ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.existingPhoneNumber ?? '',
    );
    _countryCode = widget.existingCountryCode ?? '+60';
    _gender = widget.existingGender;
    _birthday = widget.existingBirthday;
  }

  Future<bool> _isUsernameAvailable(String username) async {
    try {
      // Check if a document with this username (as ID) already exists
      final doc = await swFirestore.collection('users').doc(username).get();
      return !doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final username = _usernameController.text.trim();

      // Username is required
      if (username.isEmpty) {
        setState(() => _error = 'Please enter a username.');
        return;
      }

      // Check if username is available (but allow if it's their existing username)
      if (username != widget.existingUsername) {
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
      }

      final Map<String, dynamic> update = {
        'authUid': widget.userId, // Store the Firebase Auth UID
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      };

      if ((_gender ?? '').isNotEmpty) update['gender'] = _gender;
      if (_birthday != null) {
        update['birthday'] = Timestamp.fromDate(_birthday!);
      }
      if (_phoneController.text.trim().isNotEmpty) {
        update['phoneNumber'] = _phoneController.text.trim();
        update['countryCode'] = _countryCode;
      }

      // At least phone, gender, or birthday must be filled
      if (!update.containsKey('gender') &&
          !update.containsKey('birthday') &&
          !update.containsKey('phoneNumber')) {
        setState(
          () => _error =
              'Please fill in at least gender, birthday, or phone number.',
        );
        return;
      }

      try {
        await swFirestore
            .collection('users')
            .doc(widget.userId)
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
            () => _error = 'Failed to save profile data. Please try again.',
          );
        }
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
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
      appBar: AppBar(
        elevation: 0,
        title: Text(AppLocalizations.of(context).completeYourProfile),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).weNeedAFewMoreDetailsTo,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              SizedBox(height: 12),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: SchoolWayTheme.danger)),
                SizedBox(height: 12),
              ],
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).username2,
                  hintText: AppLocalizations.of(context).chooseAUniqueUsername,
                  border: OutlineInputBorder(),
                ),
                enabled: !_busy,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_gender),
                initialValue: _gender,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).gender,
                  border: OutlineInputBorder(),
                ),
                hint: Text(AppLocalizations.of(context).selectGender),
                items: [
                  DropdownMenuItem(
                    value: 'Male',
                    child: Text(AppLocalizations.of(context).male),
                  ),
                  DropdownMenuItem(
                    value: 'Female',
                    child: Text(AppLocalizations.of(context).female),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _gender = value),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      initialValue: _countryCode,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).country,
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) {
                        return _countryCodes.entries
                            .map(
                              (e) => Text(
                                e.value,
                                style: TextStyle(fontFamily: 'Lexend'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                            .toList();
                      },
                      items: _countryCodes.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.value,
                              child: Text(
                                '${e.key} ${e.value}',
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _countryCode = v ?? '+60'),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).phoneNumber2,
                        prefixText: _countryCode,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      enabled: !_busy,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _birthday ??
                                DateTime(now.year - 18, now.month, now.day),
                            firstDate: DateTime(1900),
                            lastDate: now,
                          );
                          if (picked != null) {
                            setState(() => _birthday = picked);
                          }
                        },
                  child: Text(
                    _birthday == null
                        ? 'Select birthday'
                        : 'Birthday: ${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SchoolWayTheme.primary,
                    foregroundColor: SchoolWayTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    AppLocalizations.of(context).saveAndContinue,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
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
