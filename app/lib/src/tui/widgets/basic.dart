part of 'widgets.dart';

/// A leaf widget that renders [text] in the terminal using [RenderText].
///
/// All fields default to the same values as [RenderText]'s constructor so that
/// a plain `Text('hello')` just prints the string with inherited colours.
class Text extends LeafRenderObjectWidget {
  const Text(
    this.text, {
    super.key,
    this.fg = Color.defaultFg,
    this.bg = Color.defaultBg,
    this.style = 0,
    this.hAlign = HorizontalAlign.left,
    this.vAlign = VerticalAlign.top,
    this.wrap = true,
  });

  /// The string to display.
  final String text;

  /// Foreground (text) colour.
  final Color fg;

  /// Background colour.
  final Color bg;

  /// ANSI text-style bitmask (bold, underline, …).
  final int style;

  /// Horizontal alignment within the allocated cell area.
  final HorizontalAlign hAlign;

  /// Vertical alignment within the allocated cell area.
  final VerticalAlign vAlign;

  /// Whether to word-wrap when the text is wider than the available columns.
  final bool wrap;

  @override
  RenderText createRenderObject(BuildContext context) => RenderText(
        text,
        fg: fg,
        bg: bg,
        style: style,
        hAlign: hAlign,
        vAlign: vAlign,
        wrap: wrap,
      );

  @override
  void updateRenderObject(BuildContext context, RenderText renderObject) {
    renderObject
      ..text = text
      ..fg = fg
      ..bg = bg
      ..style = style
      ..hAlign = hAlign
      ..vAlign = vAlign
      ..wrap = wrap;
  }
}

/// A single-child widget that insets its child by [padding].
class Padding extends SingleChildRenderObjectWidget {
  const Padding({super.key, required this.padding, super.child});

  /// The insets to apply around [child].
  final EdgeInsets padding;

  @override
  RenderPadding createRenderObject(BuildContext context) =>
      RenderPadding(padding: padding);

  @override
  void updateRenderObject(BuildContext context, RenderPadding renderObject) {
    renderObject.padding = padding;
  }
}

/// A single-child widget that imposes [constraints] on its child.
///
/// Use [SizedBox] for the common case of fixing a width and/or height.
class ConstrainedBox extends SingleChildRenderObjectWidget {
  const ConstrainedBox({
    super.key,
    required this.constraints,
    super.child,
  });

  /// The additional constraints applied to the child.
  final BoxConstraints constraints;

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      RenderConstrainedBox(additionalConstraints: constraints);

  @override
  void updateRenderObject(
      BuildContext context, RenderConstrainedBox renderObject) {
    renderObject.additionalConstraints = constraints;
  }
}

/// A fixed-size box: a [ConstrainedBox] with [BoxConstraints.tightFor].
///
/// If [width] or [height] is null that axis is left unconstrained. Wraps the
/// optional [child] (or is empty when [child] is null).
class SizedBox extends StatelessWidget {
  const SizedBox({super.key, this.width, this.height, this.child});

  /// Fixed column count, or null to leave unconstrained.
  final int? width;

  /// Fixed row count, or null to leave unconstrained.
  final int? height;

  /// The widget to constrain.
  final Widget? child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: width, height: height),
        child: child,
      );
}

/// A single-child widget that paints a [BoxDecoration] (fill or border) behind
/// its child.
///
/// The decoration does not affect layout. To add padding inside a border, wrap
/// a [Padding] inside the [DecoratedBox].
class DecoratedBox extends SingleChildRenderObjectWidget {
  const DecoratedBox({
    super.key,
    required this.decoration,
    super.child,
  });

  /// The decoration painted behind [child].
  final BoxDecoration decoration;

  @override
  RenderDecoratedBox createRenderObject(BuildContext context) =>
      RenderDecoratedBox(decoration: decoration);

  @override
  void updateRenderObject(
      BuildContext context, RenderDecoratedBox renderObject) {
    renderObject.decoration = decoration;
  }
}

/// A multi-child widget that lays its [children] out along [direction].
///
/// `Row` and `Column` are thin wrappers that fix [direction] to horizontal or
/// vertical respectively.
class Flex extends MultiChildRenderObjectWidget {
  const Flex({
    super.key,
    required this.direction,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    super.children,
  });

  /// Whether to lay children horizontally or vertically.
  final Axis direction;

  /// How children are distributed along the main axis.
  final MainAxisAlignment mainAxisAlignment;

  /// How children are aligned along the cross axis.
  final CrossAxisAlignment crossAxisAlignment;

  /// Whether this flex occupies all available space or only as much as its
  /// children need along the main axis.
  final MainAxisSize mainAxisSize;

  @override
  RenderFlex createRenderObject(BuildContext context) => RenderFlex(
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: mainAxisSize,
      );

  @override
  void updateRenderObject(BuildContext context, RenderFlex renderObject) {
    renderObject
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..crossAxisAlignment = crossAxisAlignment
      ..mainAxisSize = mainAxisSize;
  }
}

/// A [Flex] that lays children out horizontally.
class Row extends Flex {
  const Row({
    super.key,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.mainAxisSize,
    super.children,
  }) : super(direction: Axis.horizontal);
}

/// A [Flex] that lays children out vertically.
class Column extends Flex {
  const Column({
    super.key,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.mainAxisSize,
    super.children,
  }) : super(direction: Axis.vertical);
}

/// A widget that controls how a child of a [Flex] flexes.
///
/// Wraps [child] and writes a [flex] factor and [fit] into the child render
/// object's [FlexParentData] whenever the tree is updated.
class Flexible extends ParentDataWidget<FlexParentData> {
  const Flexible({
    super.key,
    this.flex = 1,
    this.fit = FlexFit.loose,
    required super.child,
  });

  /// The flex factor. A zero value means the child is inflexible.
  final int flex;

  /// Whether the child must fill its allotted space ([FlexFit.tight]) or may
  /// be smaller ([FlexFit.loose]).
  final FlexFit fit;

  @override
  void applyParentData(RenderObject renderObject) {
    var pd = renderObject.parentData! as FlexParentData;
    if (pd.flex != flex || pd.fit != fit) {
      pd.flex = flex;
      pd.fit = fit;
      if (renderObject.parent is RenderFlex) {
        (renderObject.parent! as RenderFlex).markNeedsLayout();
      }
    }
  }
}

/// A [Flexible] whose child is forced to fill the space it is given.
///
/// Equivalent to `Flexible(fit: FlexFit.tight, ...)`.
class Expanded extends Flexible {
  const Expanded({
    super.key,
    super.flex,
    required super.child,
  }) : super(fit: FlexFit.tight);
}
