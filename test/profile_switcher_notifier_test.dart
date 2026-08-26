import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/models/linked_account_profile.dart';
import 'package:schoolway/services/session_swap_service.dart';

class FakeSessionSwapService implements SessionSwapService {
  bool shouldFail = false;
  SessionSwapException? failureException;

  @override
  Future<SessionSwapResult> swapSession({
    required LinkedAccountProfile targetAccount,
    required String? currentToken,
  }) async {
    if (shouldFail) {
      throw failureException ??
          const SessionSwapExpiredException('Token expired.');
    }
    return SessionSwapResult(
      success: true,
      newSessionToken: targetAccount.sessionToken ?? 'new_token',
      swappedAt: DateTime.now(),
    );
  }
}

void main() {
  group('ProfileSwitcherNotifier Tests', () {
    late FakeSessionSwapService fakeSwapService;
    late List<LinkedAccountProfile> sampleAccounts;
    late ProviderContainer container;

    setUp(() {
      fakeSwapService = FakeSessionSwapService();
      sampleAccounts = [
        const LinkedAccountProfile(
          id: 'acc_1',
          displayName: 'Parent One',
          email: 'parent1@schoolway.my',
          platform: AccountPlatform.email,
          isActive: true,
          unreadCount: 0,
          sessionToken: 'token_1',
        ),
        const LinkedAccountProfile(
          id: 'acc_2',
          displayName: 'Admin Two',
          email: 'admin2@schoolportal.edu.my',
          platform: AccountPlatform.google,
          isActive: false,
          unreadCount: 3,
          sessionToken: 'token_2',
        ),
        const LinkedAccountProfile(
          id: 'acc_3',
          displayName: 'Driver Three',
          email: 'driver3@schoolway.my',
          platform: AccountPlatform.email,
          isActive: false,
          unreadCount: 2,
          sessionToken: 'token_3',
        ),
      ];

      container = ProviderContainer(
        overrides: [
          sessionSwapServiceProvider.overrideWithValue(fakeSwapService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('correctly groups profiles by platform and computes unread count', () {
      final notifier = container.read(profileSwitcherProvider.notifier);
      notifier.setAccounts(sampleAccounts, activeId: 'acc_1');

      final state = container.read(profileSwitcherProvider);
      expect(state.groupedByPlatform[AccountPlatform.email]?.length, 2);
      expect(state.groupedByPlatform[AccountPlatform.google]?.length, 1);
      expect(state.activeAccountId, 'acc_1');
      expect(state.activeAccount?.displayName, 'Parent One');
      expect(state.totalUnreadCount, 5); // 3 + 2 from inactive accounts
    });

    test('successful session swap updates active account', () async {
      final notifier = container.read(profileSwitcherProvider.notifier);
      notifier.setAccounts(sampleAccounts, activeId: 'acc_1');

      final success = await notifier.selectAccount('acc_2');
      expect(success, isTrue);

      final state = container.read(profileSwitcherProvider);
      expect(state.activeAccountId, 'acc_2');
      expect(state.activeAccount?.displayName, 'Admin Two');
      expect(
        state.accounts.firstWhere((a) => a.id == 'acc_2').isActive,
        isTrue,
      );
      expect(
        state.accounts.firstWhere((a) => a.id == 'acc_1').isActive,
        isFalse,
      );
      expect(state.errorMessage, isNull);
      expect(state.isSwapping, isFalse);
    });

    test(
      'failed session swap retains previous active account and sets error',
      () async {
        fakeSwapService.shouldFail = true;
        fakeSwapService.failureException = const SessionSwapNetworkException(
          'Connection timed out.',
        );

        final notifier = container.read(profileSwitcherProvider.notifier);
        notifier.setAccounts(sampleAccounts, activeId: 'acc_1');

        final success = await notifier.selectAccount('acc_2');
        expect(success, isFalse);

        final state = container.read(profileSwitcherProvider);
        expect(state.activeAccountId, 'acc_1'); // Preserved!
        expect(
          state.accounts.firstWhere((a) => a.id == 'acc_1').isActive,
          isTrue,
        );
        expect(state.errorMessage, 'Connection timed out.');
        expect(state.isSwapping, isFalse);
      },
    );

    test('selecting already active account returns immediately', () async {
      final notifier = container.read(profileSwitcherProvider.notifier);
      notifier.setAccounts(sampleAccounts, activeId: 'acc_1');

      final success = await notifier.selectAccount('acc_1');
      expect(success, isTrue);
      expect(container.read(profileSwitcherProvider).activeAccountId, 'acc_1');
    });
  });
}
