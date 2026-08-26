import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/profile/screens/manage_accounts_screen.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/features/profile/state/profile_switcher_state.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';

class MockManageAccountsNotifier extends ProfileSwitcherNotifier {
  final List<LinkedAccountProfile> mockAccounts;

  MockManageAccountsNotifier(this.mockAccounts);

  @override
  ProfileSwitcherState build() {
    return ProfileSwitcherState(
      accounts: mockAccounts,
      activeAccountId: mockAccounts.firstOrNull?.id,
      isLoading: false,
    );
  }
}

Widget _buildManageTestApp({List<LinkedAccountProfile>? accounts}) {
  final sampleAccounts =
      accounts ??
      [
        const LinkedAccountProfile(
          id: 'acc_1',
          displayName: 'Aiman Khalid',
          email: 'aiman@schoolway.my',
          platform: AccountPlatform.email,
          isActive: true,
          unreadCount: 0,
        ),
        const LinkedAccountProfile(
          id: 'acc_2',
          displayName: 'Admin Schoolway',
          email: 'admin@schoolway.com',
          platform: AccountPlatform.google,
          isActive: false,
          unreadCount: 2,
        ),
      ];

  return ProviderScope(
    overrides: [
      profileSwitcherProvider.overrideWith(
        () => MockManageAccountsNotifier(sampleAccounts),
      ),
    ],
    child: MaterialApp(
      theme: SchoolWayTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ManageAccountsScreen(),
    ),
  );
}

void main() {
  group('ManageAccountsScreen Widget Tests', () {
    testWidgets('renders all saved accounts and action buttons', (
      tester,
    ) async {
      await tester.pumpWidget(_buildManageTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Manage Accounts'), findsOneWidget);
      expect(find.text('Aiman Khalid'), findsOneWidget);
      expect(find.text('aiman@schoolway.my'), findsOneWidget);
      expect(find.text('Admin Schoolway'), findsOneWidget);
      expect(find.text('admin@schoolway.com'), findsOneWidget);

      expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(2));
      expect(find.text('Add Account'), findsOneWidget);
    });

    testWidgets('shows confirmation dialog when delete is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(_buildManageTestApp());
      await tester.pumpAndSettle();

      final deleteButtons = find.byIcon(Icons.delete_outline_rounded);
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Remove Account'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('renders empty state when accounts list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildManageTestApp(accounts: []));
      await tester.pumpAndSettle();

      expect(find.text('No saved accounts found'), findsOneWidget);
    });
  });
}
