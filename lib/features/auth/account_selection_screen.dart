import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/auth/sign_in_screen.dart';
import 'package:schoolway/features/profile/state/profile_switcher_notifier.dart';
import 'package:schoolway/features/profile/widgets/account_switch_password_dialog.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';
import 'package:schoolway/services/session_swap_service.dart';

class AccountSelectionScreen extends ConsumerStatefulWidget {
  const AccountSelectionScreen({super.key});

  @override
  ConsumerState<AccountSelectionScreen> createState() =>
      _AccountSelectionScreenState();
}

class _AccountSelectionScreenState
    extends ConsumerState<AccountSelectionScreen> {
  Future<void> _selectAccount(LinkedAccountProfile account) async {
    final canPop = Navigator.of(context).canPop();
    if (account.id == ref.read(profileSwitcherProvider).activeAccountId) {
      if (canPop) {
        Navigator.of(context).pop();
        return;
      }
    }

    final hasGoogle =
        account.hasGoogleLinked ||
        (!account.hasPasswordLinked &&
            account.platform == AccountPlatform.google);
    final hasPassword =
        account.hasPasswordLinked ||
        (!account.hasGoogleLinked && account.platform == AccountPlatform.email);

    if (hasGoogle && hasPassword) {
      await _showAuthenticationMethods(account);
    } else if (hasGoogle) {
      await _authenticateWithGoogle(account);
    } else {
      await _authenticateWithPassword(account);
    }
  }

  Future<void> _showAuthenticationMethods(LinkedAccountProfile account) async {
    final l10n = AppLocalizations.of(context);
    final method = await showModalBottomSheet<AccountAuthenticationMethod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: SchoolWayTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SchoolWayTheme.radiusLarge),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.chooseAuthMethod,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: SchoolWayTheme.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                account.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.muted,
                ),
              ),
              const SizedBox(height: 16),
              _AuthenticationMethodTile(
                icon: Icons.password_rounded,
                title: l10n.signInWithPassword,
                subtitle: l10n.signInWithPasswordSubtitle,
                onTap: () => Navigator.pop(
                  sheetContext,
                  AccountAuthenticationMethod.password,
                ),
              ),
              const SizedBox(height: 12),
              _AuthenticationMethodTile(
                icon: Icons.language_rounded,
                title: l10n.signInWithGoogle,
                subtitle: l10n.signInWithGoogleSubtitle,
                onTap: () => Navigator.pop(
                  sheetContext,
                  AccountAuthenticationMethod.google,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || method == null) return;
    if (method == AccountAuthenticationMethod.password) {
      await _authenticateWithPassword(account);
    } else {
      await _authenticateWithGoogle(account);
    }
  }

  Future<void> _authenticateWithPassword(LinkedAccountProfile account) async {
    final success = await AccountSwitchPasswordDialog.show(
      context,
      account: account,
      onAuthenticate: (password) => ref
          .read(profileSwitcherProvider.notifier)
          .authenticateAccount(
            account.id,
            method: AccountAuthenticationMethod.password,
            password: password,
          ),
    );
    if (!mounted) return;
    if (success == true && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _authenticateWithGoogle(LinkedAccountProfile account) async {
    final success = await ref
        .read(profileSwitcherProvider.notifier)
        .authenticateAccount(
          account.id,
          method: AccountAuthenticationMethod.google,
        );
    if (!mounted) return;
    if (success) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    final message = ref.read(profileSwitcherProvider).errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _removeAccount(LinkedAccountProfile account) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeAccount),
        content: Text(l10n.removeAccountConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(profileSwitcherProvider.notifier).removeAccount(account.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.accountRemoved)));
  }

  void _openSignIn() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canPop = Navigator.of(context).canPop();
    final state = ref.watch(profileSwitcherProvider);
    final accounts = [...state.accounts]
      ..sort((left, right) {
        final leftDate =
            left.lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.lastActiveAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: canPop
          ? AppBar(
              backgroundColor: SchoolWayTheme.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: SchoolWayTheme.navy,
                ),
                tooltip: l10n.cancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 1024
                ? 48.0
                : constraints.maxWidth >= 600
                ? 32.0
                : 20.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 14),
                      Text(
                        l10n.selectAccountToLogIn,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 15,
                          color: SchoolWayTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Expanded(
                        child: ListView.separated(
                          itemCount: accounts.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final account = accounts[index];
                            return _AccountCard(
                              account: account,
                              isBusy:
                                  state.isSwapping &&
                                  state.swappingAccountId == account.id,
                              onTap: state.isSwapping
                                  ? null
                                  : () => _selectAccount(account),
                              onRemove: state.isSwapping
                                  ? null
                                  : () => _removeAccount(account),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: state.isSwapping ? null : _openSignIn,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(l10n.logIntoAnotherAccount),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: SchoolWayTheme.subtleCyanSurface,
            borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
          ),
          child: const Icon(
            Icons.directions_bus_rounded,
            size: 38,
            color: SchoolWayTheme.primary,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          AppLocalizations.of(context).appName,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: SchoolWayTheme.navy,
          ),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.isBusy,
    required this.onTap,
    required this.onRemove,
  });

  final LinkedAccountProfile account;
  final bool isBusy;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final role = (account.metadata['role'] as String?)?.trim();
    return Semantics(
      button: true,
      label: '${account.displayName}, ${account.email}',
      child: Material(
        color: SchoolWayTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
          side: const BorderSide(color: SchoolWayTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                _AccountAvatar(account: account),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        account.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.muted,
                        ),
                      ),
                      if (role != null && role.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: SchoolWayTheme.subtleCyanSurface,
                            borderRadius: BorderRadius.circular(
                              SchoolWayTheme.radius,
                            ),
                          ),
                          child: Text(
                            role.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: SchoolWayTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isBusy)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PopupMenuButton<_AccountMenuAction>(
                    tooltip: AppLocalizations.of(context).removeAccount,
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (_) => onRemove?.call(),
                    itemBuilder: (context) => [
                      PopupMenuItem<_AccountMenuAction>(
                        value: _AccountMenuAction.remove,
                        enabled: onRemove != null,
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).removeAccount,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _AccountMenuAction { remove }

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.account});

  final LinkedAccountProfile account;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        account.initials,
        style: const TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w700,
          color: SchoolWayTheme.primary,
        ),
      ),
    );
    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: SchoolWayTheme.subtleCyanSurface,
      ),
      child: account.avatarUrl == null || account.avatarUrl!.trim().isEmpty
          ? fallback
          : Image.network(
              account.avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _AuthenticationMethodTile extends StatelessWidget {
  const _AuthenticationMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SchoolWayTheme.background,
      borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: SchoolWayTheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
