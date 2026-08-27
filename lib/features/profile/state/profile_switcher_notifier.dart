import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/features/profile/state/profile_switcher_state.dart';
import 'package:schoolway/models/linked_account_profile.dart';
import 'package:schoolway/services/saved_accounts_store.dart';
import 'package:schoolway/services/session_swap_service.dart';

/// Provider exposing the session swap service dependency.
final sessionSwapServiceProvider = Provider<SessionSwapService>((ref) {
  return DefaultSessionSwapService();
});

/// Provider for managing linked profiles and active profile switching.
final profileSwitcherProvider =
    NotifierProvider<ProfileSwitcherNotifier, ProfileSwitcherState>(
      ProfileSwitcherNotifier.new,
    );

/// Riverpod Notifier orchestrating real profile listing, token swapping, and error recovery.
class ProfileSwitcherNotifier extends Notifier<ProfileSwitcherState> {
  SessionSwapService get _sessionSwapService =>
      ref.read(sessionSwapServiceProvider);

  StreamSubscription<User?>? _authSubscription;

  @override
  ProfileSwitcherState build() {
    _authSubscription?.cancel();
    try {
      _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
        _syncFromUser(user);
      });
    } catch (error, stackTrace) {
      AppLogger.warning(
        'profile_switcher',
        'Failed to bind userChanges listener.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    return _computeInitialState();
  }

  ProfileSwitcherState _computeInitialState() {
    User? currentUser;
    try {
      currentUser = FirebaseAuth.instance.currentUser;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'profile_switcher',
        'Failed to read currentUser.',
        error: error,
        stackTrace: stackTrace,
      );
      currentUser = null;
    }

    final saved = SavedAccountsStore.readAccounts();
    final currentUid = currentUser?.uid;
    final accounts = <LinkedAccountProfile>[];

    if (currentUser != null && currentUid != null) {
      final isGoogle = currentUser.providerData.any(
        (p) => p.providerId.toLowerCase().contains('google'),
      );
      final hasPassword = currentUser.providerData.any(
        (p) => p.providerId.toLowerCase().contains('password'),
      );
      final platform = isGoogle
          ? AccountPlatform.google
          : AccountPlatform.email;

      final savedActive = saved.where((s) => s.id == currentUid).firstOrNull;
      final currentName =
          (currentUser.displayName != null &&
              currentUser.displayName!.trim().isNotEmpty)
          ? currentUser.displayName!.trim()
          : (savedActive != null && savedActive.displayName.isNotEmpty)
          ? savedActive.displayName
          : (currentUser.email?.split('@').first ?? 'User');

      final activeProfile = LinkedAccountProfile(
        id: currentUid,
        displayName: currentName,
        email: currentUser.email ?? '',
        avatarUrl: currentUser.photoURL,
        platform: platform,
        hasGoogleLinked: isGoogle,
        hasPasswordLinked: hasPassword || !isGoogle,
        isActive: true,
        unreadCount: 0,
        sessionToken: 'session_$currentUid',
        lastActiveAt: DateTime.now(),
        metadata: savedActive?.metadata ?? const {},
      );

      accounts.add(activeProfile);
      SavedAccountsStore.saveAccount(activeProfile);

      // Add other previously saved real accounts from this device
      for (final other in saved) {
        if (other.id != currentUid) {
          accounts.add(other.copyWith(isActive: false));
        }
      }
    } else {
      accounts.addAll(saved);
    }

    final activeId =
        accounts.where((a) => a.isActive).firstOrNull?.id ??
        accounts.firstOrNull?.id;

    return ProfileSwitcherState(
      accounts: accounts,
      activeAccountId: activeId,
      isLoading: false,
    );
  }

  void _syncFromUser(User? user) {
    if (user == null) {
      final saved = SavedAccountsStore.readAccounts();
      final updated = saved.map((a) => a.copyWith(isActive: false)).toList();
      state = state.copyWith(
        accounts: updated,
        activeAccountId: null,
        clearError: true,
      );
      return;
    }

    final saved = SavedAccountsStore.readAccounts();
    final isGoogle = user.providerData.any(
      (p) => p.providerId.toLowerCase().contains('google'),
    );
    final hasPassword = user.providerData.any(
      (p) => p.providerId.toLowerCase().contains('password'),
    );
    final platform = isGoogle ? AccountPlatform.google : AccountPlatform.email;

    final savedActive = saved.where((s) => s.id == user.uid).firstOrNull;
    final currentName =
        (user.displayName != null && user.displayName!.trim().isNotEmpty)
        ? user.displayName!.trim()
        : (savedActive != null && savedActive.displayName.isNotEmpty)
        ? savedActive.displayName
        : (user.email?.split('@').first ?? 'User');

    final activeProfile = LinkedAccountProfile(
      id: user.uid,
      displayName: currentName,
      email: user.email ?? '',
      avatarUrl: user.photoURL,
      platform: platform,
      hasGoogleLinked: isGoogle,
      hasPasswordLinked: hasPassword || !isGoogle,
      isActive: true,
      unreadCount: 0,
      sessionToken: 'session_${user.uid}',
      lastActiveAt: DateTime.now(),
      metadata: savedActive?.metadata ?? const {},
    );

    SavedAccountsStore.saveAccount(activeProfile);
    SavedAccountsStore.setActive(user.uid);

    final accounts = <LinkedAccountProfile>[activeProfile];
    for (final other in saved) {
      if (other.id != user.uid) {
        accounts.add(other.copyWith(isActive: false));
      }
    }

    state = state.copyWith(
      accounts: accounts,
      activeAccountId: user.uid,
      clearError: true,
    );
  }

  /// Synchronizes the active account with updated metadata (e.g. role from Firestore).
  Future<void> syncActiveAccount(LinkedAccountProfile profile) async {
    await SavedAccountsStore.saveAccount(profile);
    await SavedAccountsStore.setActive(profile.id);

    final updated = <LinkedAccountProfile>[];
    var found = false;
    for (final acc in state.accounts) {
      if (acc.id == profile.id) {
        updated.add(profile.copyWith(isActive: true));
        found = true;
      } else {
        updated.add(acc.copyWith(isActive: false));
      }
    }
    if (!found) {
      updated.insert(0, profile.copyWith(isActive: true));
    }
    state = state.copyWith(
      accounts: updated,
      activeAccountId: profile.id,
      clearError: true,
    );
  }

  /// Sets accounts manually (e.g. for testing or external sync).
  void setAccounts(List<LinkedAccountProfile> accounts, {String? activeId}) {
    final effectiveActiveId =
        activeId ??
        accounts.where((a) => a.isActive).firstOrNull?.id ??
        accounts.firstOrNull?.id;

    state = state.copyWith(
      accounts: accounts,
      activeAccountId: effectiveActiveId,
      clearError: true,
    );
  }

  /// Adds a real account to the switcher and persists it.
  Future<void> addAccount(LinkedAccountProfile profile) async {
    final updated = List<LinkedAccountProfile>.from(state.accounts);
    final index = updated.indexWhere((a) => a.id == profile.id);
    if (index >= 0) {
      updated[index] = profile;
    } else {
      updated.add(profile);
    }
    await SavedAccountsStore.saveAccount(profile);
    state = state.copyWith(accounts: updated);
  }

  /// Removes an account from the switcher and local storage.
  Future<void> removeAccount(String accountId) async {
    final updated = state.accounts.where((a) => a.id != accountId).toList();
    await SavedAccountsStore.removeAccount(accountId);
    state = state.copyWith(
      accounts: updated,
      activeAccountId: state.activeAccountId == accountId
          ? updated.firstOrNull?.id
          : state.activeAccountId,
    );
  }

  /// Selects and switches the active account session with token/credential swapping.
  Future<bool> selectAccount(String accountId, {String? password}) async {
    if (state.activeAccountId == accountId) {
      return true; // Already active
    }

    final targetAccount = state.accounts
        .where((a) => a.id == accountId)
        .firstOrNull;
    if (targetAccount == null) {
      state = state.copyWith(errorMessage: 'Selected profile does not exist.');
      return false;
    }

    final currentAccount = state.activeAccount;
    state = state.copyWith(
      isSwapping: true,
      swappingAccountId: accountId,
      clearError: true,
    );

    try {
      final result = await _sessionSwapService.swapSession(
        targetAccount: targetAccount,
        currentToken: currentAccount?.sessionToken,
        password: password,
      );

      if (!result.success) {
        throw const SessionSwapExpiredException('Session swap rejected.');
      }

      // Update state with newly active profile and refreshed token/timestamps
      final updatedList = state.accounts.map((acc) {
        if (acc.id == accountId) {
          return acc.copyWith(
            isActive: true,
            sessionToken: result.newSessionToken,
            lastActiveAt: result.swappedAt,
          );
        } else if (acc.isActive) {
          return acc.copyWith(isActive: false);
        }
        return acc;
      }).toList();

      await SavedAccountsStore.setActive(accountId);

      state = state.copyWith(
        accounts: updatedList,
        activeAccountId: accountId,
        isSwapping: false,
        clearError: true,
      );

      AppLogger.info(
        'profile_switcher',
        'Switched active account to: ${targetAccount.displayName} (${targetAccount.id})',
      );
      return true;
    } on SessionSwapExpiredException catch (e, st) {
      AppLogger.warning(
        'profile_switcher',
        'Session expired during account swap',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(isSwapping: false, errorMessage: e.message);
      return false;
    } on SessionSwapNetworkException catch (e, st) {
      AppLogger.warning(
        'profile_switcher',
        'Network error during account swap',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(isSwapping: false, errorMessage: e.message);
      return false;
    } on SessionSwapUnauthorizedException catch (e, st) {
      AppLogger.warning(
        'profile_switcher',
        'Unauthorized account swap attempt',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(isSwapping: false, errorMessage: e.message);
      return false;
    } catch (e, st) {
      AppLogger.error(
        'profile_switcher',
        'Unexpected error swapping profile',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(
        isSwapping: false,
        errorMessage: 'Failed to switch profile: $e',
      );
      return false;
    }
  }

  /// Reauthenticates a saved account from the logged-out account picker.
  Future<bool> authenticateAccount(
    String accountId, {
    required AccountAuthenticationMethod method,
    String? password,
  }) async {
    final targetAccount = state.accounts
        .where((account) => account.id == accountId)
        .firstOrNull;
    if (targetAccount == null) {
      state = state.copyWith(errorMessage: 'Selected profile does not exist.');
      return false;
    }

    state = state.copyWith(
      isSwapping: true,
      swappingAccountId: accountId,
      clearError: true,
    );

    try {
      final result = await _sessionSwapService.swapSession(
        targetAccount: targetAccount,
        currentToken: null,
        authenticationMethod: method,
        password: password,
      );
      if (!result.success) {
        throw const SessionSwapExpiredException('Account sign-in rejected.');
      }

      final updated = state.accounts.map((account) {
        return account.copyWith(
          isActive: account.id == accountId,
          sessionToken: account.id == accountId
              ? result.newSessionToken
              : account.sessionToken,
          lastActiveAt: account.id == accountId
              ? result.swappedAt
              : account.lastActiveAt,
        );
      }).toList();
      await SavedAccountsStore.setActive(accountId);
      state = state.copyWith(
        accounts: updated,
        activeAccountId: accountId,
        isSwapping: false,
        clearError: true,
      );
      return true;
    } on SessionSwapException catch (error, stackTrace) {
      AppLogger.warning(
        'profile_switcher',
        'Saved account authentication failed',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(isSwapping: false, errorMessage: error.message);
      return false;
    } catch (error, stackTrace) {
      AppLogger.error(
        'profile_switcher',
        'Unexpected saved account authentication failure',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        isSwapping: false,
        errorMessage: 'Failed to sign in to the selected account.',
      );
      return false;
    }
  }

  /// Dismisses any active error notification.
  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }
}
