import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/linked_account_profile.dart';

void main() {
  group('LinkedAccountProfile Model Tests', () {
    test('derives initials correctly from display name and email', () {
      const p1 = LinkedAccountProfile(
        id: '1',
        displayName: 'John Doe',
        email: 'john@example.com',
        platform: AccountPlatform.google,
      );
      expect(p1.initials, 'JD');

      const p2 = LinkedAccountProfile(
        id: '2',
        displayName: 'Alice',
        email: 'alice@example.com',
        platform: AccountPlatform.apple,
      );
      expect(p2.initials, 'AL');

      const p3 = LinkedAccountProfile(
        id: '3',
        displayName: '',
        email: 'faiz@schoolway.my',
        platform: AccountPlatform.schoolWaySso,
      );
      expect(p3.initials, 'F');

      const p4 = LinkedAccountProfile(
        id: '4',
        displayName: 'Ahmad Faiz (Parent)',
        email: 'parent@schoolway.my',
        platform: AccountPlatform.schoolWaySso,
      );
      expect(p4.initials, 'AF');
    });

    test('serializes to and from map with correct platform enum', () {
      final now = DateTime(2026, 8, 27, 10, 0);
      final profile = LinkedAccountProfile(
        id: 'acc_101',
        displayName: 'Ahmad Faiz',
        email: 'ahmad.faiz@schoolway.my',
        avatarUrl: 'https://example.com/avatar.png',
        platform: AccountPlatform.microsoft,
        isActive: true,
        unreadCount: 5,
        sessionToken: 'token_xyz_998',
        lastActiveAt: now,
        metadata: const {'role': 'driver', 'busId': 'bus_01'},
      );

      final map = profile.toMap();
      expect(map['id'], 'acc_101');
      expect(map['platform'], 'microsoft');
      expect(map['unreadCount'], 5);
      expect(map['isActive'], true);

      final restored = LinkedAccountProfile.fromMap(map);
      expect(restored.id, 'acc_101');
      expect(restored.platform, AccountPlatform.microsoft);
      expect(restored.unreadCount, 5);
      expect(restored.isActive, true);
      expect(restored.metadata['role'], 'driver');
      expect(restored, equals(profile));
    });

    test('copyWith updates specified fields only', () {
      const original = LinkedAccountProfile(
        id: '1',
        displayName: 'Original',
        email: 'orig@school.my',
        platform: AccountPlatform.schoolWaySso,
        isActive: false,
        unreadCount: 0,
      );

      final updated = original.copyWith(
        displayName: 'Updated Name',
        isActive: true,
        unreadCount: 4,
      );

      expect(updated.id, '1');
      expect(updated.displayName, 'Updated Name');
      expect(updated.email, 'orig@school.my');
      expect(updated.isActive, true);
      expect(updated.unreadCount, 4);
    });
  });
}
