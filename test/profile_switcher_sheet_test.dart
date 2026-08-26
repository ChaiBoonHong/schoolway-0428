import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/features/profile/state/profile_switcher_state.dart';
import 'package:schoolway/features/profile/widgets/profile_switcher_sheet.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';

class MockProfileSwitcherNotifier extends ProfileSwitcherNotifier {
  final List<LinkedAccountProfile> mockAccounts;

  MockProfileSwitcherNotifier(this.mockAccounts);

  @override
  ProfileSwitcherState build() {
    return ProfileSwitcherState(
      accounts: mockAccounts,
      activeAccountId: mockAccounts.firstOrNull?.id,
      isLoading: false,
    );
  }
}

Widget _buildTestApp({
  List<LinkedAccountProfile>? accounts,
  VoidCallback? onManage,
  VoidCallback? onAdd,
}) {
  final sampleAccounts =
      accounts ??
      [
        const LinkedAccountProfile(
          id: 'acc_1',
          displayName: 'Ahmad Faiz',
          email: 'ahmad@schoolway.my',
          platform: AccountPlatform.schoolWaySso,
          isActive: true,
          unreadCount: 0,
        ),
        const LinkedAccountProfile(
          id: 'acc_2',
          displayName: 'Faiz Admin',
          email: 'admin@schoolportal.edu.my',
          platform: AccountPlatform.google,
          isActive: false,
          unreadCount: 4,
        ),
      ];

  return ProviderScope(
    overrides: [
      profileSwitcherProvider.overrideWith(
        () => MockProfileSwitcherNotifier(sampleAccounts),
      ),
    ],
    child: MaterialApp(
      theme: SchoolWayTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ProfileSwitcherSheet(
          onManageAccounts: onManage,
          onAddAccount: onAdd,
        ),
      ),
    ),
  );
}

void main() {
  group('ProfileSwitcherSheet Widget Tests', () {
    testWidgets(
      'renders header, platform groups, active indicator and unread badges',
      (tester) async {
        await tester.pumpWidget(_buildTestApp());
        await tester.pumpAndSettle();

        // Header
        expect(find.text('Switch Profile'), findsOneWidget);
        expect(find.text('Linked Accounts'), findsOneWidget);

        // Platform Headers
        expect(find.text('SchoolWay SSO'), findsOneWidget);
        expect(find.text('Google Workspace'), findsOneWidget);

        // Account Info
        expect(find.text('Ahmad Faiz'), findsOneWidget);
        expect(find.text('ahmad@schoolway.my'), findsOneWidget);
        expect(find.text('Active Account'), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);

        expect(find.text('Faiz Admin'), findsOneWidget);
        expect(find.text('admin@schoolportal.edu.my'), findsOneWidget);
        expect(find.text('4'), findsOneWidget); // Unread badge
      },
    );

    testWidgets('triggers onAddAccount callback when Add Account tile tapped', (
      tester,
    ) async {
      var addTapped = false;
      await tester.pumpWidget(_buildTestApp(onAdd: () => addTapped = true));
      await tester.pumpAndSettle();

      expect(find.text('Add Account'), findsOneWidget);
      await tester.tap(find.text('Add Account'));
      await tester.pump();
      expect(addTapped, isTrue);
    });

    testWidgets(
      'triggers onManageAccounts callback when Manage Accounts button tapped',
      (tester) async {
        var manageTapped = false;
        await tester.pumpWidget(
          _buildTestApp(onManage: () => manageTapped = true),
        );
        await tester.pumpAndSettle();

        expect(find.text('Manage Accounts'), findsOneWidget);
        await tester.tap(find.text('Manage Accounts'));
        await tester.pump();
        expect(manageTapped, isTrue);
      },
    );
  });
}
