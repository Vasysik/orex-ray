import 'package:flutter/material.dart';

/// Shared motion timings for layout changes caused by responsive breakpoints.
///
/// These animations are intentionally short: they soften a layout jump without
/// making window resizing feel elastic. Continuous data updates (traffic, ping,
/// timers) should not use these transitions.
abstract final class OrexMotion {
  static const responsive = Duration(milliseconds: 180);
  static const navigation = Duration(milliseconds: 220);
  static const compact = Duration(milliseconds: 160);
  static const curve = Curves.easeOutCubic;

  static Duration duration(
    BuildContext context, [
    Duration normal = responsive,
  ]) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ? Duration.zero : normal;
  }
}

/// Softens an abrupt responsive branch replacement without keeping both
/// branches mounted at the same time.
///
/// The initial layout is shown immediately. Motion starts only when
/// [layoutKey] changes, so opening a screen does not add an unnecessary fade.
/// Keeping only the current child is important for OrexRay screens because a
/// desktop/mobile switch can contain the same controllers, lists and keys. A
/// traditional [AnimatedSwitcher] would briefly mount both layouts at once.
class OrexResponsiveReveal extends StatefulWidget {
  const OrexResponsiveReveal({
    super.key,
    required this.layoutKey,
    required this.child,
    this.alignment = Alignment.topLeft,
  });

  final Object layoutKey;
  final Widget child;
  final Alignment alignment;

  @override
  State<OrexResponsiveReveal> createState() => _OrexResponsiveRevealState();
}

class _OrexResponsiveRevealState extends State<OrexResponsiveReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OrexMotion.responsive,
    value: 1,
  );

  void _syncMotionPreference() {
    final duration = OrexMotion.duration(context);
    _controller.duration = duration;
    if (duration == Duration.zero) _controller.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant OrexResponsiveReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutKey == widget.layoutKey) return;
    if (_controller.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.duration == Duration.zero) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = OrexMotion.curve.transform(_controller.value);
        return Opacity(
          opacity: 0.90 + (0.10 * value),
          child: Transform.scale(
            alignment: widget.alignment,
            scale: 0.994 + (0.006 * value),
            child: child,
          ),
        );
      },
    );
  }
}
