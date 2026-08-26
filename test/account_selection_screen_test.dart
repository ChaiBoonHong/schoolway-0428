import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/auth/account_selection_screen.dart';
import 'package:schoolway/features/auth/sign_in_screen.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/features/profile/state/profile_switcher_state.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';
import 'package:schoolway/services/session_swap_service.dart';

class FakeAccountAuthenticationService implements SessionSwapService {
  AccountAuthenticationMethod? lastMethod;

  @override
  Future<SessionSwapResult> swapSession({
    required LinkedAccountProfile targetAccount,
    required String? currentToken,
    AccountAuthenticationMethod? authenticationMethod,
    String? password,
  }) async {
    lastMethod = authenticationMethod;
    return SessionSwapResult(
      success: true,
      newSessionToken: 'session_${targetAccount.id}',
      swappedAt: DateTime(2026, 8, 27),
    );
  }
}

class MockAccountSelectionNotifier extends ProfileSwitcherNotifier {
  MockAccountSelectionNotifier(this.accounts);

  final List<LinkedAccountProfile> accounts;

  @override
  ProfileSwitcherState build() => ProfileSwitcherState(
    accounts: accounts,
    activeAccountId: accounts.firstOrNull?.id,
    isLoading: false,
  );
}

const emailAccount = LinkedAccountProfile(
  id: 'email_account',
  displayName: 'Aiman Khalid',
  email: 'aiman@schoolway.my',
  platform: AccountPlatform.email,
  hasPasswordLinked: true,
  metadata: {'role': 'parent'},
);

const dualAccount = LinkedAccountProfile(
  id: 'dual_account',
  displayName: 'Admin Schoolway',
  email: 'admin@schoolway.com',
  platform: AccountPlatform.google,
  hasGoogleLinked: true,
  hasPasswordLinked: true,
  metadata: {'role': 'admin'},
);

Widget buildTestApp({
  List<LinkedAccountProfile> accounts = const [emailAccount, dualAccount],
  FakeAccountAuthenticationService? authenticationService,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return ProviderScope(
    overrides: [
      profileSwitcherProvider.overrideWith(
        () => MockAccountSelectionNotifier(accounts),
      ),
      sessionSwapServiceProvider.overrideWithValue(
        authenticationService ?? FakeAccountAuthenticationService(),
      ),
    ],
    child: MaterialApp(
      theme: SchoolWayTheme.light,
      darkTheme: SchoolWayTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AccountSelectionScreen(),
    ),
  );
}

void main() {
  group('AccountSelectionScreen', () {
    testWidgets('renders one recency-sorted list without platform headers', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Select an account to log in'), findsOneWidget);
      expect(find.text('Aiman Khalid'), findsOneWidget);
      expect(find.text('Admin Schoolway'), findsOneWidget);
      expect(find.text('SchoolWay Account (Email)'), findsNothing);
      expect(find.text('Google Account'), findsNothing);
    });

    testWidgets('email-only account opens the password dialog', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aiman Khalid'));
      await tester.pumpAndSettle();

      expect(find.text('Enter password to switch account'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('dual-linked account offers both sign-in methods', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Admin Schoolway'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Sign-in Method'), findsOneWidget);
      expect(find.text('Enter Password'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('password choice opens the password dialog', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Admin Schoolway'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter Password'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('another account action navigates to sign in', (tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log into another account'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('removing an account confirms and updates the list', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Account').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Are you sure you want to remove this account from this device?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Aiman Khalid'), findsNothing);
      expect(find.text('Admin Schoolway'), findsOneWidget);
    });

    for (final size in <Size>[
      const Size(390, 844),
      const Size(800, 1000),
      const Size(1280, 900),
    ]) {
      testWidgets('renders without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildTestApp(themeMode: ThemeMode.dark));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
