import 'package:flutter/material.dart';

import '../theme/glass.dart';

/// Shared surface for selection / profile management bottom sheets.
/// Keep margins, radius, inner padding and opacity identical everywhere.
class OrexModalSheetSurface extends StatelessWidget {
  const OrexModalSheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassPanel(
          borderRadius: 24,
          opacity: OrexGlassOpacity.modal,
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }
}
