import 'package:flutter/material.dart';

import '../theme/orex_theme.dart';
import 'responsive_motion.dart';

/// An action which stays in the header even when its caption is collapsed.
class OrexHeaderAction {
  const OrexHeaderAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.trailingIcon,
    this.busy = false,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? trailingIcon;
  final bool busy;
}

/// A single responsive policy shared by Profiles and Diagnostics.
///
/// All captions appear whenever there is room. When space is reduced,
/// captions collapse from LEFT to RIGHT (the opposite of the previous
/// Profiles behaviour). The buttons themselves always remain on one line.
/// When the minimum width cannot fit alongside the title, the whole action
/// bar moves below the title and scrolls horizontally only as a last resort.
class OrexAdaptiveHeader extends StatelessWidget {
  const OrexAdaptiveHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    this.accentColor = OrexColors.copper,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<OrexHeaderAction> actions;
  final Color accentColor;

  static const double _buttonWidth = 52;
  static const double _buttonGap = 10;
  static const double _headerGap = 20;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).textTheme;
    final titleWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: accentColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: typography.headlineSmall,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(subtitle, style: typography.bodySmall,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final titleWidth = 62 + _textWidth(context, title, typography.headlineSmall);
        // Do not reserve the subtitle's entire width and force an early wrap:
        // it is allowed to ellipsize when the viewport is narrow.
        final minimumTitleWidth = titleWidth > 178 ? titleWidth : 178.0;
        final compactWidth = actions.isEmpty ? 0.0 :
            actions.length * _buttonWidth + (actions.length - 1) * _buttonGap;
        final sameRow = width >= minimumTitleWidth + _headerGap + compactWidth;
        final availableWidth = sameRow
            ? width - minimumTitleWidth - _headerGap
            : width;
        final expandedWidths = [
          for (final action in actions)
            8 + _textWidth(context, action.label, typography.labelLarge) +
                (action.trailingIcon == null ? 0 : 22),
        ];
        final expanded = List<bool>.filled(actions.length, true);
        var totalWidth = compactWidth;
        for (final extra in expandedWidths) {
          totalWidth += extra;
        }
        // Prioritise rightmost captions; compact the leftmost first.
        for (var index = 0;
            index < actions.length && totalWidth > availableWidth - 2;
            index++) {
          expanded[index] = false;
          totalWidth -= expandedWidths[index];
        }

        final actionBar = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const SizedBox(width: _buttonGap),
              _HeaderButton(action: actions[index], expanded: expanded[index]),
            ],
          ],
        );

        final content = sameRow
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: titleWidget),
                  const SizedBox(width: _headerGap),
                  actionBar,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleWidget,
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // Keep the final (usually confirmation) action visible.
                    reverse: true,
                    child: actionBar,
                  ),
                ],
              );
        return AnimatedSize(
          duration: OrexMotion.duration(context, OrexMotion.compact),
          curve: OrexMotion.curve,
          alignment: Alignment.topLeft,
          child: OrexResponsiveReveal(
            layoutKey: sameRow ? 'header-$title-row' : 'header-$title-stack',
            child: content,
          ),
        );
      },
    );
  }
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.action, required this.expanded});

  final OrexHeaderAction action;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.tooltip,
      child: SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: action.onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: action.color,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action.busy)
                const SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                Icon(action.icon),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(action.label),
                      if (action.trailingIcon != null) ...[
                        const SizedBox(width: 4),
                        Icon(action.trailingIcon, size: 18),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
