import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A one-time migration script to backfill the `user_roles` collection 
/// based on existing `users` collection data.
Future<void> migrateUserRoles() async {
  if (kDebugMode) {
    print('Starting user roles migration...');
  }
  
  final firestore = FirebaseFirestore.instance;
  final usersSnapshot = await firestore.collection('users').get();
  final batch = firestore.batch();
  int count = 0;

  for (final doc in usersSnapshot.docs) {
    final data = doc.data();
    final authUid = data['authUid'] as String?;
    final role = data['role'] as String?;
    final username = doc.id;

    if (authUid != null) {
      final roleRef = firestore.collection('user_roles').doc(authUid);
      batch.set(roleRef, {
        'username': username,
        'role': role,
      }, SetOptions(merge: true));
      count++;
    }
  }

  await batch.commit();
  
  if (kDebugMode) {
    print('Migration complete. $count user roles migrated.');
  }
}
