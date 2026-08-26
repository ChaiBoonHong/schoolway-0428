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

    final defaultProfiles = <LinkedAccountProfile>[
      LinkedAccountProfile(
        id: currentUid,
        displayName: currentName,
        email: currentEmail,
        platform: AccountPlatform.schoolWaySso,
        isActive: true,
        unreadCount: 0,
        sessionToken: 'sso_active_token_9921',
        lastActiveAt: DateTime.now(),
      ),
      LinkedAccountProfile(
        id: 'acc_parent_sso',
        displayName: 'Ahmad Faiz (Parent)',
        email: 'parent.faiz@schoolway.my',
        platform: AccountPlatform.schoolWaySso,
        isActive: false,
        unreadCount: 0,
        sessionToken: 'sso_parent_token_9921',
        lastActiveAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      LinkedAccountProfile(
        id: 'acc_admin_google',
        displayName: 'Faiz Admin',
        email: 'faiz.admin@schoolportal.edu.my',
        platform: AccountPlatform.google,
        isActive: false,
        unreadCount: 3,
        sessionToken: 'google_workspace_token_4812',
        lastActiveAt: DateTime.now().subtract(const Duration(hours: 2)),
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
      ),
    ];

    final activeId =
        defaultProfiles.where((p) => p.isActive).firstOrNull?.id ??
        defaultProfiles.firstOrNull?.id;

    return ProfileSwitcherState(
      accounts: defaultProfiles,
      activeAccountId: activeId,
      isLoading: false,
    );
  }

  /// Sets accounts manually (e.g. for testing or external sync).
  void setAccounts(List<LinkedAccountProfile> accounts, {String? activeId}) {
    final effectiveActiveId =
        activeId ??
        accounts.where((a) => a.isActive).firstOrNull?.id ??
        accounts.firstOrNull?.id;

    final updated = accounts.map((a) {
      return a.copyWith(isActive: a.id == effectiveActiveId);
    }).toList();

    state = state.copyWith(
      accounts: updated,
      activeAccountId: effectiveActiveId,
      clearError: true,
    );
  }

  /// Selects a linked account and performs a secure session token swap.
  /// Returns `true` if the swap succeeded, or `false` on failure.
  Future<bool> selectAccount(String targetAccountId) async {
    if (state.isSwapping) return false;
    if (state.activeAccountId == targetAccountId) return true;

    final target = state.accounts
        .where((a) => a.id == targetAccountId)
        .firstOrNull;
    if (target == null) {
      state = state.copyWith(errorMessage: 'Target account not found.');
      return false;
    }

    final previousActiveId = state.activeAccountId;
    final currentToken = state.activeAccount?.sessionToken;

    state = state.copyWith(
      isSwapping: true,
      swappingAccountId: targetAccountId,
      clearError: true,
    );

    try {
      final result = await _sessionSwapService.swapSession(
        targetAccount: target,
        currentToken: currentToken,
      );

      if (!result.success) {
        throw SessionSwapUnauthorizedException(
          result.message ?? 'Session swap failed.',
        );
      }

      // Update active flags across all accounts
      final updatedAccounts = state.accounts.map((acc) {
        final isNowActive = acc.id == targetAccountId;
        return acc.copyWith(
          isActive: isNowActive,
          lastActiveAt: isNowActive ? DateTime.now() : acc.lastActiveAt,
        );
      }).toList();

      state = state.copyWith(
        accounts: updatedAccounts,
        activeAccountId: targetAccountId,
        isSwapping: false,
        swappingAccountId: null,
      );

      AppLogger.info(
        'profile_switcher',
        'Swapped active profile to $targetAccountId (${target.displayName})',
      );
      return true;
    } on SessionSwapException catch (e) {
      AppLogger.warning(
        'profile_switcher',
        'Session swap failed for target $targetAccountId: $e',
      );
      state = state.copyWith(
        isSwapping: false,
        swappingAccountId: null,
        activeAccountId: previousActiveId,
        errorMessage: e.message,
      );
      return false;
    } catch (e, st) {
      AppLogger.error(
        'profile_switcher',
        'Unexpected error swapping profile to $targetAccountId',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(
        isSwapping: false,
        swappingAccountId: null,
        activeAccountId: previousActiveId,
        errorMessage: 'An unexpected error occurred while switching profiles.',
      );
      return false;
    }
  }

  /// Appends or updates a newly linked profile account.
  void linkAccount(LinkedAccountProfile newAccount) {
    final existingIndex = state.accounts.indexWhere(
      (a) => a.id == newAccount.id,
    );
    final updatedList = List<LinkedAccountProfile>.from(state.accounts);

    if (existingIndex >= 0) {
      updatedList[existingIndex] = newAccount;
    } else {
      updatedList.add(newAccount);
    }

    state = state.copyWith(accounts: updatedList);
  }

  /// Removes an unlinked profile from the list.
  void removeAccount(String accountId) {
    final updatedList = state.accounts.where((a) => a.id != accountId).toList();
    var nextActiveId = state.activeAccountId;
    if (nextActiveId == accountId) {
      nextActiveId = updatedList.firstOrNull?.id;
    }

    state = state.copyWith(
      accounts: updatedList,
      activeAccountId: nextActiveId,
    );
  }

  /// Clears any active error message in the UI state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
