// The scene document — a deliberately *uniform* node: every node carries the
// same styling bag (fill, corner, opacity) and the same geometry slots.
// Graduated from the canvas-toy spike 2026-09-01; pure Dart by decision
// (2026-09-01-scene-graduation-plan.md) so the headless surface can hold it.
import 'listenable.dart';
import 'values.dart';

part 'read_plane.dart';

/// How a frame arranges its children.
///
/// [table] is the one that is not a flex: its children are ROWS, their
/// children are cells, and the widths come from the frame's column tracks
/// rather than from each cell — which is the whole point of it. Stacked
/// rows each size their own columns and cannot agree; a table is what
/// agreeing across rows is called.
enum NodeLayout { absolute, row, column, table }

/// A node's name is its identity everywhere — the wire, the rects, the hit
/// targets — and in the file it is the *field name* the node is declared
/// under, so it must be a valid Dart identifier.
final _identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
const _reserved = {
  // Dart's reserved words — a field cannot be named these.
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default',
  'do', 'else', 'enum', 'extends', 'false', 'final', 'finally', 'for', 'if',
  'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', 'this',
  'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

bool isValidNodeName(String name) =>
    _identifier.hasMatch(name) && !_reserved.contains(name);

/// The typed hole: a constructor parameter whose default is the mockup.
/// Declared in the file as a primary-constructor formal with a default;
/// referenced by node properties by bare identifier. Parameters share the
/// class namespace with node fields.
///
/// A parameter's type. [list] is the one that is not a value: its default
/// is a list of items, and what reads it is a node's [SceneNode.repeat]
/// rather than a property. Substitution and repetition are the same
/// mechanism seen from two sides, which is why they share this table.
enum SceneParamKind { string, number, color, list }

/// One item of a list parameter: field name to value, and a value is a
/// string or a number — the two kinds a bound property can take.
typedef SceneItem = Map<String, Object>;

class SceneParamDecl {
  SceneParamDecl(this.name, this.kind, this.defaultValue);

  final String name;
  final SceneParamKind kind;

  /// String, double or [SceneColor] — the mockup, read by every consumer
  /// that passes no argument (the editor, the export matrix at the base
  /// point).
  final Object defaultValue;

  String get typeName => switch (kind) {
    SceneParamKind.string => 'String',
    SceneParamKind.number => 'double',
    SceneParamKind.color => 'SceneColor',
    // A record type, so `line.item` inside a repeat's closure is checked
    // against the fields the data actually has.
    SceneParamKind.list =>
      items.isEmpty
          ? 'List<Object?>'
          : 'List<({${[for (var e in items.first.entries) '${e.value is String ? 'String' : 'double'} ${e.key}'].join(', ')}})>',
  };

  /// The declared items, for a [SceneParamKind.list] — the mockup standing
  /// in for the data until a caller passes its own.
  List<SceneItem> get items => switch (kind) {
    SceneParamKind.list => (defaultValue as List).cast<SceneItem>(),
    _ => const [],
  };
}

sealed class SceneNode {
  /// Every authorable property this node kind shares, named exactly as the
  /// file spells it — because the file IS a call to this constructor. A
  /// property the grammar has and this does not is a property a scene file
  /// cannot compile, so the two cannot drift.
  SceneNode({
    this.name = '',
    this.x = 0,
    this.y = 0,
    this.width,
    this.height,
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
    this.corner = 0,
    this.opacity = 1,
  });

  /// The node's identity — the field name in the file, and SOURCE-LEVEL
  /// ONLY. A compiled scene leaves it empty: Dart has no field-name
  /// reflection, and at runtime a node's identity is the object, which is
  /// what makes `scene.headline` a typed reference rather than a lookup.
  /// The editor, which parsed the source, is what fills this in.
  String name;

  // Authored geometry. x/y are meaningful only under an absolute parent.
  double x;
  double y;

  /// Size along each axis, three-valued in one field:
  ///
  /// - `null` — **hug**: as big as the content needs.
  /// - a finite number — **fixed**.
  /// - [double.infinity] — **fill**: as much as the parent gives.
  ///
  /// The sentinel is Flutter's own vocabulary rather than an invention:
  /// `Container(width: double.infinity)` already means this, so the value
  /// reads the way it behaves and every reader that only passes it through
  /// keeps working. It is not JSON, though — `jsonEncode` refuses a
  /// non-finite double — so both the wire and the file spell it out; see
  /// [sizeToWire].
  ///
  /// Fill along the parent's MAIN axis needs that parent to be bounded on
  /// it: a column that hugs its height has no leftover to hand out. The
  /// renderer honours what it can and the editor is where the contradiction
  /// has to be shown, not hidden.
  double? width;
  double? height;

  /// Whether this node takes what the parent gives along each axis.
  bool get widthFills => width != null && width!.isInfinite;
  bool get heightFills => height != null && height!.isInfinite;

  // The uniform styling bag — the bet under test.
  SceneColor? fill;

  /// A line around the node, or none. Two fields rather than one value,
  /// because the file's vocabulary is flat named arguments and a
  /// `Border(...)` would be a construct the grammar does not have.
  SceneColor? borderColor;
  double borderWidth;

  double corner;
  double opacity;

  /// Laid-out rect in artboard coordinates, swept after each frame by
  /// whichever renderer measured it.
  SceneRect? measured;

  /// Which properties read a parameter: property key → parameter name.
  ///
  /// The READ plane's provenance, and empty in a compiled scene — there a
  /// property that reads a parameter reads a Dart variable, and nothing has
  /// to be recorded about it. The property here still holds the resolved
  /// value (the default, until [SceneReadPlane.applyArgs]); the ref
  /// survives a save only while that value still equals the parameter's
  /// default. See `read_plane.dart`.
  final paramRefs = <String, String>{};

  /// The evaluated plane: per-frame contributions composed OVER the
  /// authored values above, keyed by (writer, property) in writer-stack
  /// order — the order is normative (× does not bit-commute). Motion lanes
  /// and app [Effect]s write here; Save never reads it; a cancelled writer
  /// clears its own entries and the authored value was never touched.
  final fx = <(Object, String), Object>{};

  SceneDocument? _doc;

  void writeFx(Object writer, String prop, Object value) {
    fx[(writer, prop)] = value;
    _doc?.fxTick();
  }

  void removeFx(Object writer, String prop) {
    if (fx.remove((writer, prop)) != null) _doc?.fxTick();
  }

  void clearFxWriter(Object writer) {
    var before = fx.length;
    fx.removeWhere((k, _) => identical(k.$1, writer));
    if (fx.length != before) _doc?.fxTick();
  }

  /// Whether any writer currently contributes to [prop] — the renderer asks
  /// this where the authored value's absence means something (a null fill
  /// draws no decoration; a composed fill draws one).
  bool hasFx(String prop) => fx.keys.any((k) => k.$2 == prop);

  /// The composed value the renderer should draw: authored base folded with
  /// every contribution through the derived operator table — opacity and
  /// scale multiply, translations and rotation add, everything else
  /// replaces in stack order.
  Object fxRendered(String prop) {
    var v = _fxBase(prop);
    for (var entry in fx.entries) {
      if (entry.key.$2 != prop) continue;
      v = switch (prop) {
        'opacity' || 'scale' => (v as double) * (entry.value as double),
        'translateX' ||
        'translateY' ||
        'rotate' => (v as double) + (entry.value as double),
        _ => entry.value,
      };
    }
    return v;
  }

  Object _fxBase(String prop) => switch (prop) {
    'opacity' => opacity,
    'translateX' || 'translateY' || 'rotate' => 0.0,
    'scale' => 1.0,
    'fontSize' => (this as TextNode).fontSize,
    'color' => (this as TextNode).color,
    'gap' => (this as FrameNode).gap,
    'fill' => fill ?? const SceneColor(0x00000000),
    _ => throw ArgumentError('no animatable property "$prop"'),
  };

  /// Mint an app-side fx writer. Handles are the only app surface — two
  /// independent effects on one property compose instead of colliding, and
  /// clearing one leaves the others (sketch 25).
  Effect effect() => Effect._(this);

  String get typeName;

  List<SceneNode> get children => const [];
}

/// One app-side fx writer: cosmetic, composed, never saved. Setting a
/// property to null removes that contribution; [clear] removes them all.
class Effect {
  Effect._(this._node);

  final SceneNode _node;

  // Each property reads back this writer's OWN contribution (null when it
  // has none) — the composed result is the node's [SceneNode.fxRendered].
  double? get opacity => _get('opacity');
  set opacity(double? v) => _set('opacity', v);
  double? get scale => _get('scale');
  set scale(double? v) => _set('scale', v);
  double? get translateX => _get('translateX');
  set translateX(double? v) => _set('translateX', v);
  double? get translateY => _get('translateY');
  set translateY(double? v) => _set('translateY', v);
  double? get rotate => _get('rotate');
  set rotate(double? v) => _set('rotate', v);

  double? _get(String prop) => _node.fx[(this, prop)] as double?;

  void _set(String prop, double? v) {
    if (v == null) {
      _node.removeFx(this, prop);
    } else {
      _node.writeFx(this, prop, v);
    }
  }

  void clear() => _node.clearFxWriter(this);
}

/// A frame drawn once per item of a list.
///
/// The rule is a CLOSURE, because that is the only shape of it Dart can
/// check: `row: (line) => [TextNode(line.item)]` types `line` as the item
/// and `line.item` as its field, so a cell reading a field the data does
/// not have is a program that does not build.
///
/// The frame stays one frame — one field in the file, one row in the tree,
/// one thing to select and style. What multiplies is the picture.
class SceneRepeat {
  SceneRepeat({required this.items, required this.row, this.source = ''});

  /// The data. Records in a compiled scene, [SceneItem] maps in one the
  /// editor parsed; only [row] ever looks inside one.
  final List<Object?> items;

  /// One item's cells.
  final List<SceneNode> Function(Object? item) row;

  /// Which parameter the items came from — SOURCE-LEVEL, for the editor and
  /// the emitter. Empty in a compiled scene, where the closure is the whole
  /// binding and nothing needs to write it back out.
  final String source;
}

/// One number when one number says it, four names when it does not — the
/// grammar's own spelling of an inset, assembled into the value the model
/// carries.
SceneEdges _edges(
  double? all,
  double? left,
  double? top,
  double? right,
  double? bottom,
) => SceneEdges(
  left: left ?? all ?? 0,
  top: top ?? all ?? 0,
  right: right ?? all ?? 0,
  bottom: bottom ?? all ?? 0,
);

class FrameNode extends SceneNode {
  /// Padding comes in as the grammar spells it — one number when one number
  /// says it, four names when it does not — rather than as a [SceneEdges],
  /// which the file has no way to write.
  FrameNode({
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
    this.layout = NodeLayout.absolute,
    this.gap = 8,
    double? padding,
    double? paddingLeft,
    double? paddingTop,
    double? paddingRight,
    double? paddingBottom,
    List<double?>? columns,
    double? cellPadding,
    double? cellPaddingLeft,
    double? cellPaddingTop,
    double? cellPaddingRight,
    double? cellPaddingBottom,
    this.mainAlign = SceneMainAxisAlignment.start,
    this.crossAlign = SceneCrossAxisAlignment.center,
    List<SceneNode> children = const [],
  }) : columns = columns == null ? [] : [...columns],
       padding = _edges(
         padding,
         paddingLeft,
         paddingTop,
         paddingRight,
         paddingBottom,
       ),
       cellPadding = _edges(
         cellPadding,
         cellPaddingLeft,
         cellPaddingTop,
         cellPaddingRight,
         cellPaddingBottom,
       ) {
    this.children.addAll(children);
  }

  /// Drawn once per item of [SceneRepeat.items], or null for a frame drawn
  /// once. Built by [repeating] in a compiled scene; rebuilt from the
  /// recorded binding by [bindRepeats] in one that was parsed.
  SceneRepeat? repeated;

  NodeLayout layout;
  double gap;
  SceneEdges padding;

  /// The column tracks, when [layout] is [NodeLayout.table]. Each is a size
  /// in the same three-valued vocabulary as a node's: `null` hugs the
  /// widest cell in the column, a number is fixed, [double.infinity] takes
  /// what is left. A column nobody declared hugs.
  ///
  /// The tracks belong to the TABLE, not to the cells, and that is the
  /// difference a table makes: every row is measured against the same
  /// tracks, so the columns line up whatever each row happens to hold.
  List<double?> columns;

  /// Space inside every cell of a table. Cells are laid out by the table
  /// rather than by their own boxes, so this is where their breathing room
  /// has to be said; on any other layout it means nothing.
  SceneEdges cellPadding = SceneEdges.zero;
  SceneMainAxisAlignment mainAlign = SceneMainAxisAlignment.start;
  SceneCrossAxisAlignment crossAlign = SceneCrossAxisAlignment.center;

  /// A frame drawn once per item of [over], its cells built by [row].
  ///
  /// A static rather than a constructor because it is GENERIC: `T` is the
  /// item type, inferred from the list, and that is what makes `line.item`
  /// checked rather than dynamic. The cast inside cannot fail — the list
  /// and the closure arrive together.
  ///
  /// The frame's own children are the first item's cells, so the thing on
  /// screen and the thing in the file are the same row.
  static FrameNode repeating<T>({
    required List<T> over,
    required List<SceneNode> Function(T item) row,
    String name = '',
    double x = 0,
    double y = 0,
    double? width,
    double? height,
    SceneColor? fill,
    SceneColor? borderColor,
    double borderWidth = 1,
    double corner = 0,
    double opacity = 1,
    NodeLayout layout = NodeLayout.absolute,
    double gap = 8,
    double? padding,
    double? paddingLeft,
    double? paddingTop,
    double? paddingRight,
    double? paddingBottom,
    SceneMainAxisAlignment mainAlign = SceneMainAxisAlignment.start,
    SceneCrossAxisAlignment crossAlign = SceneCrossAxisAlignment.center,
  }) => FrameNode(
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    fill: fill,
    borderColor: borderColor,
    borderWidth: borderWidth,
    corner: corner,
    opacity: opacity,
    layout: layout,
    gap: gap,
    padding: padding,
    paddingLeft: paddingLeft,
    paddingTop: paddingTop,
    paddingRight: paddingRight,
    paddingBottom: paddingBottom,
    mainAlign: mainAlign,
    crossAlign: crossAlign,
    children: over.isEmpty ? const [] : row(over.first),
  )..repeated = SceneRepeat(items: over, row: (item) => row(item as T));

  @override
  final List<SceneNode> children = [];

  @override
  String get typeName => 'Frame';
}

class TextNode extends SceneNode {
  TextNode(
    this.text, {
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
    this.fontSize = 16,
    this.weight = SceneFontWeight.w400,
    this.color = const SceneColor(0xFF1A1A1A),
    this.align = SceneTextAlign.left,
    this.maxLines,
  });

  String text;
  double fontSize;
  SceneFontWeight weight;
  SceneColor color;
  SceneTextAlign align;

  /// How many lines before it is cut with an ellipsis, or null for as many
  /// as it takes. A banner filled per language is the reason: the layout
  /// that fits English has to survive German, and something has to give.
  int? maxLines;

  @override
  String get typeName => 'Text';
}

class ShapeNode extends SceneNode {
  ShapeNode({
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
    this.circle = false,
  });

  bool circle;

  @override
  String get typeName => 'Shape';
}

/// What an [ExternalNode] builds, given the args of the moment.
///
/// The return is `Object` and not `Widget` because this half of the scene
/// system is pure Dart by decision — a widget is a subtype of Object, so a
/// file writing `(a) => app.DrinkBadge(…)` satisfies it, and the renderer
/// is where it becomes a Widget again.
typedef SceneWidgetBuilder = Object Function(SceneArgs args);

/// An external node's arguments, read by name and by kind.
///
/// Names are strings here and stay strings: a foreign widget's parameters
/// are not something a scene can type, which is why the motion grammar
/// already calls this its one stringly boundary. What the reader buys is
/// that a missing or wrong-kinded arg is a null rather than a crash, and
/// that the file never writes a cast.
class SceneArgs {
  const SceneArgs(this._values);

  final Map<String, Object?> _values;

  double? number(String name) => switch (_values[name]) {
    num n => n.toDouble(),
    _ => null,
  };

  String? text(String name) => switch (_values[name]) {
    String s => s,
    var v when v != null => '$v',
    _ => null,
  };

  SceneColor? color(String name) => switch (_values[name]) {
    SceneColor c => c,
    num argb => SceneColor(argb.toInt()),
    _ => null,
  };

  bool? flag(String name) => switch (_values[name]) {
    bool b => b,
    _ => null,
  };

  /// Every name the node carries — what an editor lists.
  Iterable<String> get names => _values.keys;
}

/// One parameter a widget declaration names, with the value it falls back
/// to when a scene sets nothing.
///
/// The type is the type argument, and it survives to runtime as [type] —
/// which is how an editor can be told `size` is a `double` without anything
/// having resolved the widget's own source.
class Arg<T> {
  const Arg(this.name, [this.fallback]);

  final String name;
  final T? fallback;

  Type get type => T;
}

/// What the app says about a widget a scene may place: its label, the
/// arguments it takes, and how to make one.
///
/// This is the file that stands in for resolving the app package, and the
/// only place in the system where an argument is named by a string. Written
/// by hand, it must compile before anything has been generated from it —
/// so it names nothing generated, and [build] reads its arguments by name
/// like the untyped thing it is.
class ExternalWidget {
  const ExternalWidget(this.entry, {this.args = const [], required this.build});

  final String entry;
  final List<Arg<Object>> args;

  /// Makes the widget. The one closure in the system, and it belongs here:
  /// only the app knows what a mockup instance is made of.
  ///
  /// Returns `Object` rather than `Widget` because this half of the scene
  /// system is pure Dart by decision; the renderer is where it becomes a
  /// widget again.
  final Object Function(SceneArgs args) build;
}

/// The generated argument object a node carries — one class per declared
/// widget or nested scene, with a field per argument.
///
/// A scene file writes `ExternalNode(const DrinkBadgeArgs(size: 140))` and
/// no strings at all: the class IS the widget's identity, its fields are
/// the declared arguments, and an argument the widget does not take cannot
/// be written down. [entry] is what crosses the editor's wire, where a
/// generated type cannot go.
sealed class SceneNodeArgs {
  const SceneNodeArgs();

  String get entry;

  /// This, with [fx] on top — how an animated frame is built. Every
  /// generated override narrows the return to its own type, so the whole
  /// render path stays typed.
  SceneNodeArgs merge(SceneArgs fx);

  Map<String, Object?> toMap();
}

abstract class SceneExtArgs extends SceneNodeArgs {
  const SceneExtArgs();

  @override
  SceneExtArgs merge(SceneArgs fx);

  /// The widget, built through the declaration this class was generated
  /// from. A node can therefore draw itself, which is why a shipped app
  /// hands the view nothing.
  Object build();
}

abstract class SceneRefArgs extends SceneNodeArgs {
  const SceneRefArgs();

  @override
  SceneRefArgs merge(SceneArgs fx);

  /// The nested scene, by a direct constructor call the compiler checks.
  SceneDefinition build();
}

/// A widget from the app, placed in a scene.
///
/// The file holds one TYPED ARGUMENT OBJECT — `ExternalNode(const
/// DrinkBadgeArgs(size: 140))` — generated from the app's declaration of
/// that widget. There are no strings here and no closure: the class is the
/// widget's identity, and an argument it does not declare cannot be
/// written. [entry] is what crosses the editor's wire, where a generated
/// type cannot go.
class ExternalNode extends SceneNode {
  ExternalNode(
    SceneExtArgs declared, {
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
  }) : declared = declared,
       entry = declared.entry,
       args = declared.toMap();

  /// A node the tool READ — from a scene file it parsed, or from the wire.
  /// It has the label and the values but not the generated class, because
  /// the editor does not compile the app.
  ExternalNode.read(
    this.entry, {
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
    Map<String, Object?>? args,
  }) : declared = null,
       args = args ?? {};

  final String entry;
  final Map<String, Object?> args;

  /// The typed arguments, when this node was compiled rather than read.
  /// A generated type is not data, so it never crosses the editor's wire —
  /// see [entry] for what does.
  SceneExtArgs? declared;

  /// How the widget is made, for a node that was READ. Bound by whoever
  /// holds the app's declarations — see `bindExternals` — because a
  /// document that arrived as data has no class to ask.
  SceneWidgetBuilder? builder;

  /// Authored args with fx contributions folded in (an ext arg's operator
  /// is replace, in stack order) — what the guest should render.
  Map<String, Object?> get renderedArgs {
    var out = Map.of(args);
    for (var entry in fx.entries) {
      var prop = entry.key.$2;
      if (prop.startsWith('args.')) out[prop.substring(5)] = entry.value;
    }
    return out;
  }

  /// The widget for the moment the fx plane is parked at.
  ///
  /// A compiled node builds through its own generated class, which reaches
  /// the declaration itself — which is why a shipped app hands the view
  /// nothing. A read one goes through whatever bound it.
  Object? buildWidget() => switch (declared) {
    var d? => d.merge(SceneArgs(renderedArgs)).build(),
    null => builder?.call(SceneArgs(renderedArgs)),
  };

  @override
  String get typeName => 'Ext';
}

/// An instance of another scene, by class name, with that scene's
/// parameters overridden by [args].
///
/// The instance's internals are not addressable from here — the nesting
/// law: the parent sees one box, the child is edited in its own file. What
/// the parent may animate is the imposed vocabulary on the box plus the
/// child's declared parameters, as `args.<param>` tracks.
///
/// [instance] is runtime state, like `measured`: whoever can find files —
/// the workspace — resolves the class name and instantiates the child with
/// [args]; nothing serializes it, and a node nobody resolved draws as a
/// placeholder naming what it wanted.
class SceneRefNode extends SceneNode {
  SceneRefNode(
    SceneRefArgs declared, {
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
  }) : declared = declared,
       sceneClassName = declared.entry,
       args = declared.toMap();

  /// A node the tool READ; see [ExternalNode.read].
  SceneRefNode.read(
    this.sceneClassName, {
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.fill,
    super.borderColor,
    super.borderWidth,
    super.corner,
    super.opacity,
    Map<String, Object?>? args,
  }) : declared = null,
       args = args ?? {};

  final String sceneClassName;
  final Map<String, Object?> args;

  /// The typed arguments, when this node was compiled rather than read —
  /// `const PromoBadgeArgs(label: 'Now open')`, whose `build` is a direct
  /// constructor call to the other scene class that the compiler checks.
  SceneRefArgs? declared;

  SceneDocument? instance;

  /// The authored args with the motion's `args.*` writes on top.
  Map<String, Object?> get renderedArgs {
    var out = Map.of(args);
    for (var entry in fx.entries) {
      var prop = entry.key.$2;
      if (prop.startsWith('args.')) out[prop.substring(5)] = entry.value;
    }
    return out;
  }

  /// Puts the rendered args onto the instance — every declared parameter,
  /// so one the motion stopped writing falls back to its default rather
  /// than staying wherever the last frame left it.
  void syncInstance() {
    // Compiled: the builder IS how args reach the child, so the instance is
    // rebuilt from the args of the moment. A parsed child has paramRefs and
    // takes them the other way, in place.
    if (declared case var d?) {
      instance = d.merge(SceneArgs(renderedArgs)).build().scene;
      return;
    }
    var inst = instance;
    if (inst == null) return;
    inst.applyArgs({
      for (var p in inst.params) p.name: p.defaultValue,
      ...renderedArgs,
    });
  }

  @override
  String get typeName => 'Scene';
}

/// What a `.scene.dart` class extends — the seam between a scene as Dart and
/// a scene as a document.
///
/// The generated file is a REAL Dart file: it compiles, it analyzes, and an
/// app instantiates it with typed arguments. The class declares its nodes as
/// `late final` fields and names one of them `root`; this turns that into
/// the document every other surface consumes.
///
/// Nothing here reads a name. A node's identity at runtime is the OBJECT —
/// which is what lets a motion say `scene.headline` and have the compiler
/// check it — and the field names live only in the source, where the editor
/// reads them.
abstract class SceneDefinition {
  FrameNode get root;

  /// This definition as a document, built once.
  late final SceneDocument scene = SceneDocument(root);
}

class SceneDocument extends SceneListenable {
  SceneDocument(this.root) {
    _adopt();
  }

  final FrameNode root;

  /// Every node knows its document, so an fx write anywhere schedules the
  /// one coalesced flush. Re-swept after each [edit] — structure may move.
  void _adopt() {
    for (var (node, _) in walk()) {
      node._doc = this;
    }
  }

  var _fxScheduled = false;

  /// The probed frame-aligned flush (500 writes → 1 rebuild): coalesce all
  /// fx writes of a batch into one notification, through whatever
  /// [sceneFlushScheduler] the process installed.
  void fxTick() {
    if (_fxScheduled) return;
    _fxScheduled = true;
    sceneFlushScheduler(() {
      _fxScheduled = false;
      notifyListeners();
    });
  }

  /// The scene's declared parameters, in declaration order.
  final params = <SceneParamDecl>[];

  /// List arguments a caller passed, overriding the declared mockups until
  /// the next [SceneReadPlane.applyArgs]. Scalar arguments need no such
  /// table — they land in the properties that read them — but nothing holds
  /// a list, so this does. Storage for the read plane; empty in a compiled
  /// scene, where the list is a constructor parameter.
  final _lists = <String, List<SceneItem>>{};

  SceneParamDecl? paramNamed(String name) {
    for (var p in params) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// What to draw for one child slot: the node itself, and one copy per
  /// FURTHER item when it repeats.
  ///
  /// The first item is not a copy — it is the node, holding the authored
  /// values, so it keeps its identity: its fx writers, its selection
  /// outline and the rect the editor drags by are all still its own. The
  /// copies are pictures, renamed `<name>#1`, `#2`… so no key or measured
  /// rect of theirs can be mistaken for the template's.
  List<SceneNode> expand(SceneNode child) {
    if (child is! FrameNode) return [child];
    var rep = child.repeated;
    if (rep == null) return [child];
    // No data, nothing drawn — the honest answer for a table of an empty
    // list, and the reason the mockup in the file is not empty.
    if (rep.items.isEmpty) return const [];
    return [
      child,
      for (var i = 1; i < rep.items.length; i++) _drawnRow(child, rep, i),
    ];
  }

  /// Row [i] of a repeat: a copy of the template holding that item's cells.
  ///
  /// Every name in it takes the `#i` suffix — the cells come out of the
  /// closure carrying the template's own names, and a copy answering to the
  /// template's name is a copy the editor outlines as the selection and
  /// measures the template by.
  SceneNode _drawnRow(FrameNode template, SceneRepeat rep, int i) {
    var copy = deepCopyNode(template, rename: (n) => '$n#$i') as FrameNode;
    copy.children
      ..clear()
      ..addAll(rep.row(rep.items[i]));
    void suffix(SceneNode n) {
      if (n.name.isNotEmpty) n.name = '${n.name}#$i';
      n.children.forEach(suffix);
    }

    copy.children.forEach(suffix);
    return copy;
  }

  /// Bumped when a post-frame sweep finds moved geometry, so overlays repaint
  /// without rebuilding the scene.
  final geometryEpoch = SceneValue(0);

  void edit(void Function() fn) {
    fn();
    _adopt();
    notifyListeners();
  }

  /// The wire the scene host renders from — data, never code, and a
  /// PICTURE rather than a document: it carries rendered values (base op
  /// fx), so a playing motion reaches the guest as a stream of these, one
  /// per flush. Selection is editor chrome riding along for hosts that
  /// outline it — the editor's, never the document's.
  ///
  /// Deliberately not `toJson`: that name belongs to the authored document
  /// (`SceneDocumentJson.toJson`), which is what a guest needs when it will
  /// evaluate the motion itself instead of being fed frames.
  Map<String, dynamic> toWire({Iterable<String> selected = const []}) => {
    'root': _json(root),
    'selected': [...selected],
  };

  Map<String, dynamic> _json(SceneNode n) {
    var tx = n.fxRendered('translateX') as double;
    var ty = n.fxRendered('translateY') as double;
    var scale = n.fxRendered('scale') as double;
    var rotate = n.fxRendered('rotate') as double;
    var fill = n.hasFx('fill') ? n.fxRendered('fill') as SceneColor : n.fill;
    return {
      'name': n.name,
      'x': n.x,
      'y': n.y,
      'w': sizeToWire(n.width),
      'h': sizeToWire(n.height),
      'fill': fill?.argb,
      if (n.borderColor case var b?) 'border': [b.argb, n.borderWidth],
      'corner': n.corner,
      'opacity': n.fxRendered('opacity'),
      // The imposed transforms have no authored slots — identity is the
      // base — so they ride the wire only when a writer moves them.
      // [translateX, translateY, scale, rotate°], applied about the center.
      if (tx != 0 || ty != 0 || scale != 1 || rotate != 0)
        'fx': [tx, ty, scale, rotate],
      ...switch (n) {
        FrameNode f => {
          'kind': 'frame',
          'layout': f.layout.name,
          'gap': f.fxRendered('gap'),
          'padding': f.padding.toWire(),
          if (f.columns.isNotEmpty)
            'columns': [for (var c in f.columns) sizeToWire(c)],
          if (!f.cellPadding.isZero) 'cellPadding': f.cellPadding.toWire(),
          'mainAlign': f.mainAlign.index,
          'crossAlign': f.crossAlign.index,
          // The wire is a picture, so a repeat is already spent here: the
          // host is handed the rows rather than the rule that made them.
          'children': [
            for (var c in f.children)
              for (var drawn in expand(c)) _json(drawn),
          ],
        },
        TextNode t => {
          'kind': 'text',
          'align': t.align.index,
          if (t.maxLines != null) 'maxLines': ?t.maxLines,
          'text': t.text,
          'fontSize': t.fxRendered('fontSize'),
          'weight': t.weight.index,
          'color': (t.fxRendered('color') as SceneColor).argb,
        },
        ShapeNode s => {'kind': 'shape', 'circle': s.circle},
        ExternalNode e => {
          'kind': 'ext',
          'entry': e.entry,
          'args': e.renderedArgs,
        },
        SceneRefNode r => _refWire(r),
      },
    };
  }

  /// The instance's own picture, flattened under the ref node's box: the
  /// host draws frames and needs no resolver. Internal names are prefixed
  /// with the ref's, so a measured rect never lands on a parent node by
  /// coincidence — and never lands at all, since only parent names are
  /// looked up.
  Map<String, dynamic> _refWire(SceneRefNode r) {
    var inst = r.instance;
    if (inst == null) {
      return {'kind': 'frame', 'layout': 'absolute', 'children': const []};
    }
    r.syncInstance();
    var picture = inst._json(inst.root);
    Map<String, dynamic> prefixed(Map<String, dynamic> json) => {
      ...json,
      'name': '${r.name}/${json['name']}',
      if (json['children'] case List children)
        'children': [
          for (var c in children) prefixed(c as Map<String, dynamic>),
        ],
    };
    var children = (picture['children'] as List? ?? const [])
        .map((c) => prefixed(c as Map<String, dynamic>))
        .toList();
    // The box is the ref's; the child's root supplies what the ref leaves
    // to hug (size) or inherit (fill, corner). Opacities multiply.
    return {
      'kind': 'frame',
      'layout': picture['layout'],
      'gap': picture['gap'],
      'padding': picture['padding'],
      'mainAlign': picture['mainAlign'],
      'crossAlign': picture['crossAlign'],
      'children': children,
      'w': sizeToWire(r.width) ?? picture['w'],
      'h': r.height ?? picture['h'],
      if (r.fill == null && !r.hasFx('fill')) 'fill': picture['fill'],
      if (r.corner == 0) 'corner': picture['corner'],
      'opacity':
          (r.fxRendered('opacity') as double) *
          ((picture['opacity'] as num?)?.toDouble() ?? 1),
    };
  }

  Iterable<(SceneNode, int)> walk() sync* {
    Iterable<(SceneNode, int)> visit(SceneNode n, int depth) sync* {
      yield (n, depth);
      for (var c in n.children) {
        yield* visit(c, depth + 1);
      }
    }

    yield* visit(root, 0);
  }

  /// A fresh identifier-shaped name — names are field names in the file, so
  /// they must be unique and valid Dart identifiers from the moment a node is
  /// created, not sanitized at save time.
  String uniqueName(String base) {
    var taken = {for (var (n, _) in walk()) n.name};
    var i = 1;
    while (taken.contains('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  /// The node declared under [name], or null — names are field names, so
  /// this is the resolution a motion target (`scene.headline`) performs.
  SceneNode? nodeNamed(String name) {
    for (var (node, _) in walk()) {
      if (node.name == name) return node;
    }
    return null;
  }

  FrameNode? parentOf(SceneNode node) {
    FrameNode? search(FrameNode frame) {
      if (frame.children.contains(node)) return frame;
      for (var c in frame.children.whereType<FrameNode>()) {
        var found = search(c);
        if (found != null) return found;
      }
      return null;
    }

    return search(root);
  }

  void delete(SceneNode node) {
    var parent = parentOf(node);
    if (parent == null) return;
    edit(() {
      parent.children.remove(node);
    });
  }

  void reorder(SceneNode node, int newIndex) {
    var parent = parentOf(node);
    if (parent == null) return;
    var index = parent.children.indexOf(node);
    var clamped = newIndex.clamp(0, parent.children.length - 1);
    if (index == clamped) return;
    edit(() {
      parent.children.removeAt(index);
      parent.children.insert(clamped, node);
    });
  }

  /// Topmost direct child of [scope] containing the point (artboard coords).
  SceneNode? hitShallow(double x, double y, {FrameNode? scope}) {
    var frame = scope ?? root;
    for (var c in frame.children.reversed) {
      var rect = c.measured;
      if (rect != null && rect.contains(x, y)) return c;
    }
    return null;
  }

  /// Deepest node under the point.
  SceneNode? hitDeep(double x, double y) {
    SceneNode? visit(SceneNode n) {
      var rect = n.measured;
      if (rect == null || !rect.contains(x, y)) return null;
      for (var c in n.children.reversed) {
        var hit = visit(c);
        if (hit != null) return hit;
      }
      return n == root ? null : n;
    }

    return visit(root);
  }

  /// The authored plane, captured: params and the node tree, deep-copied.
  /// The fx plane is NOT part of a snapshot — it is evaluated state owned
  /// by its writers, and restoring authored values must not cancel a
  /// playing motion (the same law as Save never reading fx).
  SceneSnapshot snapshot() =>
      SceneSnapshot._([...params], deepCopyNode(root) as FrameNode);

  /// Write [state] back into this document — the undo door's other half.
  /// Nodes are REVIVED, not replaced: a live node with the snapshot's name
  /// and kind gets the state copied into it and keeps its object identity,
  /// so fx writers (an [Effect], a bound motion), widget keys and anything
  /// else holding the node keep working across an undo. Only nodes the
  /// snapshot has and the document lost come back as fresh copies.
  void restore(SceneSnapshot state) {
    edit(() {
      params
        ..clear()
        ..addAll(state._params);
      var live = {for (var (n, _) in walk()) n.name: n};
      SceneNode revive(SceneNode snap) {
        var into = live[snap.name];
        if (into == null ||
            into.runtimeType != snap.runtimeType ||
            (into is ExternalNode &&
                into.entry != (snap as ExternalNode).entry) ||
            (into is SceneRefNode &&
                into.sceneClassName != (snap as SceneRefNode).sceneClassName)) {
          return deepCopyNode(snap);
        }
        switch ((into, snap)) {
          case (FrameNode i, FrameNode s):
            i
              ..layout = s.layout
              ..gap = s.gap
              ..padding = s.padding
              ..columns = [...s.columns]
              ..cellPadding = s.cellPadding
              ..repeated = s.repeated
              ..mainAlign = s.mainAlign
              ..crossAlign = s.crossAlign
              ..children.clear()
              ..children.addAll([for (var c in s.children) revive(c)]);
          case (TextNode i, TextNode s):
            i
              ..text = s.text
              ..fontSize = s.fontSize
              ..weight = s.weight
              ..color = s.color
              ..align = s.align
              ..maxLines = s.maxLines;
          case (ShapeNode i, ShapeNode s):
            i.circle = s.circle;
          case (ExternalNode i, ExternalNode s):
            i
              ..declared = s.declared
              ..builder = s.builder
              ..args.clear();
            i.args.addAll(s.args);
          case (SceneRefNode i, SceneRefNode s):
            i
              ..declared = s.declared
              ..args.clear();
            i.args.addAll(s.args);
          default:
            throw StateError('unreachable: kinds matched above');
        }
        into
          ..x = snap.x
          ..y = snap.y
          ..width = snap.width
          ..height = snap.height
          ..fill = snap.fill
          ..borderColor = snap.borderColor
          ..borderWidth = snap.borderWidth
          ..corner = snap.corner
          ..opacity = snap.opacity
          ..paramRefs.clear()
          ..paramRefs.addAll(snap.paramRefs);
        return into;
      }

      revive(state._root);
      // A node the snapshot brought back is a NEW object, and a repeat's
      // closure reads the cells of the one it was built for. Rebound here
      // rather than left to whoever notices.
      bindRepeats(this);
    });
  }
}

/// The authored half of a document at one moment. Opaque: made by
/// [SceneDocument.snapshot], consumed by [SceneDocument.restore], reusable —
/// restoring copies out of it, never hands its own nodes over.
class SceneSnapshot {
  SceneSnapshot._(this._params, this._root);

  final List<SceneParamDecl> _params;
  final FrameNode _root;
}

/// A deep copy of [node]'s authored plane — every authored property,
/// paramRefs and children; never fx, measured geometry or the document
/// pointer. [rename] maps every name in the subtree (a duplicate needs
/// fresh names — names are field identity, unique per scene); a snapshot
/// passes nothing and keeps them.
SceneNode deepCopyNode(SceneNode node, {String Function(String)? rename}) {
  var name = rename == null ? node.name : rename(node.name);
  var copy = switch (node) {
    FrameNode f =>
      FrameNode(name: name, layout: f.layout)
        ..gap = f.gap
        ..padding = f.padding
        ..columns = [...f.columns]
        ..cellPadding = f.cellPadding
        // A renamed copy is one drawn ROW, not the rule that drew it —
        // carrying the repeat would make each copy repeat again.
        ..repeated = rename == null ? f.repeated : null
        ..mainAlign = f.mainAlign
        ..crossAlign = f.crossAlign
        ..children.addAll([
          for (var c in f.children) deepCopyNode(c, rename: rename),
        ]),
    TextNode t =>
      TextNode(t.text, name: name)
        ..fontSize = t.fontSize
        ..weight = t.weight
        ..color = t.color
        ..align = t.align
        ..maxLines = t.maxLines,
    ShapeNode s => ShapeNode(name: name, circle: s.circle),
    ExternalNode e =>
      ExternalNode.read(e.entry, name: name, args: Map.of(e.args))
        ..declared = e.declared
        ..builder = e.builder,
    // The instance is copied too, so the copy draws at once; each copy owns
    // its own, because args are applied by mutating it.
    SceneRefNode r =>
      SceneRefNode.read(r.sceneClassName, name: name, args: Map.of(r.args))
        ..declared = r.declared
        ..instance = r.instance == null
            ? null
            : instantiateScene(r.instance!, r.args),
  };
  copy
    ..x = node.x
    ..y = node.y
    ..width = node.width
    ..height = node.height
    ..fill = node.fill
    ..borderColor = node.borderColor
    ..borderWidth = node.borderWidth
    ..corner = node.corner
    ..opacity = node.opacity
    ..paramRefs.addAll(node.paramRefs);
  return copy;
}
