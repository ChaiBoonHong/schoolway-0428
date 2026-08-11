import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/emergency_alert.dart';

void main() {
  test('emergency notification recipient survives Firestore map conversion', () {
    const recipient = EmergencyNotificationRecipient(
      authUid: 'auth-1',
      username: 'parent01',
      name: 'Parent One',
    );

    final decoded = EmergencyNotificationRecipient.fromMap(recipient.toMap());

    expect(decoded.authUid, 'auth-1');
    expect(decoded.username, 'parent01');
    expect(decoded.name, 'Parent One');
  });
}
