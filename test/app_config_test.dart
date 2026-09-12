import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/config.dart';

void main() {
  group('AppConfig Centralized Secrets & Configuration Tests', () {
    test('AppConfig provides valid default FCM Web VAPID key', () {
      expect(AppConfig.fcmWebVapidKey, isNotEmpty);
      expect(AppConfig.fcmWebVapidKey.length, greaterThan(20));
    });

    test('AppConfig provides valid support email and admin hotline', () {
      expect(AppConfig.supportContactEmail, contains('@'));
      expect(AppConfig.adminPhoneNumber, isNotEmpty);
    });

    test('AppConfig provides acceptable telemetry interval', () {
      expect(AppConfig.gpsUploadInterval.inSeconds, inInclusiveRange(1, 10));
    });
  });
}
