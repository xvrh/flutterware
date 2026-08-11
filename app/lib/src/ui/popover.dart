import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which side of the anchor the popover opens on.
enum PopoverSide { bottom, top }

/// Horizontal edge of the popover aligned to the anchor.
enum PopoverAlign { start, end }

/// Controls a single [Popover]; handed to the anchor builder so a trigger can
/// open/close it and reflect its open state.
abstract class PopoverController {
  void open();
  void close();
  void toggle();
  bool get isOpen;

  /// Width of the anchor, available once the popover is laid out — lets content
  /// size to its trigger without a [LayoutBuilder]. Null before first layout.
  double? get anchorWidth;
}

/// An anchored, dismissible popover.
///
/// A thin wrapper over [RawMenuAnchor]: the framework handles the overlay,
/// outside-tap and Escape dismissal, and focus; we own positioning ([side]/
/// [align], clamped on-screen) and the content. Content is rendered as-is —
/// the primitive supplies no surface of its own.
///
/// Ported from `cms/packages/admin_ui/lib/src/common/ui/popover.dart`.
class Popover extends StatefulWidget {
  final Widget Function(BuildContext context, PopoverController controller)
  anchor;
  final Widget Function(BuildContext context, PopoverController controller)
  content;
  final PopoverSide side;
  final PopoverAlign align;

  /// Gap between the anchor and the popover.
  final double gap;

  /// Whether opening moves focus into the popover. Interactive content wants
  /// this; a read-only tip should pass false to keep the caller's focus.
  final bool autofocus;

  /// Fires however the popover closes — selection, outside tap or Escape.
  /// For state the content leaves behind that an unmount will not undo: a
  /// hovered row's `onExit` never fires when dismissal removes the overlay
  /// from under the pointer.
  final VoidCallback? onClose;

  const Popover({
    super.key,
    required this.anchor,
    required this.content,
    this.side = PopoverSide.bottom,
    this.align = PopoverAlign.start,
    this.gap = 6,
    this.autofocus = true,
    this.onClose,
  });

  @override
  State<Popover> createState() => _PopoverState();
}

class _PopoverState extends State<Popover> implements PopoverController {
  final _menu = MenuController();
  bool _isOpen = false;
  double? _anchorWidth;

  @override
  bool get isOpen => _isOpen;

  @override
  double? get anchorWidth => _anchorWidth;

  @override
  void open() => _menu.open();

  @override
  void close() => _menu.close();

  @override
  void toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    return RawMenuAnchor(
      controller: _menu,
      onOpen: () => setState(() => _isOpen = true),
      onClose: () {
        setState(() => _isOpen = false);
        widget.onClose?.call();
      },
      builder: (context, controller, child) => widget.anchor(context, this),
      overlayBuilder: (context, info) {
        _anchorWidth = info.anchorRect.width;
        return CustomSingleChildLayout(
          delegate: _PopoverLayout(
            anchor: info.anchorRect,
            side: widget.side,
            align: widget.align,
            gap: widget.gap,
          ),
          // RawMenuAnchor's Escape shortcut wraps the anchor, not the overlay,
          // so we handle it on the content to dismiss regardless of focus.
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
            child: Focus(
              autofocus: widget.autofocus,
              // A bare RawMenuAnchor's own handler only closes child submenus,
              // so we close on taps outside the group ourselves.
              child: TapRegion(
                groupId: info.tapRegionGroupId,
                onTapOutside: (_) => close(),
                child: widget.content(context, this),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final PopoverSide side;
  final PopoverAlign align;
  final double gap;

  static const _margin = 8.0;

  _PopoverLayout({
    required this.anchor,
    required this.side,
    required this.align,
    required this.gap,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var dx = align == PopoverAlign.start
        ? anchor.left
        : anchor.right - childSize.width;
    var dy = side == PopoverSide.bottom
        ? anchor.bottom + gap
        : anchor.top - gap - childSize.height;

    dx = _clamp(dx, size.width, childSize.width);
    dy = _clamp(dy, size.height, childSize.height);
    return Offset(dx, dy);
  }

  double _clamp(double value, double extent, double childExtent) {
    var max = extent - childExtent - _margin;
    if (max < _margin) return _margin;
    return value.clamp(_margin, max);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor ||
      old.side != side ||
      old.align != align ||
      old.gap != gap;
}
