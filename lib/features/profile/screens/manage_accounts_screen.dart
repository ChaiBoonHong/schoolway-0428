import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/app.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/bouncing_button.dart';
import 'package:schoolway/features/auth/sign_in_screen.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Screen allowing the user to manage, add, or remove linked/saved accounts on this device.
class ManageAccountsScreen extends ConsumerWidget {
  const ManageAccountsScreen({super.key});

  static const routeName = '/manage-accounts';

  Future<void> _confirmRemoveAccount(
    BuildContext context,
    WidgetRef ref,
    LinkedAccountProfile account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
        ),
        backgroundColor: SchoolWayTheme.surface,
        title: Text(
          l10n.removeAccount,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: SchoolWayTheme.navy,
          ),
        ),
        content: Text(
          '${l10n.removeAccountConfirmation}\n\n${account.displayName} (${account.email})',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            color: SchoolWayTheme.blueGrey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SchoolWayTheme.danger,
              foregroundColor: SchoolWayTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
              ),
            ),
            child: Text(
              l10n.confirmRemove,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final isCurrentActive = account.isActive;
      await ref
          .read(profileSwitcherProvider.notifier)
          .removeAccount(account.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.accountRemoved),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (isCurrentActive && context.mounted) {
        await FirebaseAuth.instance.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthRoleGate()),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(profileSwitcherProvider);
    final accounts = state.accounts;

    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: AppBar(
        backgroundColor: SchoolWayTheme.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: SchoolWayTheme.navy,
          ),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: l10n.cancel,
        ),
        title: Text(
          l10n.manageAccounts,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: SchoolWayTheme.navy,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: SchoolWayTheme.border, height: 1),
        ),
      ),
      body: accounts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.manage_accounts_outlined,
                    size: 64,
                    color: SchoolWayTheme.muted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noSavedAccounts,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15,
                      color: SchoolWayTheme.blueGrey,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: accounts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final isGoogle = account.platform == AccountPlatform.google;
                final platformColor = isGoogle
                    ? SchoolWayTheme.googleBlue
                    : SchoolWayTheme.primary;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: account.isActive
                        ? SchoolWayTheme.subtleBlueSurface
                        : SchoolWayTheme.surface,
                    borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
                    border: Border.all(
                      color: account.isActive
                          ? SchoolWayTheme.primary
                          : SchoolWayTheme.border,
                      width: account.isActive ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: platformColor.withValues(alpha: 0.15),
                        child: Text(
                          account.initials,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: platformColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: SchoolWayTheme.navy,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              account.email,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                color: SchoolWayTheme.blueGrey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isGoogle
                                          ? Icons.g_mobiledata_rounded
                                          : Icons.mail_outline_rounded,
                                      size: 14,
                                      color: platformColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isGoogle
                                          ? l10n.platformGoogle
                                          : l10n.platformEmail,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: platformColor,
                                      ),
                                    ),
                                  ],
                                ),
                                if (account.isActive) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SchoolWayTheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      l10n.activeAccount,
                                      style: const TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: SchoolWayTheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Remove button
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: SchoolWayTheme.danger,
                          size: 22,
                        ),
                        tooltip: l10n.removeAccount,
                        onPressed: () =>
                            _confirmRemoveAccount(context, ref, account),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: BouncingButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
              );
            },
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: SchoolWayTheme.primary,
                borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.person_add_alt_1_outlined,
                    color: SchoolWayTheme.surface,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.addAccount,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: SchoolWayTheme.surface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
