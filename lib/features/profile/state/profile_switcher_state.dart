import 'package:flutter/foundation.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Immutable UI state for the Profile Switcher component.
@immutable
class ProfileSwitcherState {
  final List<LinkedAccountProfile> accounts;
  final String? activeAccountId;
  final bool isLoading;
  final bool isSwapping;
  final String? swappingAccountId;
  final String? errorMessage;

  const ProfileSwitcherState({
    this.accounts = const <LinkedAccountProfile>[],
    this.activeAccountId,
    this.isLoading = false,
    this.isSwapping = false,
    this.swappingAccountId,
    this.errorMessage,
  });

  /// Currently active account profile.
  LinkedAccountProfile? get activeAccount {
    if (activeAccountId == null) {
      return accounts.where((a) => a.isActive).firstOrNull ??
          accounts.firstOrNull;
    }
    return accounts.where((a) => a.id == activeAccountId).firstOrNull;
  }

  /// Groups linked accounts by their authentication platform preserving stable order.
  Map<AccountPlatform, List<LinkedAccountProfile>> get groupedByPlatform {
    final grouped = <AccountPlatform, List<LinkedAccountProfile>>{};
    for (final account in accounts) {
      grouped.putIfAbsent(account.platform, () => []).add(account);
    }
    return grouped;
  }

  /// Aggregated unread badge count across all inactive linked accounts.
  int get totalUnreadCount {
    return accounts
        .where((a) => a.id != activeAccountId)
        .fold<int>(0, (sum, a) => sum + a.unreadCount);
  }

  bool get hasAccounts => accounts.isNotEmpty;

  ProfileSwitcherState copyWith({
    List<LinkedAccountProfile>? accounts,
    String? activeAccountId,
    bool? isLoading,
    bool? isSwapping,
    String? swappingAccountId,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileSwitcherState(
      accounts: accounts ?? this.accounts,
      activeAccountId: activeAccountId ?? this.activeAccountId,
      isLoading: isLoading ?? this.isLoading,
      isSwapping: isSwapping ?? this.isSwapping,
      swappingAccountId: isSwapping == false
          ? null
          : (swappingAccountId ?? this.swappingAccountId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProfileSwitcherState &&
        listEquals(other.accounts, accounts) &&
        other.activeAccountId == activeAccountId &&
        other.isLoading == isLoading &&
        other.isSwapping == isSwapping &&
        other.swappingAccountId == swappingAccountId &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(accounts),
    activeAccountId,
    isLoading,
    isSwapping,
    swappingAccountId,
    errorMessage,
  );
}
