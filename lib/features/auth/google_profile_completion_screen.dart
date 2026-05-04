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
  State<GoogleProfileCompletionScreen> createState() => _GoogleProfileCompletionScreenState();
}

class _GoogleProfileCompletionScreenState extends State<GoogleProfileCompletionScreen> {
  bool _busy = false;
  String? _error;
  late final TextEditingController _usernameController;
  late final TextEditingController _phoneController;
  late String _countryCode;
  String? _gender;
  DateTime? _birthday;

  final Map<String, String> _countryCodes = const {
    'Malaysia': '+60',
    'Singapore': '+65',
  };

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.existingUsername ?? '');
    _phoneController = TextEditingController(text: widget.existingPhoneNumber ?? '');
    _countryCode = widget.existingCountryCode ?? '+60';
    _gender = widget.existingGender;
    _birthday = widget.existingBirthday;
  }

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
            setState(() => _error = 'Username is already taken. Please choose another.');
          }
          return;
        }
      }
      
      final Map<String, dynamic> update = {
        'authUid': widget.userId,  // Store the Firebase Auth UID
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      };
      
      if ((_gender ?? '').isNotEmpty) update['gender'] = _gender;
      if (_birthday != null) update['birthday'] = Timestamp.fromDate(_birthday!);
      if (_phoneController.text.trim().isNotEmpty) {
        update['phoneNumber'] = _phoneController.text.trim();
        update['countryCode'] = _countryCode;
      }

      // At least phone, gender, or birthday must be filled
      if (!update.containsKey('gender') && !update.containsKey('birthday') && !update.containsKey('phoneNumber')) {
        setState(() => _error = 'Please fill in at least gender, birthday, or phone number.');
        return;
      }

      try {
        // Create/update user document with username as document ID
        await swFirestore
            .collection('users')
            .doc(username)
            .set(update, SetOptions(merge: true));
      } on FirebaseException catch (e) {
        if (mounted) {
          setState(() => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e));
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'Failed to save profile data. Please try again.');
        }
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _error = FirebaseErrorHandler.getFirestoreErrorMessage(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'An unexpected error occurred. Please try again.');
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
          'Complete your profile',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'We need a few more details to continue.',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Choose a unique username',
                  border: OutlineInputBorder(),
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_gender),
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: _busy ? null : (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      initialValue: _countryCode,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) {
                        return _countryCodes.entries
                            .map((e) => Text(
                                  e.value,
                                  style: const TextStyle(fontFamily: 'Lexend'),
                                  overflow: TextOverflow.ellipsis,
                                ))
                            .toList();
                      },
                      items: _countryCodes.entries
                          .map((e) => DropdownMenuItem(
                                value: e.value,
                                child: Text(
                                  '${e.key} ${e.value}',
                                  style: const TextStyle(fontFamily: 'Lexend'),
                                ),
                              ))
                          .toList(),
                      onChanged: _busy ? null : (v) => setState(() => _countryCode = v ?? '+60'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone number',
                        prefixText: _countryCode,
                        border: const OutlineInputBorder(),
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
                            initialDate: _birthday ?? DateTime(now.year - 18, now.month, now.day),
                            firstDate: DateTime(1900),
                            lastDate: now,
                          );
                          if (picked != null) setState(() => _birthday = picked);
                        },
                  child: Text(
                    _birthday == null
                        ? 'Select birthday'
                        : 'Birthday: ${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Save and continue',
                    style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 16),
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



