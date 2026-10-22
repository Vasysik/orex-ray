import 'package:flutter/material.dart';

/// Single app-wide policy for transient bottom notifications.
///
/// ScaffoldMessenger queues SnackBars by default. A rapid succession of
/// copy/import actions should instead show the latest result immediately.
class OrexNotice {
  const OrexNotice._();

  static void show(BuildContext context, SnackBar snackBar) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // Clear pending messages first, then remove the current one without its
    // usual exit animation. hideCurrentSnackBar() would still delay the next.
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }

  static void copied(BuildContext context, String message) {
    show(
      context,
      SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Text(message),
      ),
    );
  }
}
