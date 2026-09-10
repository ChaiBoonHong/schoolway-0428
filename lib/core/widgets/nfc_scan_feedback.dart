import 'package:flutter/material.dart';

abstract final class NfcScanFeedback {
  static const duration = Duration(seconds: 2);

  static void show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        content: Text(message, style: const TextStyle(fontFamily: 'Lexend')),
        backgroundColor: backgroundColor,
      ),
    );
  }
}
