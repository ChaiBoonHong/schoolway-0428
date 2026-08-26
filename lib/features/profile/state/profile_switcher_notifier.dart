import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/features/profile/state/profile_switcher_state.dart';
import 'package:schoolway/models/linked_account_profile.dart';
import 'package:schoolway/services/session_swap_service.dart';

/// Provider exposing the session swap service dependency.
final sessionSwapServiceProvider = Provider<SessionSwapService>((ref) {
  return const DefaultSessionSwapService();
});

/// Provider for managing linked profiles and active profile switching.
final profileSwitcherProvider =
    NotifierProvider<ProfileSwitcherNotifier, ProfileSwitcherState>(
      ProfileSwitcherNotifier.new,
    );

/// Riverpod Notifier orchestrating profile listing, token swapping, and error recovery.
class ProfileSwitcherNotifier extends Notifier<ProfileSwitcherState> {
  SessionSwapService get _sessionSwapService =>
      ref.read(sessionSwapServiceProvider);

  @override
  ProfileSwitcherState build() {
    User? currentUser;
    try {
      currentUser = FirebaseAuth.instance.currentUser;
    } catch (_) {
      currentUser = null;
    }

    final currentUid = currentUser?.uid ?? 'acc_admin_active';
    final currentEmail = currentUser?.email ?? 'admin@schoolway.my';
    final currentName =
        (currentUser?.displayName != null &&
            currentUser!.displayName!.trim().isNotEmpty)
        ? currentUser.displayName!.trim()
        : 'Admin Schoolway';

    final isGoogle =
        currentUser?.providerData.any(
          (p) => p.providerId.toLowerCase().contains('google'),
        ) ??
        false;

    final primaryActiveProfile = LinkedAccountProfile(
      id: currentUid,
      displayName: currentName,
      email: currentEmail,
      avatarUrl: currentUser?.photoURL,
      platform: isGoogle
          ? AccountPlatform.google
          : AccountPlatform.schoolWaySso,
      isActive: true,
      unreadCount: 0,
      sessionToken: 'session_$currentUid',
      lastActiveAt: DateTime.now(),
      metadata: const {'role': 'admin'},
    );

    final defaultProfiles = <LinkedAccountProfile>[
      primaryActiveProfile,
      LinkedAccountProfile(
        id: 'acc_parent_sso',
        displayName: 'Ahmad Faiz (Parent)',
        email: 'parent.faiz@schoolway.my',
        platform: AccountPlatform.schoolWaySso,
        isActive: false,
        unreadCount: 0,
        sessionToken: 'sso_parent_token_9921',
        lastActiveAt: DateTime.now().subtract(const Duration(hours: 2)),
        metadata: const {'role': 'parent'},
      ),
      LinkedAccountProfile(
        id: 'acc_driver_sso',
        displayName: 'Ahmad Faiz (Driver)',
        email: 'driver.faiz@schoolway.my',
        platform: AccountPlatform.schoolWaySso,
        isActive: false,
        unreadCount: 1,
        sessionToken: 'sso_driver_token_1104',
        lastActiveAt: DateTime.now().subtract(const Duration(days: 1)),
        metadata: const {'role': 'driver'},
      ),
      LinkedAccountProfile(
        id: 'acc_google_workspace',
        displayName: 'Faiz Education Admin',
        email: 'faiz.admin@schoolportal.edu.my',
        platform: AccountPlatform.google,
        isActive: false,
        unreadCount: 3,
        sessionToken: 'google_workspace_token_4812',
        lastActiveAt: DateTime.now().subtract(const Duration(hours: 5)),
        metadata: const {'role': 'admin'},
      ),
      LinkedAccountProfile(
        id: 'acc_faculty_ms',
        displayName: 'Faiz Lecturer',
        email: 'faiz@university.edu.my',
        platform: AccountPlatform.microsoft,
        isActive: false,
        unreadCount: 0,
        sessionToken: 'ms_token_9931',
        lastActiveAt: DateTime.now().subtract(const Duration(days: 3)),
        metadata: const {'role': 'admin'},
      ),
    ];

    return ProfileSwitcherState(
      accounts: defaultProfiles,
      activeAccountId: currentUid,
      isLoading: false,
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

  /// Selects and switches the active account session with token swapping.
  Future<bool> selectAccount(String accountId) async {
    if (state.activeAccountId == accountId) {
      return true; // Already active
    }

    final targetAccount = state.accounts
        .where((a) => a.id == accountId)
        .firstOrNull;
    if (targetAccount == null) {
      state = state.copyWith(
        errorMessage: 'Selected profile does not exist.',
      );
      return false;
    }

    final currentAccount = state.activeAccount;
    state = state.copyWith(isSwapping: true, clearError: true);

    try {
      final result = await _sessionSwapService.swapSession(
        targetAccount: targetAccount,
        currentToken: currentAccount?.sessionToken,
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
      state = state.copyWith(
        isSwapping: false,
        errorMessage: e.message,
      );
      return false;
    } on SessionSwapNetworkException catch (e, st) {
      AppLogger.warning(
        'profile_switcher',
        'Network error during account swap',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(
        isSwapping: false,
        errorMessage: e.message,
      );
      return false;
    } on SessionSwapUnauthorizedException catch (e, st) {
      AppLogger.warning(
        'profile_switcher',
        'Unauthorized account swap attempt',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(
        isSwapping: false,
        errorMessage: e.message,
      );
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

  /// Dismisses any active error notification.
  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }
}
