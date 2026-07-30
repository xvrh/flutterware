import 'package:flutter/widgets.dart';

/// Ripple-free tap target — the house alternative to [InkWell]. Components paint
/// their own borders and fills for hover/selected state, so Material's ink would
/// only muddy them. A [GestureDetector] (opaque hit test) wrapped in a
/// [MouseRegion] that shows the click cursor when [onTap] is set and
/// [disabledCursor] (default basic) otherwise.
///
/// Use the default constructor for a static child. Use [Tappable.builder] when
/// the child depends on hover — the ubiquitous "tint a Container on hover" row —
/// so the `bool _hover` + `onEnter/onExit` scaffold lives here once instead of
/// in every caller. [onHover] also bubbles the flag out for a sibling that
/// reacts to it.
///
/// Ported from `cms/packages/admin_ui/lib/src/common/ui/tappable.dart`.
class Tappable extends StatefulWidget {
  final VoidCallback? onTap;

  /// Static content, for the default constructor.
  final Widget? child;

  /// Hover-aware content, for [Tappable.builder].
  final Widget Function(BuildContext context, bool hovered)? builder;

  /// Notified as the pointer enters/leaves — for hover that drives a sibling.
  final ValueChanged<bool>? onHover;

  /// Overrides the enabled cursor (default [SystemMouseCursors.click]).
  final MouseCursor? cursor;

  /// Cursor while [onTap] is null.
  final MouseCursor disabledCursor;

  final HitTestBehavior behavior;

  const Tappable({
    super.key,
    required this.onTap,
    required Widget this.child,
    this.onHover,
    this.cursor,
    this.disabledCursor = SystemMouseCursors.basic,
    this.behavior = HitTestBehavior.opaque,
  }) : builder = null;

  const Tappable.builder({
    super.key,
    required this.onTap,
    required Widget Function(BuildContext, bool) this.builder,
    this.onHover,
    this.cursor,
    this.disabledCursor = SystemMouseCursors.basic,
    this.behavior = HitTestBehavior.opaque,
  }) : child = null;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _hover = false;

  // Only watch the pointer when something consumes the flag.
  bool get _tracksHover => widget.builder != null || widget.onHover != null;

  void _setHover(bool value) {
    if (_hover == value) return;
    _hover = value;
    if (widget.builder != null) {
      setState(() {});
    }
    widget.onHover?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    var cursor = widget.onTap == null
        ? widget.disabledCursor
        : (widget.cursor ?? SystemMouseCursors.click);
    var child = widget.builder != null
        ? widget.builder!(context, _hover)
        : widget.child!;
    return MouseRegion(
      cursor: cursor,
      onEnter: _tracksHover ? (_) => _setHover(true) : null,
      onExit: _tracksHover ? (_) => _setHover(false) : null,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        child: child,
      ),
    );
  }
}
