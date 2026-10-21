import 'package:flutter/material.dart';

import '../theme/orex_theme.dart';

/// Compact confirmation dialog styled by the same DialogTheme as editors.
/// Glass effects are reserved for panels and selection sheets.
class OrexConfirmDialog extends StatelessWidget {
  const OrexConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmLabel,
    this.cancelLabel = 'Отмена',
    this.icon,
  });

  final String title;
  final Widget content;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      // Use OrexTheme.dialogTheme for the same opaque material surface,
      // corners and colors as manual profile/configuration editors.
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        key: const ValueKey('orex-confirm-content'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 24, color: OrexColors.copper),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(child: content),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
