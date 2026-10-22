/// Responsive thresholds in logical pixels.
///
/// Home uses the width *inside* the content pane; the shell threshold uses
/// the full window width (including the 132 px sidebar and outer spacing).
abstract final class OrexBreakpoints {
  /// Both the connection card and quick-info card fit comfortably side by side.
  static const double homeSplitCards = 700;

  /// Switch to bottom navigation below 660 logical pixels of window width.
  /// The home screen already stacks its cards before this threshold.
  static const double shellSideNavigation = 660;
}
