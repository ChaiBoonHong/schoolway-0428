import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/firebase_options.dart';

void main() {
  test('all configured Firebase apps target the SchoolWay project', () {
    final options = [
      DefaultFirebaseOptions.web,
      DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios,
      DefaultFirebaseOptions.macos,
      DefaultFirebaseOptions.windows,
    ];

    for (final option in options) {
      expect(option.projectId, kSchoolWayFirebaseProjectId);
      expect(option.messagingSenderId, '137687591166');
      expect(
        option.storageBucket,
        '$kSchoolWayFirebaseProjectId.firebasestorage.app',
      );
    }
  });

  test('Firebase services use the deployed region and named database', () {
    expect(kSchoolWayFunctionsRegion, 'asia-southeast1');
    expect(kSchoolWayFirestoreDatabaseId, 'schoolway');
  });
}
