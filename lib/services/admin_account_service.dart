import 'package:cloud_functions/cloud_functions.dart';

abstract final class AdminAccountService {
  static const int minimumPasswordLength = 8;

  static void validateNewPassword(String password) {
    if (password.length < minimumPasswordLength) {
      throw ArgumentError(
        'Password must be at least $minimumPasswordLength characters',
      );
    }
  }

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  static Future<String> createUser({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    String phoneNumber = '',
    String countryCode = '+60',
    String gender = 'Other',
    bool isActive = true,
  }) async {
    validateNewPassword(password);
    final result = await _functions.httpsCallable('adminCreateUser').call({
      'username': username,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'password': password,
      'role': role,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'gender': gender,
      'isActive': isActive,
    });
    return (result.data as Map<Object?, Object?>)['uid']! as String;
  }

  static Future<void> updateUser(String uid, Map<String, Object?> patch) async {
    await _functions.httpsCallable('adminUpdateUser').call({
      'uid': uid,
      ...patch,
    });
  }

  static Future<void> deleteUser(String uid) async {
    await _functions.httpsCallable('adminDeleteUser').call({'uid': uid});
  }
}
