import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/bouncing_button.dart';
import 'package:schoolway/features/auth/firebase_error_handler.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/linked_account_profile.dart';

/// Modal dialog prompting the user for credentials to switch to an email account.
class AccountSwitchPasswordDialog extends StatefulWidget {
  const AccountSwitchPasswordDialog({
    super.key,
    required this.account,
    required this.onAuthenticate,
  });

  final LinkedAccountProfile account;
  final Future<bool> Function(String password) onAuthenticate;

  static Future<bool?> show(
    BuildContext context, {
    required LinkedAccountProfile account,
    required Future<bool> Function(String password) onAuthenticate,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AccountSwitchPasswordDialog(
        account: account,
        onAuthenticate: onAuthenticate,
      ),
    );
  }

  @override
  State<AccountSwitchPasswordDialog> createState() =>
      _AccountSwitchPasswordDialogState();
}

class _AccountSwitchPasswordDialogState
    extends State<AccountSwitchPasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text.trim();
    final l10n = AppLocalizations.of(context);
    if (password.isEmpty) {
      setState(() => _errorMessage = l10n.passwordRequired);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onAuthenticate(password);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = _errorMessage ?? l10n.sessionSwapFailed;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = FirebaseErrorHandler.getFirebaseAuthErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Authentication failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
      ),
      backgroundColor: SchoolWayTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with avatar
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: SchoolWayTheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  child: Text(
                    widget.account.initials,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.switchAccount,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.account.email,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.blueGrey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: SchoolWayTheme.muted,
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  tooltip: l10n.cancel,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: SchoolWayTheme.border, height: 1),
            const SizedBox(height: 16),

            // Error banner
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                margin: const EdgeInsets.only(bottom: 12),
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
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            Text(
              l10n.enterPasswordToSwitch,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                color: SchoolWayTheme.navy,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            // Password Field
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontFamily: 'Lexend'),
              decoration: InputDecoration(
                hintText: l10n.password,
                hintStyle: const TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.muted,
                ),
                filled: true,
                fillColor: SchoolWayTheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
                  borderSide: const BorderSide(color: SchoolWayTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
                  borderSide: const BorderSide(color: SchoolWayTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
                  borderSide: const BorderSide(
                    color: SchoolWayTheme.primary,
                    width: 1.5,
                  ),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: SchoolWayTheme.muted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SchoolWayTheme.navy,
                      side: const BorderSide(color: SchoolWayTheme.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          SchoolWayTheme.radius,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BouncingButton(
                    onPressed: _isLoading ? null : _submit,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isLoading
                            ? SchoolWayTheme.primary.withValues(alpha: 0.5)
                            : SchoolWayTheme.primary,
                        borderRadius: BorderRadius.circular(
                          SchoolWayTheme.radius,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SchoolWayTheme.surface,
                              ),
                            )
                          : Text(
                              l10n.switchAccount,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: SchoolWayTheme.surface,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
