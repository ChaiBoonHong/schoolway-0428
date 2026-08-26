import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/app_modal_sheet.dart';
import 'package:schoolway/features/auth/sign_in_screen.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/features/shell/app_settings_screen.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Production-grade modal bottom sheet for switching active profiles across linked accounts.
class ProfileSwitcherSheet extends ConsumerWidget {
  const ProfileSwitcherSheet({
    super.key,
    this.onManageAccounts,
    this.onAddAccount,
  });

  final VoidCallback? onManageAccounts;
  final VoidCallback? onAddAccount;

  /// Convenience presentation method.
  static Future<void> show(
    BuildContext context, {
    VoidCallback? onManageAccounts,
    VoidCallback? onAddAccount,
  }) {
    return showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: ProfileSwitcherSheet(
          onManageAccounts: onManageAccounts,
          onAddAccount: onAddAccount,
        ),
      ),
    );
  }

  String _platformLabel(AccountPlatform platform, AppLocalizations l10n) {
    switch (platform) {
      case AccountPlatform.email:
        return l10n.platformEmail;
      case AccountPlatform.google:
        return l10n.platformGoogle;
    }
  }

  IconData _platformIcon(AccountPlatform platform) {
    switch (platform) {
      case AccountPlatform.email:
        return Icons.mail_outline_rounded;
      case AccountPlatform.google:
        return Icons.g_mobiledata_rounded;
    }
  }

  Color _platformColor(AccountPlatform platform) {
    switch (platform) {
      case AccountPlatform.email:
        return SchoolWayTheme.primary;
      case AccountPlatform.google:
        return SchoolWayTheme.googleBlue;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(profileSwitcherProvider);
    final notifier = ref.read(profileSwitcherProvider.notifier);
    final l10n = AppLocalizations.of(context);

    final grouped = state.groupedByPlatform;
    final activeId = state.activeAccountId;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: SchoolWayTheme.surface,
          borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
          boxShadow: const [
            BoxShadow(
              color: SchoolWayTheme.text12,
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle & Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: SchoolWayTheme.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.switchProfile,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.linkedAccounts,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                color: SchoolWayTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: SchoolWayTheme.muted,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: l10n.cancel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: SchoolWayTheme.border, height: 1),

            // Error Banner (if any)
            if (state.errorMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                decoration: BoxDecoration(
                  color: SchoolWayTheme.dangerSurface,
                  borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
                  border: Border.all(
                    color: SchoolWayTheme.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: SchoolWayTheme.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.danger,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: SchoolWayTheme.danger,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: notifier.clearError,
                    ),
                  ],
                ),
              ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Grouped Accounts List
                    ...grouped.entries.map((entry) {
                      final platform = entry.key;
                      final accounts = entry.value;
                      final label = _platformLabel(platform, l10n);
                      final icon = _platformIcon(platform);
                      final color = _platformColor(platform);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Platform Section Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                            child: Row(
                              children: [
                                Icon(icon, size: 16, color: color),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: color,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${accounts.length}',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Account Cards
                          ...accounts.map((account) {
                            final isActive = account.id == activeId;
                            final isSwappingThis =
                                state.isSwapping &&
                                state.swappingAccountId == account.id;

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? SchoolWayTheme.subtleBlueSurface
                                    : SchoolWayTheme.surface,
                                borderRadius: BorderRadius.circular(
                                  SchoolWayTheme.radius,
                                ),
                                border: Border.all(
                                  color: isActive
                                      ? SchoolWayTheme.primary
                                      : SchoolWayTheme.border,
                                  width: isActive ? 1.5 : 1.0,
                                ),
                              ),
                              child: Material(
                                color: SchoolWayTheme.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    SchoolWayTheme.radius,
                                  ),
                                  onTap: state.isSwapping
                                      ? null
                                      : () async {
                                          if (isActive) {
                                            Navigator.of(context).pop();
                                            return;
                                          }
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final success = await notifier
                                              .selectAccount(account.id);
                                          if (success && context.mounted) {
                                            Navigator.of(context).pop();
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  l10n.switchedProfileTo(
                                                    account.displayName,
                                                  ),
                                                ),
                                                duration: const Duration(
                                                  seconds: 2,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        // Avatar / Monogram
                                        _AccountAvatar(
                                          account: account,
                                          platformColor: color,
                                        ),
                                        const SizedBox(width: 12),

                                        // Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                account.displayName,
                                                style: TextStyle(
                                                  fontFamily: 'Lexend',
                                                  fontWeight: isActive
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                                  fontSize: 14,
                                                  color: SchoolWayTheme.navy,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  if (isActive) ...[
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 1,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            right: 6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: SchoolWayTheme
                                                            .primary
                                                            .withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        l10n.activeAccount,
                                                        style: const TextStyle(
                                                          fontFamily: 'Lexend',
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: SchoolWayTheme
                                                              .primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      account.email,
                                                      style: const TextStyle(
                                                        fontFamily: 'Lexend',
                                                        fontSize: 12,
                                                        color: SchoolWayTheme
                                                            .blueGrey,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Unread Badge
                                        if (account.unreadCount > 0) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: SchoolWayTheme.danger,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${account.unreadCount}',
                                              style: const TextStyle(
                                                fontFamily: 'Lexend',
                                                fontSize: 11,
                                                color: SchoolWayTheme.surface,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],

                                        // Trailing Status Indicator
                                        const SizedBox(width: 8),
                                        if (isSwappingThis)
                                          const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: SchoolWayTheme.primary,
                                            ),
                                          )
                                        else if (isActive)
                                          Container(
                                            width: 26,
                                            height: 26,
                                            decoration: const BoxDecoration(
                                              color: SchoolWayTheme.primary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              color: SchoolWayTheme.surface,
                                              size: 16,
                                            ),
                                          )
                                        else
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: SchoolWayTheme.borderSubtle,
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }),

                    const SizedBox(height: 12),

                    // Add Account Action Tile
                    Material(
                      color: SchoolWayTheme.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          SchoolWayTheme.radius,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          if (onAddAccount != null) {
                            onAddAccount!.call();
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SignInScreen(),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: SchoolWayTheme.subtleCyanSurface,
                            borderRadius: BorderRadius.circular(
                              SchoolWayTheme.radius,
                            ),
                            border: Border.all(
                              color: SchoolWayTheme.borderStrong,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.person_add_alt_1_outlined,
                                color: SchoolWayTheme.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.addAccount,
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: SchoolWayTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer: Manage Accounts Button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onManageAccounts != null) {
                    onManageAccounts!.call();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AppSettingsScreen(),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: SchoolWayTheme.navy,
                  side: const BorderSide(color: SchoolWayTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: const Icon(Icons.manage_accounts_outlined, size: 20),
                label: Text(
                  l10n.manageAccounts,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar helper widget showing an image or monogram initials.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account, required this.platformColor});

  final LinkedAccountProfile account;
  final Color platformColor;

  @override
  Widget build(BuildContext context) {
    if (account.avatarUrl != null && account.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: platformColor.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(account.avatarUrl!),
        onBackgroundImageError: (_, _) {},
        child: Text(
          account.initials,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: platformColor,
          ),
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: platformColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: platformColor.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        account.initials,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: platformColor,
        ),
      ),
    );
  }
}
