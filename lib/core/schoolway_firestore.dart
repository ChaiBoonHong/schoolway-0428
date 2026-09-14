import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Named Firestore database ID from Firebase Console (not `(default)`).
const String kSchoolWayFirebaseProjectId = 'schoolway-04286806';
const String kSchoolWayFirestoreDatabaseId = 'schoolway';
const String kSchoolWayFunctionsRegion = 'asia-southeast1';

FirebaseFirestore get swFirestore => FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: kSchoolWayFirestoreDatabaseId,
);
