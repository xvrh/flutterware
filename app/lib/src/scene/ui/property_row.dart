// One property, one anatomy.
//
// The inspector's rows used to be hand-assembled: a caption, then whatever
// control the property needed, with the bound ones announced in a separate
// block at the top of the panel and nothing on the field itself. A reader
// could see that `fill` was bound and could see a colour picker, and had no
// way to know they were the same property — or that the picker they were
// about to drag would move a parameter every sibling reads.
//
// So a property row states its own origin, and the control it shows follows
// from it. A property is BOUND or it is FREE: bound, the control gives way to
// the source, because there is no local value to edit and a live control
// saying otherwise is the lie. A style is the one soft case — it sets a value
// the node may type over — and it stays live, marked.
//
// The plug is the affordance the panel had none of. It appears on hover on
// every bindable row, in the label's own line, and it is the same gesture on
// a number, a colour and a text.
import 'package:flutter/material.dart';

import '../../ui/design/design.dart';
import '../../ui/tappable.dart';

/// Where a property's value comes from — what the row shows, and whether the
/// control under it is live.
enum PropertyOrigin {
  /// The node's own value. The control edits it.
  own,

  /// A parameter of this scene. Bound.
  parameter,

  /// A token the package declares. Bound.
  token,

  /// A value the app exports, which the editor never sees — the canvas draws
  /// it and the panel can only name it. Bound.
  appValue,

  /// A shared text style sets it. Live: typing overrides, and equal means
  /// inherited, so there is no flag beyond the marker on this row.
  style;

  /// Bound properties have no local value. The style is not one of them.
  bool get isBound => this != own && this != style;
}

/// A property the node has typed over its style: the broken link, and the
/// way back.
///
/// One icon carries every state of "something else drives this" — faint for
/// a property nothing drives yet, solid on a binding's chip, broken here —
/// so the panel has one vocabulary rather than a link idiom for bindings and
/// an arrow idiom for styles.
///
/// An INHERITED property shows nothing. Under a style, inheriting is the
/// normal state; marking a dozen rows with the same name is noise, and the
/// file says the same thing — `tokens.display.copyWith(weight: …)` names the
/// override and nothing else. What is worth a mark is the divergence.
///
/// Its own widget because the paint stack is a style property like any other
/// and does not fit in a [PropertyRow] — it draws a list with a header of
/// its own — and the mark has to read identically in both places.
class PropertyOriginMark extends StatelessWidget {
  const PropertyOriginMark({
    super.key,
    required this.origin,
    this.sourceName,
    this.overridden = false,
    this.onReset,
  });

  final PropertyOrigin origin;
  final String? sourceName;
  final bool overridden;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    if (origin != PropertyOrigin.style || !overridden) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message:
          'Typed over ${sourceName ?? 'the style'} — click to take its '
          'value back',
      child: Tappable(
        onTap: onReset,
        child: Icon(
          Icons.link_off,
          size: FwIconSize.sm,
          color: context.colors.accent,
        ),
      ),
    );
  }
}

/// A label, a control, and where the value comes from.
class PropertyRow extends StatefulWidget {
  const PropertyRow({
    super.key,
    required this.label,
    required this.child,
    this.origin = PropertyOrigin.own,
    this.sourceName,
    this.valueLabel,
    this.swatch,
    this.overridden = false,
    this.trailing,
    this.inline = false,
    this.onBind,
    this.onUnbind,
    this.onOpenSource,
    this.onReset,
  });

  final String label;

  /// The control. Shown whenever the property is not bound — including under
  /// a style, whose values are the node's to type over.
  final Widget child;

  final PropertyOrigin origin;

  /// What it reads: `headline`, `tokens.brand`.
  final String? sourceName;

  /// What that currently resolves to, for a bound row — the panel still says
  /// what the number is, it just does not pretend you can drag it here.
  final String? valueLabel;

  /// A colour chip for the value, where the value is a colour.
  final Color? swatch;

  /// Under a style, and typed over. Offers the way back.
  final bool overridden;

  /// A control that belongs on the label's line rather than under it — a
  /// size's *hug* / *fill* word, which is a mode and not a value. It sits
  /// before the origin marker.
  final Widget? trailing;

  /// The control sits on the label's line rather than under it. For a
  /// self-contained control that is already the width of its meaning — a
  /// checkbox — where a row of its own would be three times its height.
  final bool inline;

  /// Opens the bind menu at a global point. Null on a property nothing can
  /// fill, and then the plug is not there — an affordance that refuses is
  /// worse than none. Reached from the plug and from a right-click anywhere
  /// on the row, which is the gesture that worked before this one existed.
  final ValueChanged<Offset>? onBind;
  final VoidCallback? onUnbind;

  /// Steps to the parameter or token this reads.
  final VoidCallback? onOpenSource;

  /// Back to what the style says.
  final VoidCallback? onReset;

  @override
  State<PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends State<PropertyRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (d) => widget.onBind?.call(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  bottom: widget.inline ? 0 : FwSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: widget.inline ? context.type.body : caption,
                      ),
                    ),
                    if (widget.inline && !widget.origin.isBound) ...[
                      widget.child,
                      const Gap(FwSpacing.sm),
                    ],
                    if (widget.trailing != null) ...[
                      widget.trailing!,
                      const Gap(FwSpacing.sm),
                    ],
                    ..._marker(context, caption),
                  ],
                ),
              ),
              if (widget.origin.isBound)
                _source(context)
              else if (!widget.inline)
                widget.child,
            ],
          ),
        ),
      ),
    );
  }

  /// The label line's right edge: the way back from a style, or the plug.
  ///
  /// The plug is faint until the row is hovered, and never absent. Hover
  /// alone would leave the panel exactly as undiscoverable as it is now — a
  /// gesture nobody performs on a field that looks inert. Faint and always
  /// there, a column of them teaches the whole grammar at a glance: these
  /// are the properties something else can drive.
  List<Widget> _marker(BuildContext context, TextStyle caption) {
    var colors = context.colors;
    // Typed over a style: the broken link takes the slot. The plug is still
    // there on a right-click — a property under a style can still be bound to
    // a parameter — but two icons in a 129px label line is a crowd, and this
    // is the one that has something to say.
    if (widget.origin == PropertyOrigin.style && widget.overridden) {
      return [
        PropertyOriginMark(
          origin: widget.origin,
          sourceName: widget.sourceName,
          overridden: widget.overridden,
          onReset: widget.onReset,
        ),
      ];
    }
    if (widget.origin.isBound || widget.onBind == null) return const [];
    return [
      Opacity(
        opacity: _hovered ? 1 : 0.35,
        child: GestureDetector(
          onTapDown: (d) => widget.onBind!(d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(FwSpacing.xxs),
            child: Icon(Icons.link, size: FwIconSize.sm, color: colors.mut2),
          ),
        ),
      ),
    ];
  }

  /// What a bound property shows instead of a control: the source, the value
  /// it resolves to, and the way out.
  Widget _source(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    return Tappable(
      onTap: widget.onOpenSource,
      borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.sm,
          vertical: FwSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.accentSoft,
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
          border: Border.all(color: colors.accentSoft2),
        ),
        child: Row(
          children: [
            Icon(Icons.link, size: FwIconSize.xs, color: colors.accent),
            const Gap(FwSpacing.xs),
            Flexible(
              child: Text(
                widget.sourceName ?? '',
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.accent),
              ),
            ),
            const Gap(FwSpacing.xs),
            if (widget.swatch != null) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: widget.swatch,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: colors.line),
                ),
              ),
              const Gap(FwSpacing.xs),
            ],
            Text(
              widget.origin == PropertyOrigin.appValue
                  ? "the app's"
                  : widget.valueLabel ?? '',
              style: type.caption.copyWith(color: colors.mut3),
            ),
            if (_hovered && widget.onUnbind != null) ...[
              const Gap(FwSpacing.xs),
              Tappable(
                onTap: widget.onUnbind,
                child: Icon(
                  Icons.close,
                  size: FwIconSize.xs,
                  color: colors.mut2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
