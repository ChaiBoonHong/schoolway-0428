import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/services/push_messaging_service.dart';

void main() {
  test('push diagnostics expose only safe delivery state', () {
    const diagnostics = PushMessagingDiagnostics(
      notificationsEnabled: true,
      criticalChannelReady: true,
      tokenSyncState: PushTokenSyncState.synchronized,
    );

    expect(diagnostics.notificationsEnabled, isTrue);
    expect(diagnostics.criticalChannelReady, isTrue);
    expect(diagnostics.tokenSyncState, PushTokenSyncState.synchronized);
  });
}
