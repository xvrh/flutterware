import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// How a [Tappable] says it is under the pointer.
///
/// The wash itself comes from the palette's interaction tokens rather than from
/// a literal here, so a theme that is not the default gets a hover that belongs
/// to it.
enum TapFeedback {
  /// Paint nothing. For a target that already answers for itself — a
  /// [Tappable.builder] that swaps a colour, or a cell whose row tints behind
  /// it — where a second wash would read as two overlapping states.
  none,

  /// Neutral ink wash, for a control on a light surface. The default.
  overlay,

  /// White wash, for a control sitting on a dark or accent fill, where ink
  /// would disappear into what it is laid over.
  onFill,

  /// Accent-tinted wash — the *link* affordance, as opposed to the neutral
  /// [overlay] a control gets.
  link,
}

/// Ripple-free tap target — the house alternative to [InkWell]. Components paint
/// their own borders and fills for selected state, so Material's ink would only
/// muddy them.
///
/// It paints its own hover and press state. That is the difference between
/// this and a bare [GestureDetector], and it is the whole reason to reach for
/// it: every tap target in the app answers the pointer, without each caller
/// re-deriving the same wash from the same two tokens. [feedback] picks which
/// wash; [TapFeedback.none] opts out for the targets that answer another way.
/// [borderRadius] rounds it to match a child that is itself rounded.
///
/// The default differs by constructor, and the reason is what each one is for:
/// [Tappable.builder] exists *because* the caller draws its own hover, so
/// painting a second wash under it would read as two overlapping states —
/// it defaults to [TapFeedback.none]. The plain constructor has no way to say
/// anything at all, so it defaults to [TapFeedback.overlay]. A builder that
/// would rather hand the job over passes `feedback: TapFeedback.overlay` and
/// drops its own ternary, which also buys it the press state for free.
///
/// A label inside a [SelectionArea] is not selectable. Flutter's [Text]
/// wraps itself in a text-cursor [MouseRegion] whenever a selection registrar
/// is in scope, and that region sits *below* this one — so the click cursor
/// lost to the button's own label, and dragging across a row of buttons put
/// their words in the clipboard. The child is put in a
/// [SelectionContainer.disabled] when there is a registrar to hide, which
/// answers both. [selectableChild] is the way out for a target whose text is
/// the point.
///
/// Focus is keyboard-only. A tap deliberately does not take focus, so the
/// [FwPalette.focusRing] only ever appears for somebody travelling by keyboard,
/// and Enter or Space there does what a tap does. [focusable] takes a target
/// out of the traversal order — for the ones there are hundreds of, like a
/// margin affordance repeated down every line of a diff.
///
/// Use the default constructor for a static child. Use [Tappable.builder] when
/// the child itself depends on hover, so the `bool _hover` + `onEnter/onExit`
/// scaffold lives here once instead of in every caller. [onHover] also bubbles
/// the flag out for a sibling that reacts to it.
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

  /// Which wash the pointer gets. [TapFeedback.none] paints nothing.
  final TapFeedback feedback;

  /// Rounds the wash and the focus ring, for a child that is itself rounded.
  final BorderRadius? borderRadius;

  /// Leaves the child registered with an enclosing [SelectionArea] — for a tap
  /// target whose text somebody would want to copy.
  final bool selectableChild;

  /// Whether keyboard traversal stops here.
  final bool focusable;

  final FocusNode? focusNode;

  const Tappable({
    super.key,
    required this.onTap,
    required Widget this.child,
    this.onHover,
    this.cursor,
    this.disabledCursor = SystemMouseCursors.basic,
    this.behavior = HitTestBehavior.opaque,
    this.feedback = TapFeedback.overlay,
    this.borderRadius,
    this.selectableChild = false,
    this.focusable = true,
    this.focusNode,
  }) : builder = null;

  const Tappable.builder({
    super.key,
    required this.onTap,
    required Widget Function(BuildContext, bool) this.builder,
    this.onHover,
    this.cursor,
    this.disabledCursor = SystemMouseCursors.basic,
    this.behavior = HitTestBehavior.opaque,
    this.feedback = TapFeedback.none,
    this.borderRadius,
    this.selectableChild = false,
    this.focusable = true,
    this.focusNode,
  }) : child = null;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  // Only repaint when something consumes the flag. The flag itself is kept
  // current even while nothing does: a target disabled under the pointer — a
  // mode pill that was just picked — would otherwise stop hearing onExit, and
  // the stale `true` washes it the moment it re-enables, pointer long gone.
  bool get _paintsHover =>
      widget.builder != null ||
      widget.onHover != null ||
      (_enabled && widget.feedback != TapFeedback.none);

  void _setHover(bool value) {
    if (_hover == value) return;
    _hover = value;
    if (_paintsHover) setState(() {});
    widget.onHover?.call(value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_enabled) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    widget.onTap!();
    return KeyEventResult.handled;
  }

  /// The wash for the current state, or null when there is nothing to paint.
  Color? _wash(FwPalette colors) {
    if (!_enabled || widget.feedback == TapFeedback.none) return null;
    if (!_pressed && !_hover) return null;
    return switch ((widget.feedback, _pressed)) {
      (TapFeedback.none, _) => null,
      (TapFeedback.overlay, false) => colors.hoverOverlay,
      (TapFeedback.overlay, true) => colors.pressedOverlay,
      (TapFeedback.onFill, false) => colors.hoverOverlayOnFill,
      (TapFeedback.onFill, true) => colors.pressedOverlayOnFill,
      (TapFeedback.link, false) => colors.primaryHoverOverlay,
      (TapFeedback.link, true) => colors.primaryPressedOverlay,
    };
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var cursor = _enabled
        ? (widget.cursor ?? SystemMouseCursors.click)
        : widget.disabledCursor;

    var child = widget.builder != null
        ? widget.builder!(context, _hover)
        : widget.child!;

    // Only when there is a registrar to hide: outside a selection scope this
    // would be a widget per tap target that changes nothing.
    if (!widget.selectableChild &&
        SelectionContainer.maybeOf(context) != null) {
      child = SelectionContainer.disabled(child: child);
    }

    // A target that neither washes nor takes focus has nothing to paint over
    // itself, ever — and the ones there are hundreds of are exactly those.
    if (widget.feedback != TapFeedback.none || widget.focusable) {
      var ring = _focused && _enabled
          ? Border.all(color: colors.focusRing, width: 2)
          : null;
      // Always a Stack, hovered or not: growing the tree on hover would
      // reparent the child and take a stateful one back to initState under the
      // pointer.
      child = Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _wash(colors),
                  borderRadius: widget.borderRadius,
                  border: ring,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: _enabled && widget.focusable,
      skipTraversal: !widget.focusable,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: cursor,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: widget.onTap,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          onTapUp: _enabled ? (_) => _setPressed(false) : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          child: child,
        ),
      ),
    );
  }
}
