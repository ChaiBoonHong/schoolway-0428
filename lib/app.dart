import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/init/permissions.dart';
import 'core/theme/schoolway_theme.dart';
import 'services/push_messaging_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

import 'features/parent/parent_home.dart';
import 'features/driver/driver_home.dart';
import 'features/admin/admin_home.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/shell/onboarding_screen.dart';
// Auth choice is navigated from onboarding; no route needed here
import 'features/auth/change_email_screen.dart';

class SchoolWayApp extends StatelessWidget {
  const SchoolWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'SchoolWay',
        debugShowCheckedModeBanner: false,
        theme: SchoolWayTheme.light,
        home: const _StartupGate(),
        routes: {
          ParentHome.routeName: (_) => const ParentHome(),
          DriverHome.routeName: (_) => const DriverHome(),
          AdminHome.routeName: (_) => const AdminHome(),
          SignInScreen.routeName: (_) => const SignInScreen(),
          OnboardingScreen.routeName: (_) => const OnboardingScreen(),
          ChangeEmailScreen.routeName: (_) => const ChangeEmailScreen(),
        },
      ),
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
      await Future.wait([
        AppPermissions.requestEssentialPermissions().timeout(
          const Duration(seconds: 12),
        ),
        PushMessagingService.initialize().timeout(const Duration(seconds: 12)),
      ]);
    } catch (e) {
      debugPrint('StartupGate init error: $e');
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

class AuthRoleGate extends StatefulWidget {
  const AuthRoleGate({super.key});

  @override
  State<AuthRoleGate> createState() => _AuthRoleGateState();
}

class _AuthRoleGateState extends State<AuthRoleGate> {
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
          return const OnboardingScreen();
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

            // Query user by authUid to get username (document ID).
            final docStream = swFirestore
                .collection('users')
                .where('authUid', isEqualTo: user.uid)
                .limit(1)
                .snapshots();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: docStream,
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!userSnap.hasData || userSnap.data!.docs.isEmpty) {
                  return _AwaitingAssignmentScreen(
                    email: user.email,
                    uid: user.uid,
                  );
                }
                final data = userSnap.data!.docs.first.data();
                final role = (data['role'] as String?)?.toLowerCase();
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
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: const Text(
          'SchoolWay',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
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
                  color: Color(0xFF03045E),
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
                  color: Color(0xFF03045E),
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
                    color: Color(0xFF03045E),
                  ),
                ),
              ],
              if (uid != null) ...[
                const SizedBox(height: 8),
                Text(
                  'UID: ${uid!}',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Color(0xFF03045E),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Once assigned to Parent, Driver, or Admin, this screen will update automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: Color(0xFF03045E),
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
