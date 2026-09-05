// The property table: every authorable property of every node kind, as
// data — its name, its kind, its default, and how to read and write it on
// a node.
//
// One organ, several hosts. The wire and the authored JSON encode and
// decode by walking it; the file emitter and parser spell and read by it;
// the read plane gets, sets and types a property by it; a copy and an undo
// restore move values by it. What it cannot derive is the constructor — a
// scene file IS a call to it, so the named parameters stay hand-written
// Dart — and the renderer, which is what a property MEANS. A test pins the
// table to the constructors; adding a property is a row here, a parameter
// with its field, a renderer case, and a named parameter on `animate()` if
// it animates. Four places pinned to each other, instead of twenty-five
// pinned by nothing.
import 'model.dart';
import 'values.dart';

/// The kinds a property's value can take. Each has one wire spelling here
/// and one file spelling in the tool; a property's kind is what a parameter
/// binding is checked against.
enum ScenePropKind {
  /// A double.
  number,

  /// A whole number, or null for "no limit".
  integer,

  /// A string.
  string,

  /// True or false.
  boolean,

  /// A [SceneColor], nullable where the property can be absent.
  color,

  /// A size: null for hug, infinity for fill, or a number.
  size,

  /// A list of sizes — a table's column tracks.
  sizes,

  /// [SceneEdges]: one number when uniform, four named sides when not.
  edges,

  /// One of a fixed set — an enum, spelled `Type.member`.
  choice,
}

/// The members a [ScenePropKind.choice] property can take and how the file
/// spells them: `NodeLayout.row`, `SceneFontWeight.w700`.
class SceneChoices {
  const SceneChoices(this.typeName, this.values, {required this.nameOf});

  final String typeName;
  final List<Object> values;
  final String Function(Object value) nameOf;

  List<String> get names => [for (var v in values) nameOf(v)];

  Object? valueOf(String name) {
    for (var v in values) {
      if (nameOf(v) == name) return v;
    }
    return null;
  }

  /// Wire and authored JSON carry the member's name — one spelling, the
  /// file's own, rather than an index that means nothing off the wire.
  String toWire(Object value) => nameOf(value);
}

/// Which node kinds carry a property.
enum ScenePropOwner {
  any,
  frame,
  text,
  shape;

  bool has(SceneNode node) => switch (this) {
    any => true,
    frame => node is FrameNode,
    text => node is TextNode,
    shape => node is ShapeNode,
  };
}

/// One authorable property.
class SceneProp {
  const SceneProp(
    this.name,
    this.kind, {
    required this.read,
    required this.write,
    this.defaultValue,
    this.wireKey,
    this.owner = ScenePropOwner.any,
    this.animatable = false,
    this.choices,
    this.sides,
  });

  /// The file's named argument, the read plane's key, the motion's track
  /// name when it animates.
  final String name;
  final ScenePropKind kind;

  /// What a node holds when the file says nothing. A property at its
  /// default is not written — to the file, to the JSON, to the wire.
  final Object? defaultValue;

  /// The key on the wire when it is not [name] — `w` for width.
  final String? wireKey;
  final ScenePropOwner owner;

  /// Whether a motion track can write it — which also decides whether the
  /// wire carries the composed value rather than the authored one.
  final bool animatable;

  /// For a [ScenePropKind.choice].
  final SceneChoices? choices;

  /// For a [ScenePropKind.edges]: the four file names of the sides, in
  /// left-top-right-bottom order — `paddingLeft`, `paddingTop`…
  final List<String>? sides;

  final Object? Function(SceneNode node) read;
  final void Function(SceneNode node, Object? value) write;

  String get key => wireKey ?? name;

  bool appliesTo(SceneNode node) => owner.has(node);

  /// The parameter kind a binding to this property must have, or null when
  /// no parameter can fill it — a choice, a list of sizes.
  SceneParamKind? get paramKind => switch (kind) {
    ScenePropKind.number ||
    ScenePropKind.size ||
    ScenePropKind.edges => SceneParamKind.number,
    ScenePropKind.string => SceneParamKind.string,
    ScenePropKind.boolean => SceneParamKind.bool,
    ScenePropKind.color => SceneParamKind.color,
    ScenePropKind.integer ||
    ScenePropKind.sizes ||
    ScenePropKind.choice => null,
  };

  /// The value as the wire and the authored JSON carry it.
  Object? toWire(Object? value) => switch (kind) {
    ScenePropKind.color => (value as SceneColor?)?.argb,
    ScenePropKind.size => sizeToWire(value as double?),
    ScenePropKind.sizes => [
      for (var c in value! as List<double?>) sizeToWire(c),
    ],
    ScenePropKind.edges => (value! as SceneEdges).toWire(),
    ScenePropKind.choice => value == null ? null : choices!.toWire(value),
    _ => value,
  };

  /// The inverse of [toWire]; a missing or unreadable value is the default.
  Object? fromWire(Object? raw) => switch (kind) {
    ScenePropKind.number => (raw as num?)?.toDouble() ?? defaultValue,
    ScenePropKind.integer => (raw as num?)?.toInt(),
    ScenePropKind.string => raw is String ? raw : defaultValue,
    ScenePropKind.boolean => raw is bool ? raw : defaultValue,
    ScenePropKind.color => raw is num ? SceneColor(raw.toInt()) : defaultValue,
    ScenePropKind.size => sizeFromWire(raw),
    ScenePropKind.sizes => switch (raw) {
      List l => [for (var c in l) sizeFromWire(c)],
      _ => <double?>[],
    },
    ScenePropKind.edges => SceneEdges.fromWire(raw),
    ScenePropKind.choice => switch (raw) {
      String name => choices!.valueOf(name) ?? defaultValue,
      // Older payloads carried the index.
      num i when i >= 0 && i < choices!.values.length =>
        choices!.values[i.toInt()],
      _ => defaultValue,
    },
  };
}

// ── the table ──────────────────────────────────────────────────────────────

const _weights = SceneChoices(
  'SceneFontWeight',
  SceneFontWeight.values,
  nameOf: _weightName,
);
String _weightName(Object v) => 'w${(v as SceneFontWeight).value}';

const _layouts = SceneChoices(
  'NodeLayout',
  NodeLayout.values,
  nameOf: _enumName,
);
const _mainAligns = SceneChoices(
  'SceneMainAxisAlignment',
  SceneMainAxisAlignment.values,
  nameOf: _enumName,
);
const _crossAligns = SceneChoices(
  'SceneCrossAxisAlignment',
  SceneCrossAxisAlignment.values,
  nameOf: _enumName,
);
const _aligns = SceneChoices(
  'SceneTextAlign',
  SceneTextAlign.values,
  nameOf: _enumName,
);
String _enumName(Object v) => (v as Enum).name;

/// Every node's properties, in the order the file writes them.
const sceneCommonProps = <SceneProp>[
  SceneProp(
    'x',
    ScenePropKind.number,
    defaultValue: 0.0,
    read: _x,
    write: _setX,
  ),
  SceneProp(
    'y',
    ScenePropKind.number,
    defaultValue: 0.0,
    read: _y,
    write: _setY,
  ),
  SceneProp(
    'width',
    ScenePropKind.size,
    wireKey: 'w',
    read: _width,
    write: _setWidth,
  ),
  SceneProp(
    'height',
    ScenePropKind.size,
    wireKey: 'h',
    read: _height,
    write: _setHeight,
  ),
  SceneProp(
    'fill',
    ScenePropKind.color,
    animatable: true,
    read: _fill,
    write: _setFill,
  ),
  SceneProp(
    'borderColor',
    ScenePropKind.color,
    read: _borderColor,
    write: _setBorderColor,
  ),
  SceneProp(
    'borderWidth',
    ScenePropKind.number,
    defaultValue: 1.0,
    read: _borderWidth,
    write: _setBorderWidth,
  ),
  SceneProp(
    'corner',
    ScenePropKind.number,
    defaultValue: 0.0,
    read: _corner,
    write: _setCorner,
  ),
  SceneProp(
    'opacity',
    ScenePropKind.number,
    defaultValue: 1.0,
    animatable: true,
    read: _opacity,
    write: _setOpacity,
  ),
  SceneProp(
    'visible',
    ScenePropKind.boolean,
    defaultValue: true,
    read: _visible,
    write: _setVisible,
  ),
];

/// A frame's own properties, after the common ones. `children` and the
/// repeat are not here: they are structure, not values.
const sceneFrameProps = <SceneProp>[
  SceneProp(
    'layout',
    ScenePropKind.choice,
    owner: ScenePropOwner.frame,
    defaultValue: NodeLayout.absolute,
    choices: _layouts,
    read: _layout,
    write: _setLayout,
  ),
  SceneProp(
    'gap',
    ScenePropKind.number,
    owner: ScenePropOwner.frame,
    defaultValue: 8.0,
    animatable: true,
    read: _gap,
    write: _setGap,
  ),
  SceneProp(
    'padding',
    ScenePropKind.edges,
    owner: ScenePropOwner.frame,
    defaultValue: SceneEdges.zero,
    sides: ['paddingLeft', 'paddingTop', 'paddingRight', 'paddingBottom'],
    read: _padding,
    write: _setPadding,
  ),
  SceneProp(
    'columns',
    ScenePropKind.sizes,
    owner: ScenePropOwner.frame,
    defaultValue: <double?>[],
    read: _columns,
    write: _setColumns,
  ),
  SceneProp(
    'cellPadding',
    ScenePropKind.edges,
    owner: ScenePropOwner.frame,
    defaultValue: SceneEdges.zero,
    sides: [
      'cellPaddingLeft',
      'cellPaddingTop',
      'cellPaddingRight',
      'cellPaddingBottom',
    ],
    read: _cellPadding,
    write: _setCellPadding,
  ),
  SceneProp(
    'mainAlign',
    ScenePropKind.choice,
    owner: ScenePropOwner.frame,
    defaultValue: SceneMainAxisAlignment.start,
    choices: _mainAligns,
    read: _mainAlign,
    write: _setMainAlign,
  ),
  SceneProp(
    'crossAlign',
    ScenePropKind.choice,
    owner: ScenePropOwner.frame,
    defaultValue: SceneCrossAxisAlignment.center,
    choices: _crossAligns,
    read: _crossAlign,
    write: _setCrossAlign,
  ),
];

/// A text's own properties. The text itself is the positional argument and
/// is read and written through the table too, but spelled by hand.
const sceneTextProps = <SceneProp>[
  SceneProp(
    'text',
    ScenePropKind.string,
    owner: ScenePropOwner.text,
    defaultValue: '',
    read: _text,
    write: _setText,
  ),
  SceneProp(
    'fontSize',
    ScenePropKind.number,
    owner: ScenePropOwner.text,
    defaultValue: 16.0,
    animatable: true,
    read: _fontSize,
    write: _setFontSize,
  ),
  SceneProp(
    'weight',
    ScenePropKind.choice,
    owner: ScenePropOwner.text,
    defaultValue: SceneFontWeight.w400,
    choices: _weights,
    read: _weight,
    write: _setWeight,
  ),
  SceneProp(
    'color',
    ScenePropKind.color,
    owner: ScenePropOwner.text,
    defaultValue: SceneColor(0xFF1A1A1A),
    animatable: true,
    read: _color,
    write: _setColor,
  ),
  SceneProp(
    'align',
    ScenePropKind.choice,
    owner: ScenePropOwner.text,
    defaultValue: SceneTextAlign.left,
    choices: _aligns,
    read: _align,
    write: _setAlign,
  ),
  SceneProp(
    'maxLines',
    ScenePropKind.integer,
    owner: ScenePropOwner.text,
    read: _maxLines,
    write: _setMaxLines,
  ),
];

const sceneShapeProps = <SceneProp>[
  SceneProp(
    'circle',
    ScenePropKind.boolean,
    owner: ScenePropOwner.shape,
    defaultValue: false,
    read: _circle,
    write: _setCircle,
  ),
];

/// The table, whole.
const sceneProps = <SceneProp>[
  ...sceneCommonProps,
  ...sceneFrameProps,
  ...sceneTextProps,
  ...sceneShapeProps,
];

/// The properties [node] carries, in file order: its kind's own after the
/// common ones.
List<SceneProp> scenePropsOf(SceneNode node) => [
  for (var p in sceneProps)
    if (p.appliesTo(node)) p,
];

/// One property by name, when [node] carries it.
SceneProp? scenePropNamed(SceneNode node, String name) {
  for (var p in sceneProps) {
    if (p.name == name && p.appliesTo(node)) return p;
  }
  return null;
}

/// Whether [value] is what the property holds by default — the test that
/// decides whether it is written at all.
bool isSceneDefault(SceneProp p, Object? value) => switch (p.kind) {
  ScenePropKind.sizes =>
    (value! as List<double?>).isEmpty &&
        (p.defaultValue! as List<double?>).isEmpty,
  _ => value == p.defaultValue,
};

// ── accessors: the one place a name meets a field ─────────────────────────

Object? _x(SceneNode n) => n.x;
void _setX(SceneNode n, Object? v) => n.x = (v! as num).toDouble();
Object? _y(SceneNode n) => n.y;
void _setY(SceneNode n, Object? v) => n.y = (v! as num).toDouble();
Object? _width(SceneNode n) => n.width;
void _setWidth(SceneNode n, Object? v) => n.width = v as double?;
Object? _height(SceneNode n) => n.height;
void _setHeight(SceneNode n, Object? v) => n.height = v as double?;
Object? _fill(SceneNode n) => n.fill;
void _setFill(SceneNode n, Object? v) => n.fill = v as SceneColor?;
Object? _borderColor(SceneNode n) => n.borderColor;
void _setBorderColor(SceneNode n, Object? v) =>
    n.borderColor = v as SceneColor?;
Object? _borderWidth(SceneNode n) => n.borderWidth;
void _setBorderWidth(SceneNode n, Object? v) =>
    n.borderWidth = (v! as num).toDouble();
Object? _corner(SceneNode n) => n.corner;
void _setCorner(SceneNode n, Object? v) => n.corner = (v! as num).toDouble();
Object? _opacity(SceneNode n) => n.opacity;
void _setOpacity(SceneNode n, Object? v) => n.opacity = (v! as num).toDouble();
Object? _visible(SceneNode n) => n.visible;
void _setVisible(SceneNode n, Object? v) => n.visible = v! as bool;

Object? _layout(SceneNode n) => (n as FrameNode).layout;
void _setLayout(SceneNode n, Object? v) =>
    (n as FrameNode).layout = v! as NodeLayout;
Object? _gap(SceneNode n) => (n as FrameNode).gap;
void _setGap(SceneNode n, Object? v) =>
    (n as FrameNode).gap = (v! as num).toDouble();
Object? _padding(SceneNode n) => (n as FrameNode).padding;
void _setPadding(SceneNode n, Object? v) =>
    (n as FrameNode).padding = v! as SceneEdges;
Object? _columns(SceneNode n) => (n as FrameNode).columns;
void _setColumns(SceneNode n, Object? v) =>
    (n as FrameNode).columns = [...v! as List<double?>];
Object? _cellPadding(SceneNode n) => (n as FrameNode).cellPadding;
void _setCellPadding(SceneNode n, Object? v) =>
    (n as FrameNode).cellPadding = v! as SceneEdges;
Object? _mainAlign(SceneNode n) => (n as FrameNode).mainAlign;
void _setMainAlign(SceneNode n, Object? v) =>
    (n as FrameNode).mainAlign = v! as SceneMainAxisAlignment;
Object? _crossAlign(SceneNode n) => (n as FrameNode).crossAlign;
void _setCrossAlign(SceneNode n, Object? v) =>
    (n as FrameNode).crossAlign = v! as SceneCrossAxisAlignment;

Object? _text(SceneNode n) => (n as TextNode).text;
void _setText(SceneNode n, Object? v) => (n as TextNode).text = v! as String;
Object? _fontSize(SceneNode n) => (n as TextNode).fontSize;
void _setFontSize(SceneNode n, Object? v) =>
    (n as TextNode).fontSize = (v! as num).toDouble();
Object? _weight(SceneNode n) => (n as TextNode).weight;
void _setWeight(SceneNode n, Object? v) =>
    (n as TextNode).weight = v! as SceneFontWeight;
Object? _color(SceneNode n) => (n as TextNode).color;
void _setColor(SceneNode n, Object? v) =>
    (n as TextNode).color = v! as SceneColor;
Object? _align(SceneNode n) => (n as TextNode).align;
void _setAlign(SceneNode n, Object? v) =>
    (n as TextNode).align = v! as SceneTextAlign;
Object? _maxLines(SceneNode n) => (n as TextNode).maxLines;
void _setMaxLines(SceneNode n, Object? v) =>
    (n as TextNode).maxLines = v as int?;

Object? _circle(SceneNode n) => (n as ShapeNode).circle;
void _setCircle(SceneNode n, Object? v) => (n as ShapeNode).circle = v! as bool;
