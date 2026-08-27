import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'core/preferences/app_preferences.dart';
import 'core/theme/schoolway_theme.dart';
import 'services/push_messaging_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'core/diagnostics/app_logger.dart';

import 'features/parent/parent_home.dart';
import 'features/driver/driver_home.dart';
import 'features/admin/admin_home.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/auth_choice_screen.dart';
import 'features/auth/account_selection_screen.dart';
import 'features/profile/state/profile_switcher_notifier.dart';
import 'features/shell/onboarding_screen.dart';
// Auth choice is navigated from onboarding; no route needed here
import 'features/auth/change_email_screen.dart';
import 'models/linked_account_profile.dart';
import 'services/saved_accounts_store.dart';

class SchoolWayApp extends ConsumerWidget {
  const SchoolWayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: SchoolWayTheme.light,
      darkTheme: SchoolWayTheme.dark,
      themeMode: preferences.themeMode,
      locale: preferences.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final reduceMotion = switch (preferences.motionPreference) {
          MotionPreference.reduced => true,
          MotionPreference.full => false,
          MotionPreference.system => media.disableAnimations,
        };
        return MediaQuery(
          data: media.copyWith(disableAnimations: reduceMotion),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _StartupGate(),
      routes: {
        ParentHome.routeName: (_) => const ParentHome(),
        DriverHome.routeName: (_) => const DriverHome(),
        AdminHome.routeName: (_) => const AdminHome(),
        SignInScreen.routeName: (_) => const SignInScreen(),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        ChangeEmailScreen.routeName: (_) => const ChangeEmailScreen(),
      },
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await PushMessagingService.initialize().timeout(
        const Duration(seconds: 12),
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'notifications',
        'Notification startup initialization failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const AuthRoleGate();
  }
}

class AuthRoleGate extends ConsumerStatefulWidget {
  const AuthRoleGate({super.key});

  @override
  ConsumerState<AuthRoleGate> createState() => _AuthRoleGateState();
}

class _AuthRoleGateState extends ConsumerState<AuthRoleGate> {
  String? _reloadedForUid;
  String? _reloadRequestedForUid;
  Future<void>? _reloadFuture;

  Future<void> _ensureReload(User user) {
    if (_reloadedForUid == user.uid) {
      return Future.value();
    }
    if (_reloadRequestedForUid == user.uid && _reloadFuture != null) {
      return _reloadFuture!;
    }
    _reloadRequestedForUid = user.uid;
    _reloadFuture = user.reload().catchError((_) {}).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _reloadedForUid = user.uid;
        if (_reloadRequestedForUid == user.uid) {
          _reloadRequestedForUid = null;
          _reloadFuture = null;
        }
      });
    });
    return _reloadFuture!;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = authSnap.data;
        if (user == null) {
          _reloadedForUid = null;
          _reloadRequestedForUid = null;
          _reloadFuture = null;
          final completed = ref.watch(
            appPreferencesProvider.select((value) => value.onboardingCompleted),
          );
          if (!completed) return const OnboardingScreen();
          final savedAccounts = ref.watch(profileSwitcherProvider).accounts;
          return savedAccounts.isNotEmpty
              ? const AccountSelectionScreen()
              : const AuthChoiceScreen();
        }
        // Ensure we have the latest emailVerified before deciding.
        final reloadFuture = _ensureReload(user);

        return FutureBuilder<void>(
          future: reloadFuture,
          builder: (context, reloadSnap) {
            if (reloadSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final docStream = swFirestore
                .collection('users')
                .doc(user.uid)
                .snapshots();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docStream,
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!userSnap.hasData || !userSnap.data!.exists) {
                  return _AwaitingAssignmentScreen(
                    email: user.email,
                    uid: user.uid,
                  );
                }
                final data = userSnap.data!.data()!;
                final role = (data['role'] as String?)?.toLowerCase();
                final firstName = (data['firstName'] as String?)?.trim() ?? '';
                final lastName = (data['lastName'] as String?)?.trim() ?? '';
                final fullName = '$firstName $lastName'.trim();
                final displayName = fullName.isNotEmpty
                    ? fullName
                    : (user.displayName ??
                          user.email?.split('@').first ??
                          'User');

                final isGoogle = user.providerData.any(
                  (p) => p.providerId.toLowerCase().contains('google'),
                );
                final hasPassword = user.providerData.any(
                  (p) => p.providerId.toLowerCase().contains('password'),
                );
                final platform = isGoogle
                    ? AccountPlatform.google
                    : AccountPlatform.email;

                final activeProfile = LinkedAccountProfile(
                  id: user.uid,
                  displayName: displayName,
                  email: user.email ?? '',
                  avatarUrl: user.photoURL,
                  platform: platform,
                  hasGoogleLinked: isGoogle,
                  hasPasswordLinked: hasPassword || !isGoogle,
                  isActive: true,
                  unreadCount: 0,
                  sessionToken: 'session_${user.uid}',
                  lastActiveAt: DateTime.now(),
                  metadata: {'role': role ?? ''},
                );

                SavedAccountsStore.saveAccount(activeProfile);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ref
                        .read(profileSwitcherProvider.notifier)
                        .syncActiveAccount(activeProfile);
                  }
                });

                switch (role) {
                  case 'parent':
                    return const ParentHome();
                  case 'driver':
                    return const DriverHome();
                  case 'admin':
                  case 'administrator':
                    return const AdminHome();
                  default:
                    return _AwaitingAssignmentScreen(
                      email: user.email,
                      uid: user.uid,
                    );
                }
              },
            );
          },
        );
      },
    );
  }
}

class _AwaitingAssignmentScreen extends StatelessWidget {
  const _AwaitingAssignmentScreen({this.email, this.uid});

  final String? email;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: AppBar(
        backgroundColor: SchoolWayTheme.background,
        elevation: 0,
        foregroundColor: SchoolWayTheme.navy,
        title: const Text(
          'SchoolWay',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: SchoolWayTheme.navy,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your account is pending role assignment.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please contact your school administrator and provide them with the Email or UID below so they can assign you a Parent, Driver, or Admin role.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.navy,
                  fontSize: 14,
                ),
              ),
              if (email != null) ...[
                const SizedBox(height: 8),
                Text(
                  email!,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    color: SchoolWayTheme.navy,
                  ),
                ),
              ],
              if (uid != null) ...[
                const SizedBox(height: 8),
                Text(
                  'UID: ${uid!}',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.navy,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Once assigned to Parent, Driver, or Admin, this screen will update automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.navy,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
