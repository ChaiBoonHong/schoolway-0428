import 'package:flutter/material.dart';
import 'package:schoolway/features/auth/account_selection_screen.dart';

/// Screen allowing the user to select, add, or manage linked/saved accounts on this device.
/// Delegated to [AccountSelectionScreen].
class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  static const routeName = '/manage-accounts';

  @override
  Widget build(BuildContext context) {
    return const AccountSelectionScreen();
  }
}
