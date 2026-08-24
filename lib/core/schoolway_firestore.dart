import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Named Firestore database ID from Firebase Console (not `(default)`).
const String kSchoolWayFirestoreDatabaseId = 'schoolway';

FirebaseFirestore get swFirestore => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: kSchoolWayFirestoreDatabaseId,
);
