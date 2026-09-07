// The inspector, rebuilt on the design system and on the salvaged number
// editors — the first panel of the spike's four to be redone in its final
// home.
//
// Two things it does that the toy's inspector did not. Every number is a
// SceneNumberField, so a property's own metadata decides whether it is
// dragged, dragged beside a slider, or turned on a dial, and one gesture is
// one undo entry (the field commits once, on release, under the door's merge
// key). And every colour, weight and alignment goes through the studio's own
// controls rather than stock Material.
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../externals_file.dart';

import '../../ui/context_menu.dart';
import '../../ui/disclosure.dart';
import '../../ui/design/design.dart';
import '../../ui/action_button.dart';
import '../../ui/menu.dart';
import '../../ui/picker.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import 'curve_picker.dart';
import 'number_shape.dart';
import 'number_field.dart';
import 'swatches.dart';

/// The three states a size can be in, in the order the menu offers them.
enum _SizeMode {
  fixed('fixed'),
  hug('hug'),
  fill('fill');

  const _SizeMode(this.label);
  final String label;
}

class SceneInspector extends StatelessWidget {
  const SceneInspector(
    this.editor, {
    super.key,
    this.externals = const [],
    this.onOpenParam,
    this.onEnterNested,
  });

  final SceneEditor editor;

  /// Opens a parameter below the canvas — where a bound property's row
  /// leads.
  final ValueChanged<String>? onOpenParam;

  /// Drills into the scene a nested instance stands for — its main.
  final ValueChanged<SceneNode>? onEnterNested;

  /// The widgets the app declares. This is the whole of what the editor
  /// knows about a foreign widget — nothing here resolves the app package —
  /// and it is why an external node's arguments can be shown with their
  /// types and their defaults rather than guessed from whatever value the
  /// scene happens to carry.
  final List<ExternalWidgetDecl> externals;

  SceneDocument get doc => editor.doc;

  /// Every edit is a door, and consecutive edits of one property on one node
  /// merge into a single undo entry — which is what makes a drag one entry
  /// rather than sixty.
  void _door(String prop, void Function() fn) {
    var name = (editor.primary ?? doc.root).name;
    editor.perform('Edit $prop', mergeKey: 'inspect:$prop:$name', fn);
  }

  /// What a field shows for [prop]: while recording, what the motion has
  /// the node at — the key under the playhead, which the field is editing —
  /// and the node's own value otherwise. A field showing the authored value
  /// while its edits went to a key would snap back on every frame.
  T _shown<T>(SceneNode node, String prop, T authored) =>
      editor.records(node, prop) ? node.fxRendered(prop) as T : authored;

  /// An edit to an animatable property: a key at the playhead while
  /// recording, the node's own value otherwise.
  void _set(String prop, Object value, void Function() apply) {
    var node = editor.primary ?? doc.root;
    var name = node.name;
    if (editor.recordKey(node, prop, value, mergeKey: 'record:$prop:$name')) {
      return;
    }
    _door(prop, apply);
  }

  @override
  Widget build(BuildContext context) {
    if (editor.selectedKeys.isNotEmpty) return _keys(context);
    var node = editor.primary ?? doc.root;
    var parent = node == doc.root ? null : doc.parentOf(node);
    var inFlex = parent != null && parent.layout != NodeLayout.absolute;
    var isRow = parent != null && parent.layout == NodeLayout.table;

    return ListView(
      key: ValueKey('inspector:${node.name}'),
      padding: const EdgeInsets.all(FwSpacing.lg),
      children: [
        Text(
          node == doc.root
              ? 'Artboard · ${node.name}'
              : '${node.typeName} · ${node.name}',
          style: context.type.bodyStrong,
        ),
        // The root is not selectable — it is the page, not a thing on it —
        // and this panel falls back to it when nothing is selected. Saying
        // so is the difference between "here is your selection" and "you
        // have none", which the tree was telling the truth about all along.
        if (node == doc.root && editor.selectedNodes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FwSpacing.xxs),
            child: Text(
              'nothing selected',
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
          ),
        const SizedBox(height: FwSpacing.lg),
        if (node.bindings.isNotEmpty) ..._bindings(context, node),
        if (isRow)
          // A row under a table is not laid out at all: the table places the
          // cells, and the row is what paints behind them. Saying so beats
          // leaving a column of controls that quietly do nothing.
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: Text(
              'A row of ${parent.name}. It paints the fill, the border and '
              'the corner; ${parent.name} lays out the cells.',
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
          )
        else if (inFlex)
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: Text(
              'Position measured by parent layout',
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
          ),
        _row([
          _number(
            'x',
            'X',
            node.x,
            SceneNumberShape.pixels,
            enabled: !inFlex && node != doc.root,
            apply: (v) => node.x = v,
          ),
          _number(
            'y',
            'Y',
            node.y,
            SceneNumberShape.pixels,
            enabled: !inFlex && node != doc.root,
            apply: (v) => node.y = v,
          ),
        ]),
        _row([
          _bindable(
            context,
            node,
            'width',
            _size(
              'W',
              node,
              node.width,
              horizontal: true,
              onChanged: (v) => node.width = v,
            ),
          ),
          _bindable(
            context,
            node,
            'height',
            _size(
              'H',
              node,
              node.height,
              horizontal: false,
              onChanged: (v) => node.height = v,
            ),
          ),
        ]),
        const SizedBox(height: FwSpacing.md),
        _label(context, 'Fill'),
        _bindable(
          context,
          node,
          'fill',
          SceneSwatches(
            current: editor.records(node, 'fill') && node.hasFx('fill')
                ? node.fxRendered('fill') as SceneColor
                : node.fill,
            // No fill is not a colour a key can hold: that one edits the
            // node.
            onPick: (c) => c == null
                ? _door('fill', () => node.fill = null)
                : _set('fill', c, () => node.fill = c),
          ),
        ),
        const SizedBox(height: FwSpacing.md),
        _label(context, 'Border'),
        SceneSwatches(
          current: node.borderColor,
          onPick: (c) => _door('borderColor', () => node.borderColor = c),
        ),
        if (node.borderColor != null)
          _row([
            _number(
              'borderWidth',
              'Width',
              node.borderWidth,
              SceneNumberShape.pixels,
              apply: (v) => node.borderWidth = v,
            ),
          ]),
        _row([
          _number(
            'corner',
            node.corners.isUniform ? 'Corner' : 'Corners · all',
            node.corners.isUniform ? node.corner : 0,
            SceneNumberShape.pixels,
            apply: (v) => node.corner = v,
          ),
          _number(
            'opacity',
            'Opacity',
            _shown(node, 'opacity', node.opacity),
            SceneNumberShape.of(propSpecFor(node, 'opacity')),
            apply: (v) => node.opacity = v.clamp(0, 1),
          ),
        ]),
        // One number for most nodes; four when a corner has to differ, the
        // way a padding names its sides. Bounds likewise: behind a word
        // until a node has any, because most never will. Both words share a
        // line, so the folded state costs one row.
        if (node.corners.isUniform && !_hasBounds(node))
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            // A Wrap, not a Row: two short words in the app's font, and a
            // second line rather than an overflow under a wider one.
            child: Wrap(
              spacing: FwSpacing.md,
              children: [
                _cornersWord(context, node),
                _boundsWord(context, node),
              ],
            ),
          )
        else ...[
          ..._corners(context, node),
          ..._bounds(context, node),
        ],
        if (node != doc.root)
          _bindable(
            context,
            node,
            'visible',
            _check(
              context,
              'Visible',
              node.visible,
              () => _door('visible', () => node.visible = !node.visible),
            ),
          ),
        if (node != doc.root) ..._repeat(context, node),
        const Divider(height: FwSpacing.xxl),
        ...switch (node) {
          TextNode t => _textProps(context, t),
          FrameNode f => isRow ? const [] : _frameProps(context, f),
          ShapeNode s => _shapeProps(context, s),
          ExternalNode e => _extProps(context, e),
          SceneRefNode r => _sceneProps(context, r),
        },
      ],
    );
  }

  // A live drag writes through on every sample — the canvas is the feedback —
  // and closes its merge run on release, so one gesture is one undo entry and
  // the next gesture is a different one.
  Widget _number(
    String prop,
    String label,
    double value,
    SceneNumberShape shape, {
    required void Function(double) apply,
    bool enabled = true,
  }) => Builder(
    builder: (context) => _bindable(
      context,
      editor.primary ?? doc.root,
      prop,
      Opacity(
        opacity: enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: SceneNumberField(
            label: label,
            value: value,
            shape: shape,
            onChanged: (v) => _set(prop, v, () => apply(v)),
            onCommit: (v) {
              _set(prop, v, () => apply(v));
              editor.endMerge();
            },
          ),
        ),
      ),
    ),
  );

  /// Right-click on a property: make a parameter of it, bind it to one that
  /// exists, or unbind it. Nothing for a property no parameter can fill —
  /// the menu simply is not there.
  Widget _bindable(
    BuildContext context,
    SceneNode node,
    String prop,
    Widget child,
  ) {
    var kind = bindableKind(node, prop);
    if (kind == null) return child;
    // Bound to the app's own value: there is nothing here to edit — the
    // guest draws it — so the control gives way to the fact.
    if (node.bindings[prop] case TokenRef(:var name)
        when doc.tokenNamed(name)?.isExport == true) {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
        child: Text(
          '← tokens.$name · from the app',
          style: context.type.caption.copyWith(color: context.colors.mut2),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (d) {
        var bound = node.bindings[prop];
        var candidates = [
          for (var p in doc.params)
            if (p.kind == kind) p,
        ];
        var tokens = [
          for (var t in doc.tokens)
            if (t.kind == kind && t.hasValue) t,
        ];
        var exports = [
          for (var t in doc.tokens)
            if (t.kind == kind && t.isExport) t,
        ];
        showContextMenu(context, d.globalPosition, [
          MenuHeader(_propLabel(prop)),
          if (bound != null) ...[
            MenuItem('Reads $bound', icon: Icons.link),
            MenuItem(
              'Unbind',
              icon: Icons.link_off,
              onSelected: () => editor.unbind(node, prop),
            ),
          ] else ...[
            MenuItem(
              'Make a parameter',
              icon: Icons.add,
              shortcut: editor.freeParamName(prop),
              onSelected: () => editor.promote(node, prop),
            ),
            if (candidates.isNotEmpty) ...[
              const MenuDivider(),
              const MenuHeader('Bind to'),
              for (var p in candidates)
                MenuItem(
                  p.name,
                  icon: Icons.link,
                  onSelected: () => editor.bind(node, prop, p.name),
                ),
            ],
            // The package's shared values, of this property's kind. The
            // value rides along as the shortcut, so a colour can be picked
            // by what it is and not only by what it is called.
            if (tokens.isNotEmpty) ...[
              const MenuDivider(),
              const MenuHeader('Tokens'),
              for (var t in tokens)
                MenuItem(
                  t.name,
                  icon: Icons.style_outlined,
                  shortcut: _tokenValue(t),
                  onSelected: () => editor.bindToken(node, prop, t.name),
                ),
            ],
            // The app's own values of this kind: a name to pick, and the
            // canvas to see the result on — the editor holds no value.
            if (exports.isNotEmpty) ...[
              const MenuDivider(),
              const MenuHeader('From the app'),
              for (var t in exports)
                MenuItem(
                  t.name,
                  icon: Icons.ios_share_outlined,
                  shortcut: t.type,
                  onSelected: () => editor.bindToken(node, prop, t.name),
                ),
            ],
          ],
        ]);
      },
      child: child,
    );
  }

  /// A token's value, short enough for a menu's right edge.
  static String _tokenValue(SceneTokenDecl t) => switch (t.value) {
    SceneColor c =>
      '#${c.argb.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}',
    double d => d == d.roundToDouble() ? '${d.round()}' : '$d',
    String s => s.length > 16 ? "'${s.substring(0, 15)}…'" : "'$s'",
    var v => '$v',
  };

  /// A size, in the three states one can be in: a number, hug, or fill.
  ///
  /// The mode is a word you tap rather than a picker, because the three
  /// live in a 96 pixel column beside a number, and the word is also the
  /// answer to "what is this doing" — which a dropdown showing the same
  /// word would only repeat.
  Widget _size(
    String label,
    SceneNode node,
    double? value, {
    required bool horizontal,
    required void Function(double?) onChanged,
  }) {
    var mode = value == null
        ? _SizeMode.hug
        : value.isInfinite
        ? _SizeMode.fill
        : _SizeMode.fixed;
    var warning = _sizeWarning(node, mode, horizontal: horizontal);
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: context.type.caption.copyWith(
                  color: context.colors.mut2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTapDown: (d) => showContextMenu(context, d.globalPosition, [
                  for (var option in _SizeMode.values)
                    MenuItem(
                      option.label,
                      icon: option == mode ? Icons.check : null,
                      onSelected: () => _door(
                        label,
                        () => onChanged(switch (option) {
                          _SizeMode.hug => null,
                          _SizeMode.fill => double.infinity,
                          // Back from hug or fill to a number: the measured
                          // size, so the box does not jump when you pin it.
                          _SizeMode.fixed => _measuredOf(
                            node,
                            horizontal: horizontal,
                          ),
                        }),
                      ),
                    ),
                ]),
                child: Text(
                  mode.label,
                  style: context.type.caption.copyWith(
                    color: warning == null
                        ? context.colors.accent
                        : context.colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FwSpacing.xs),
          if (mode == _SizeMode.fixed)
            SceneScrubNumber(
              value: value!,
              shape: SceneNumberShape.pixels,
              onChanged: (v) => _door(label, () => onChanged(v)),
              onCommit: (v) {
                _door(label, () => onChanged(v));
                editor.endMerge();
              },
            )
          else
            Container(
              height: 27,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.line),
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              ),
              child: Text(
                mode.label,
                style: context.type.caption.copyWith(
                  color: context.colors.mut2,
                ),
              ),
            ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: FwSpacing.xs),
              child: Text(
                warning,
                style: context.type.micro.copyWith(color: context.colors.red),
              ),
            ),
        ],
      ),
    );
  }

  /// What the node is actually that big, so pinning a hugging box to a
  /// number starts from what is on screen.
  double _measuredOf(SceneNode node, {required bool horizontal}) {
    var rect = node.measured;
    if (rect == null) return 100;
    return _half(horizontal ? rect.width : rect.height);
  }

  /// The two ways a size can be a contradiction, in the author's words.
  ///
  /// Neither is a renderer bug: the renderer does the honest thing and this
  /// is where it gets said, because an author who cannot see why a fill did
  /// nothing will go looking in the wrong place.
  String? _sizeWarning(
    SceneNode node,
    _SizeMode mode, {
    required bool horizontal,
  }) {
    var parent = doc.parentOf(node);
    // Two nodes sit inside a table and neither owns its own width: a row is
    // placed entirely by the table, and a cell is as wide as its column. A
    // size set here is not honoured, and looking ignored is worse than
    // being refused in words.
    if (parent != null && parent.layout == NodeLayout.table) {
      return mode == _SizeMode.hug ? null : '${parent.name} lays this out';
    }
    var table = parent == null ? null : doc.parentOf(parent);
    if (table != null &&
        table.layout == NodeLayout.table &&
        horizontal &&
        mode != _SizeMode.hug) {
      var index = parent!.children.indexOf(node);
      return 'column ${index + 1} of ${table.name} decides this';
    }
    if (mode == _SizeMode.fill) {
      if (parent == null || parent.layout == NodeLayout.absolute) {
        return horizontal
            ? null
            : null; // free parents give a box; fill is legal there
      }
      var alongParentsMain = (parent.layout == NodeLayout.row) == horizontal;
      if (!alongParentsMain) return null;
      var parentSize = horizontal ? parent.width : parent.height;
      if (parentSize == null) {
        return 'nothing to fill: ${parent.name} hugs this axis';
      }
      return null;
    }
    if (mode == _SizeMode.hug &&
        node is FrameNode &&
        node.layout == NodeLayout.absolute &&
        node.children.isNotEmpty) {
      return 'a free frame takes the room it is given';
    }
    return null;
  }

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: FwSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(width: FwSpacing.md),
          Expanded(child: child),
        ],
      ],
    ),
  );

  /// What this node reads rather than holds: one line per bound property,
  /// and the way out. Editing a bound field edits the parameter's default,
  /// so this is where a reader learns why a sibling moved too — and unbind
  /// is the only way to keep a value of one's own, which is why it is here
  /// and not a side effect of typing.
  List<Widget> _bindings(BuildContext context, SceneNode node) => [
    _label(context, 'Bound'),
    for (var e in node.bindings.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: FwSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Tappable(
                // A step to the parameter: it opens below, where its
                // mockup and its other readers are.
                onTap: switch (e.value) {
                  ParamRef(:var name) when onOpenParam != null =>
                    () => onOpenParam!(name),
                  _ => null,
                },
                feedback: TapFeedback.none,
                child: Text(
                  '${_propLabel(e.key)} ← ${e.value}',
                  style: context.type.mono,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Tappable(
              onTap: () => editor.perform(
                'Unbind ${e.key}',
                () => node.bindings.remove(e.key),
              ),
              child: Text(
                'unbind',
                style: context.type.caption.copyWith(
                  color: context.colors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    const SizedBox(height: FwSpacing.md),
  ];

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: FwSpacing.xs),
    child: Text(
      text,
      style: context.type.caption.copyWith(color: context.colors.mut2),
    ),
  );

  List<Widget> _textProps(BuildContext context, TextNode t) => [
    ..._styleRow(context, t),
    _label(context, 'Content'),
    _bindable(
      context,
      t,
      'text',
      TextFormField(
        // Keyed on the binding too: binding rewrites the text from outside
        // this field, and a field keeps its own buffer otherwise.
        key: ValueKey('text:${t.name}:${t.bindings['text']}'),
        initialValue: t.text,
        maxLines: 3,
        minLines: 1,
        onChanged: (v) => _door('text', () => t.text = v),
      ),
    ),
    const SizedBox(height: FwSpacing.md),
    _label(context, 'Typeface'),
    _bindable(
      context,
      t,
      'fontFamily',
      TextFormField(
        key: ValueKey('family:${t.name}:${t.bindings['fontFamily']}'),
        initialValue: t.fontFamily ?? '',
        decoration: const InputDecoration(hintText: "the app's own"),
        onChanged: (v) => _door(
          'fontFamily',
          () => t.fontFamily = v.trim().isEmpty ? null : v.trim(),
        ),
      ),
    ),
    const SizedBox(height: FwSpacing.md),
    _row([
      _number(
        'fontSize',
        'Size',
        _shown(t, 'fontSize', t.fontSize),
        SceneNumberShape.of(propSpecFor(t, 'fontSize')),
        apply: (v) => t.fontSize = v,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'Weight'),
          FwPicker<SceneFontWeight>(
            selected: t.weight,
            choices: const [
              FwChoice(value: SceneFontWeight.w400, label: 'Regular'),
              FwChoice(value: SceneFontWeight.w500, label: 'Medium'),
              FwChoice(value: SceneFontWeight.w600, label: 'Semibold'),
              FwChoice(value: SceneFontWeight.w700, label: 'Bold'),
              FwChoice(value: SceneFontWeight.w900, label: 'Black'),
            ],
            onChanged: (v) => _door('weight', () => t.weight = v),
          ),
        ],
      ),
    ]),
    // Tracking and leading, together: they are read together and a display
    // size wants both moved at once.
    _row([
      _number(
        'letterSpacing',
        'Tracking',
        _shown(t, 'letterSpacing', t.letterSpacing),
        SceneNumberShape.of(propSpecFor(t, 'letterSpacing')),
        apply: (v) => t.letterSpacing = v,
      ),
      _number(
        'lineHeight',
        'Leading',
        _shown(t, 'lineHeight', t.lineHeight),
        SceneNumberShape.of(propSpecFor(t, 'lineHeight')),
        apply: (v) => t.lineHeight = v,
      ),
    ]),
    _row([
      Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, 'Align'),
            FwPicker<SceneTextAlign>(
              selected: t.align,
              choices: const [
                FwChoice(value: SceneTextAlign.left, label: 'Left'),
                FwChoice(value: SceneTextAlign.center, label: 'Center'),
                FwChoice(value: SceneTextAlign.right, label: 'Right'),
                FwChoice(value: SceneTextAlign.justify, label: 'Justify'),
              ],
              onChanged: (v) => _door('align', () => t.align = v),
            ),
          ],
        ),
      ),
      Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, 'Case'),
            FwPicker<SceneTextCase>(
              selected: t.textCase,
              choices: const [
                FwChoice(value: SceneTextCase.none, label: 'As typed'),
                FwChoice(value: SceneTextCase.upper, label: 'UPPER'),
                FwChoice(value: SceneTextCase.lower, label: 'lower'),
                FwChoice(value: SceneTextCase.title, label: 'Title'),
              ],
              onChanged: (v) => _door('textCase', () => t.textCase = v),
            ),
          ],
        ),
      ),
    ]),
    _label(context, 'Color'),
    _bindable(
      context,
      t,
      'color',
      SceneSwatches(
        current: _shown(t, 'color', t.color),
        allowNone: false,
        onPick: (c) => _set('color', c!, () => t.color = c),
      ),
    ),
    const SizedBox(height: FwSpacing.md),
    // The rest is real and rarely touched, which is the whole argument for
    // putting it behind one tap rather than at the bottom of a column
    // nobody scrolls.
    Disclosure(
      label: 'More type',
      children: [
        _row([
          Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(context, 'Style'),
                FwPicker<bool>(
                  selected: t.italic,
                  choices: const [
                    FwChoice(value: false, label: 'Roman'),
                    FwChoice(value: true, label: 'Italic'),
                  ],
                  onChanged: (v) => _door('italic', () => t.italic = v),
                ),
              ],
            ),
          ),
          _number(
            'wordSpacing',
            'Word spacing',
            _shown(t, 'wordSpacing', t.wordSpacing),
            SceneNumberShape.of(propSpecFor(t, 'wordSpacing')),
            apply: (v) => t.wordSpacing = v,
          ),
        ]),
        _row([
          Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(context, 'Decoration'),
                FwPicker<SceneTextDecoration>(
                  selected: t.decoration,
                  choices: const [
                    FwChoice(value: SceneTextDecoration.none, label: 'None'),
                    FwChoice(
                      value: SceneTextDecoration.underline,
                      label: 'Underline',
                    ),
                    FwChoice(
                      value: SceneTextDecoration.overline,
                      label: 'Overline',
                    ),
                    FwChoice(
                      value: SceneTextDecoration.lineThrough,
                      label: 'Strikethrough',
                    ),
                  ],
                  onChanged: (v) => _door('decoration', () => t.decoration = v),
                ),
              ],
            ),
          ),
          _number(
            'maxLines',
            'Max lines (0 = all)',
            (t.maxLines ?? 0).toDouble(),
            const SceneNumberShape(
              perPixel: 0.1,
              decimals: 0,
              min: 0,
              softMax: 10,
            ),
            apply: (v) => t.maxLines = v < 1 ? null : v.round(),
          ),
        ]),
        if (t.decoration != SceneTextDecoration.none) ...[
          _row([
            Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(context, 'Line style'),
                  FwPicker<SceneTextDecorationStyle>(
                    selected: t.decorationStyle,
                    choices: const [
                      FwChoice(
                        value: SceneTextDecorationStyle.solid,
                        label: 'Solid',
                      ),
                      FwChoice(
                        value: SceneTextDecorationStyle.double,
                        label: 'Double',
                      ),
                      FwChoice(
                        value: SceneTextDecorationStyle.dotted,
                        label: 'Dotted',
                      ),
                      FwChoice(
                        value: SceneTextDecorationStyle.dashed,
                        label: 'Dashed',
                      ),
                      FwChoice(
                        value: SceneTextDecorationStyle.wavy,
                        label: 'Wavy',
                      ),
                    ],
                    onChanged: (v) =>
                        _door('decorationStyle', () => t.decorationStyle = v),
                  ),
                ],
              ),
            ),
            _number(
              'decorationThickness',
              'Line thickness',
              _shown(t, 'decorationThickness', t.decorationThickness),
              SceneNumberShape.of(propSpecFor(t, 'decorationThickness')),
              apply: (v) => t.decorationThickness = v,
            ),
          ]),
          _label(context, 'Line color'),
          _bindable(
            context,
            t,
            'decorationColor',
            SceneSwatches(
              current: t.decorationColor,
              onPick: (c) =>
                  _door('decorationColor', () => t.decorationColor = c),
            ),
          ),
        ],
      ],
    ),
  ];

  /// The shared text style, when the package declares any: a picker over
  /// them, and — once one is applied — one word per property it sets,
  /// saying whether the node inherits it or overrides it, with the way back.
  /// Equal is inherited, by decision: there is no flag to show.
  List<Widget> _styleRow(BuildContext context, TextNode t) {
    var styles = [
      for (var s in doc.tokens)
        if (s.isStyle) s,
    ];
    if (styles.isEmpty) return const [];
    var bound = switch (t.bindings[styleBindingKey]) {
      StyleRef(:var name) => name,
      _ => null,
    };
    var style = styleOf(doc, t);
    var boundDecl = bound == null ? null : doc.tokenNamed(bound);
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    return [
      _label(context, 'Style'),
      FwPicker<String?>(
        selected: bound,
        choices: [
          const FwChoice(value: null, label: 'none', detail: 'its own values'),
          for (var s in styles)
            FwChoice(
              value: s.name,
              label: 'tokens.${s.name}',
              detail: s.style == null
                  ? 'from the app'
                  : s.style!.values.keys.map(_propLabel).join(' · '),
            ),
        ],
        onChanged: (name) =>
            name == null ? editor.detachStyle(t) : editor.applyStyle(t, name),
      ),
      // An export's style: the app's own, laid under the values here by
      // the canvas. Nothing to inherit or reset — what is set here is set.
      if (boundDecl?.isExport == true)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Text(
            "the app's ${boundDecl!.type}, under the values here",
            style: caption,
          ),
        ),
      if (style != null)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Wrap(
            spacing: FwSpacing.md,
            runSpacing: FwSpacing.xxs,
            children: [
              for (var prop in style.values.keys)
                if (inheritsFromStyle(doc, t, prop))
                  Text('${_propLabel(prop)} ← $bound', style: caption)
                else
                  Tappable(
                    onTap: () => editor.resetToStyle(t, prop),
                    child: Text(
                      '${_propLabel(prop)} overridden · reset',
                      style: caption.copyWith(color: colors.accent),
                    ),
                  ),
            ],
          ),
        ),
      const SizedBox(height: FwSpacing.md),
    ];
  }

  List<Widget> _frameProps(BuildContext context, FrameNode f) => [
    Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.md),
      child: _check(
        context,
        'Clip children at the edge',
        f.clip,
        () => _door('clip', () => f.clip = !f.clip),
      ),
    ),
    _label(context, 'Layout'),
    FwPicker<NodeLayout>(
      selected: f.layout,
      choices: const [
        FwChoice(value: NodeLayout.absolute, label: 'Free'),
        FwChoice(value: NodeLayout.row, label: 'Row'),
        FwChoice(value: NodeLayout.column, label: 'Column'),
        FwChoice(
          value: NodeLayout.table,
          label: 'Table',
          detail: 'children are rows, their children are cells',
        ),
      ],
      // A layout switch is a geometry transaction, not a flag flip: entering
      // Free bakes each child's measured position into authored x/y; entering
      // a flex re-derives order from visual position.
      onChanged: (next) => _door('layout', () {
        var origin = f.measured;
        if (next == NodeLayout.absolute) {
          for (var c in f.children) {
            var rect = c.measured;
            if (rect != null) {
              // A measured position carries the layout's float noise;
              // what gets authored is a half-pixel, not 32.180908203125.
              c.x = _half(rect.left - (origin?.left ?? 0));
              c.y = _half(rect.top - (origin?.top ?? 0));
            }
          }
        } else {
          f.children.sort((a, b) {
            var ra = a.measured, rb = b.measured;
            if (ra == null || rb == null) return 0;
            return next == NodeLayout.row
                ? ra.left.compareTo(rb.left)
                : ra.top.compareTo(rb.top);
          });
        }
        f.layout = next;
      }),
    ),
    const SizedBox(height: FwSpacing.md),
    if (f.layout == NodeLayout.table) ...[
      ..._tableProps(context, f),
    ] else
      _row([
        _number(
          'gap',
          'Gap',
          _shown(f, 'gap', f.gap),
          SceneNumberShape.of(propSpecFor(f, 'gap')),
          apply: (v) => f.gap = v,
        ),
      ]),
    _label(context, 'Padding'),
    _row([
      _number(
        'padding',
        'Left',
        f.padding.left,
        SceneNumberShape.pixels,
        apply: (v) => f.padding = f.padding.copyWith(left: v),
      ),
      _number(
        'padding',
        'Top',
        f.padding.top,
        SceneNumberShape.pixels,
        apply: (v) => f.padding = f.padding.copyWith(top: v),
      ),
    ]),
    _row([
      _number(
        'padding',
        'Right',
        f.padding.right,
        SceneNumberShape.pixels,
        apply: (v) => f.padding = f.padding.copyWith(right: v),
      ),
      _number(
        'padding',
        'Bottom',
        f.padding.bottom,
        SceneNumberShape.pixels,
        apply: (v) => f.padding = f.padding.copyWith(bottom: v),
      ),
    ]),
    if (f.layout == NodeLayout.table) ...[
      _label(context, 'Cells sit'),
      FwPicker<SceneCrossAxisAlignment>(
        selected: f.crossAlign,
        choices: const [
          FwChoice(value: SceneCrossAxisAlignment.start, label: 'Top'),
          FwChoice(value: SceneCrossAxisAlignment.center, label: 'Middle'),
          FwChoice(value: SceneCrossAxisAlignment.end, label: 'Bottom'),
          FwChoice(
            value: SceneCrossAxisAlignment.stretch,
            label: 'Filling the row',
          ),
        ],
        onChanged: (v) => _door('crossAlign', () => f.crossAlign = v),
      ),
    ] else if (f.layout != NodeLayout.absolute) ...[
      // Both axes, always, and each says when it has nothing to do. Cross
      // align alone was read as "align the contents", which is what main
      // align does — and a frame that hugs the axis it is aligning on has
      // no spare room, so every option looks the same and the control
      // looks broken.
      _label(context, 'Main align'),
      _alignNote(context, f, main: true),
      FwPicker<SceneMainAxisAlignment>(
        selected: f.mainAlign,
        choices: const [
          FwChoice(value: SceneMainAxisAlignment.start, label: 'Start'),
          FwChoice(value: SceneMainAxisAlignment.center, label: 'Center'),
          FwChoice(value: SceneMainAxisAlignment.end, label: 'End'),
          FwChoice(
            value: SceneMainAxisAlignment.spaceBetween,
            label: 'Space between',
          ),
          FwChoice(
            value: SceneMainAxisAlignment.spaceAround,
            label: 'Space around',
          ),
          FwChoice(
            value: SceneMainAxisAlignment.spaceEvenly,
            label: 'Space evenly',
          ),
        ],
        onChanged: (v) => _door('mainAlign', () => f.mainAlign = v),
      ),
      const SizedBox(height: FwSpacing.md),
      _label(context, 'Cross align'),
      _alignNote(context, f, main: false),
      FwPicker<SceneCrossAxisAlignment>(
        selected: f.crossAlign,
        choices: const [
          FwChoice(value: SceneCrossAxisAlignment.start, label: 'Start'),
          FwChoice(value: SceneCrossAxisAlignment.center, label: 'Center'),
          FwChoice(value: SceneCrossAxisAlignment.end, label: 'End'),
          FwChoice(value: SceneCrossAxisAlignment.stretch, label: 'Stretch'),
        ],
        onChanged: (v) => _door('crossAlign', () => f.crossAlign = v),
      ),
    ],
  ];

  /// What a repeat is, when the selected frame is one.
  ///
  /// Read-only, and honestly so: the rule is a closure in the file, and
  /// turning a frame into a repeat means writing one. There is no gesture
  /// here that could — so rather than a control that lies, this says what
  /// the frame is drawn from and how many times.
  List<Widget> _repeat(BuildContext context, SceneNode node) {
    if (node is! FrameNode) return const [];
    var source = node.repeated?.source;
    if (source == null || source.isEmpty) return const [];
    var items = doc.itemsOf(source);
    var fields = items.isEmpty ? '' : items.first.keys.join(' · ');
    return [
      const SizedBox(height: FwSpacing.md),
      _label(context, 'Repeat'),
      Text(
        items.isEmpty
            ? 'once per $source — no items, so nothing is drawn'
            : 'once per $source — ${items.length} rows, this one the first',
        style: context.type.caption,
      ),
      if (fields.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xxs),
          child: Text(
            'each item carries $fields',
            style: context.type.micro.copyWith(color: context.colors.mut2),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: FwSpacing.xs),
        child: Text(
          'The cells are written inline in the file and have no names, so '
          'they are edited there rather than here.',
          style: context.type.micro.copyWith(color: context.colors.mut2),
        ),
      ),
    ];
  }

  /// A table's own controls: the column tracks, and the room inside a cell.
  ///
  /// The tracks are the table — a column that hugs is as wide as the widest
  /// cell in ANY row, which is the thing stacked rows cannot do — so they
  /// come first, before anything about one cell.
  List<Widget> _tableProps(BuildContext context, FrameNode f) {
    var widest = 0;
    for (var row in f.children) {
      if (row.children.length > widest) widest = row.children.length;
    }
    return [
      Row(
        children: [
          Expanded(child: _label(context, 'Columns')),
          Tappable(
            onTap: () =>
                _door('columns', () => f.columns = [...f.columns, null]),
            child: Icon(
              Icons.add,
              size: FwIconSize.md,
              color: context.colors.accent,
            ),
          ),
        ],
      ),
      if (f.columns.length < widest)
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text(
            '$widest cells in the widest row — '
            '${widest - f.columns.length} column'
            '${widest - f.columns.length == 1 ? '' : 's'} '
            'undeclared, and hugging',
            style: context.type.micro.copyWith(color: context.colors.mut2),
          ),
        ),
      for (var i = 0; i < f.columns.length; i++) _column(context, f, i),
      const SizedBox(height: FwSpacing.md),
      _label(context, 'Cell padding'),
      _row([
        _number(
          'cellPadding',
          'Left',
          f.cellPadding.left,
          SceneNumberShape.pixels,
          apply: (v) => f.cellPadding = f.cellPadding.copyWith(left: v),
        ),
        _number(
          'cellPadding',
          'Top',
          f.cellPadding.top,
          SceneNumberShape.pixels,
          apply: (v) => f.cellPadding = f.cellPadding.copyWith(top: v),
        ),
      ]),
      _row([
        _number(
          'cellPadding',
          'Right',
          f.cellPadding.right,
          SceneNumberShape.pixels,
          apply: (v) => f.cellPadding = f.cellPadding.copyWith(right: v),
        ),
        _number(
          'cellPadding',
          'Bottom',
          f.cellPadding.bottom,
          SceneNumberShape.pixels,
          apply: (v) => f.cellPadding = f.cellPadding.copyWith(bottom: v),
        ),
      ]),
    ];
  }

  /// One column track, in the same three words a node's size uses.
  Widget _column(BuildContext context, FrameNode f, int index) {
    var value = f.columns[index];
    var mode = value == null
        ? _SizeMode.hug
        : value.isInfinite
        ? _SizeMode.fill
        : _SizeMode.fixed;
    void set(double? v) =>
        _door('columns', () => f.columns = [...f.columns]..[index] = v);
    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
          ),
          Expanded(
            child: mode == _SizeMode.fixed
                ? SceneScrubNumber(
                    value: value!,
                    shape: SceneNumberShape.pixels,
                    onChanged: set,
                    onCommit: (v) {
                      set(v);
                      editor.endMerge();
                    },
                  )
                : Text(
                    mode == _SizeMode.hug
                        ? 'as wide as its widest cell'
                        : 'what is left',
                    style: context.type.caption.copyWith(
                      color: context.colors.mut2,
                    ),
                  ),
          ),
          const SizedBox(width: FwSpacing.sm),
          GestureDetector(
            onTapDown: (d) => showContextMenu(context, d.globalPosition, [
              for (var option in _SizeMode.values)
                MenuItem(
                  option.label,
                  icon: option == mode ? Icons.check : null,
                  onSelected: () => set(switch (option) {
                    _SizeMode.hug => null,
                    _SizeMode.fill => double.infinity,
                    _SizeMode.fixed => 96,
                  }),
                ),
              MenuItem(
                'Remove',
                onSelected: () => _door(
                  'columns',
                  () => f.columns = [...f.columns]..removeAt(index),
                ),
              ),
            ]),
            child: Text(
              mode.label,
              style: context.type.caption.copyWith(
                color: context.colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Says when an alignment has no room to move anything: the frame hugs
  /// that axis, so every option lands in the same place.
  Widget _alignNote(BuildContext context, FrameNode f, {required bool main}) {
    var horizontal = (f.layout == NodeLayout.row) == main;
    var size = horizontal ? f.width : f.height;
    if (size != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.xs),
      child: Text(
        'no room: ${f.name} hugs its ${horizontal ? 'width' : 'height'}',
        style: context.type.micro.copyWith(color: context.colors.mut2),
      ),
    );
  }

  List<Widget> _shapeProps(BuildContext context, ShapeNode s) => [
    _check(
      context,
      'Circle',
      s.circle,
      () => _door('circle', () => s.circle = !s.circle),
    ),
  ];

  static bool _hasBounds(SceneNode node) =>
      node.minWidth != null ||
      node.maxWidth != null ||
      node.minHeight != null ||
      node.maxHeight != null;

  Widget _boundsWord(BuildContext context, SceneNode node) => Tappable(
    onTap: () =>
        _door('minWidth', () => node.minWidth = node.measured?.width ?? 100),
    child: Text(
      'bounds',
      style: context.type.caption.copyWith(color: context.colors.accent),
    ),
  );

  /// Min and max width and height, behind a word until any is set.
  List<Widget> _bounds(BuildContext context, SceneNode node) {
    if (!_hasBounds(node)) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.md),
          child: _boundsWord(context, node),
        ),
      ];
    }
    Widget bound(
      String prop,
      String label,
      double? value,
      void Function(double?) set,
    ) => _number(
      prop,
      '$label (0 = none)',
      value ?? 0,
      SceneNumberShape.pixels,
      apply: (v) => set(v <= 0 ? null : v),
    );
    return [
      _row([
        bound('minWidth', 'Min W', node.minWidth, (v) => node.minWidth = v),
        bound('maxWidth', 'Max W', node.maxWidth, (v) => node.maxWidth = v),
      ]),
      _row([
        bound('minHeight', 'Min H', node.minHeight, (v) => node.minHeight = v),
        bound('maxHeight', 'Max H', node.maxHeight, (v) => node.maxHeight = v),
      ]),
    ];
  }

  Widget _cornersWord(BuildContext context, SceneNode node) => Tappable(
    onTap: () => _door(
      'corner',
      // Nudged apart so the four fields appear; back together is a number
      // in any one of them matching the rest.
      () => node.corners = node.corners.copyWith(
        bottomRight: node.corners.topLeft + 0.5,
      ),
    ),
    child: Text(
      'corners one by one',
      style: context.type.caption.copyWith(color: context.colors.accent),
    ),
  );

  /// The corners one by one, behind a word: most nodes never open it.
  List<Widget> _corners(BuildContext context, SceneNode node) {
    var c = node.corners;
    if (c.isUniform) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.md),
          child: _cornersWord(context, node),
        ),
      ];
    }
    Widget corner(
      String prop,
      String label,
      double value,
      SceneCorners Function(double) set,
    ) => _number(
      prop,
      label,
      value,
      SceneNumberShape.pixels,
      apply: (v) => node.corners = set(v),
    );
    return [
      _row([
        corner(
          'cornerTopLeft',
          'Top left',
          c.topLeft,
          (v) => c.copyWith(topLeft: v),
        ),
        corner(
          'cornerTopRight',
          'Top right',
          c.topRight,
          (v) => c.copyWith(topRight: v),
        ),
      ]),
      _row([
        corner(
          'cornerBottomLeft',
          'Bottom left',
          c.bottomLeft,
          (v) => c.copyWith(bottomLeft: v),
        ),
        corner(
          'cornerBottomRight',
          'Bottom right',
          c.bottomRight,
          (v) => c.copyWith(bottomRight: v),
        ),
      ]),
    ];
  }

  /// A boolean as a row you tap: the box and its word.
  Widget _check(
    BuildContext context,
    String label,
    bool value,
    VoidCallback onTap,
  ) => Tappable(
    onTap: onTap,
    child: Row(
      children: [
        Icon(
          value ? Icons.check_box : Icons.check_box_outline_blank,
          size: FwIconSize.md,
          color: value ? context.colors.accent : context.colors.mut2,
        ),
        const SizedBox(width: FwSpacing.sm),
        // Flexible: a label is a sentence in one place, and the test font
        // is a box per glyph, so a fixed one overflows there first.
        Flexible(child: Text(label, style: context.type.body)),
      ],
    ),
  );

  /// The widget's declared arguments, each at its override or its default —
  /// the same shape as a nested scene's parameters, because a declaration is
  /// the same promise a scene header makes.
  List<Widget> _extProps(BuildContext context, ExternalNode e) {
    var declared = externals.where((w) => w.entry == e.entry).firstOrNull;
    return [
      _label(context, 'Entry'),
      Text(e.entry, style: context.type.body),
      if (declared == null)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Text(
            'Not declared in this package',
            style: context.type.caption.copyWith(color: context.colors.red),
          ),
        ),
      const SizedBox(height: FwSpacing.md),
      for (var arg in declared?.args ?? const <ExternalArgDecl>[]) ...[
        if (!isValueArgType(arg.typeName))
          _opaqueArg(context, e, arg)
        else if (arg.typeName == 'double')
          _number(
            'args.${arg.name}',
            arg.name,
            switch (e.args[arg.name] ?? _fallback(arg)) {
              num n => n.toDouble(),
              _ => 0,
            },
            const SceneNumberShape(perPixel: 1, decimals: 2),
            apply: (v) => e.args[arg.name] = v,
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: TextFormField(
              key: ValueKey('${e.name}:${arg.name}'),
              initialValue: '${e.args[arg.name] ?? _fallback(arg) ?? ''}',
              decoration: InputDecoration(labelText: arg.name, isDense: true),
              onChanged: (v) => _door('args', () => e.args[arg.name] = v),
            ),
          ),
      ],
    ];
  }

  /// An argument of the app's own type: nothing the editor can show a value
  /// of, so the row is a picker over the opaque tokens of that type — the
  /// only thing a scene can put there — with `none` for the widget's own
  /// fallback.
  Widget _opaqueArg(BuildContext context, ExternalNode e, ExternalArgDecl arg) {
    var prop = 'args.${arg.name}';
    var bound = switch (e.bindings[prop]) {
      TokenRef(:var name) => name,
      _ => null,
    };
    var tokens = [
      for (var t in doc.tokens)
        if (t.isExport && t.type == arg.typeName) t,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, '${arg.name} · ${arg.typeName}'),
          FwPicker<String?>(
            selected: bound,
            choices: [
              const FwChoice(
                value: null,
                label: 'none',
                detail: "the widget's own",
              ),
              for (var t in tokens)
                FwChoice(value: t.name, label: 'tokens.${t.name}'),
            ],
            empty: 'No ${arg.typeName} token declared in scene_tokens.dart',
            onChanged: (name) => name == null
                ? editor.unbind(e, prop)
                : editor.bindToken(e, prop, name),
          ),
        ],
      ),
    );
  }

  /// The declaration's fallback, as a value. It is kept as source text —
  /// what goes back out as the generated field's default — and only the two
  /// spellings a field shows are read back here.
  Object? _fallback(ExternalArgDecl arg) {
    var text = arg.defaultSource;
    if (text == null) return null;
    if (arg.typeName == 'double') return double.tryParse(text);
    return text.length >= 2 && (text.startsWith("'") || text.startsWith('"'))
        ? text.substring(1, text.length - 1)
        : text;
  }

  /// The selected keys: one key edits time, value and curve; several share a
  /// curve and nothing else, because their values are each their own.
  Widget _keys(BuildContext context) {
    var refs = editor.selectedKeys.toList();
    var colors = context.colors;
    var single = refs.length == 1 ? refs.single : null;
    var key = single == null ? null : editor.keyOf(single);
    var group = single == null
        ? null
        : editor.motions[single.motion]?.groupNamed(single.group);
    var node = group == null ? null : doc.nodeNamed(group.node.name);
    var spec = node == null || single == null
        ? null
        : propSpecFor(node, single.prop);
    var shared = {for (var ref in refs) editor.keyOf(ref)?.curve?.name};
    return ListView(
      key: ValueKey('keys:${refs.join(',')}'),
      padding: const EdgeInsets.all(FwSpacing.lg),
      children: [
        Text(
          single == null
              ? '${refs.length} keys'
              : 'Key · ${single.group}.${_propLabel(single.prop)}',
          style: context.type.bodyStrong,
        ),
        if (group != null)
          Padding(
            padding: const EdgeInsets.only(top: FwSpacing.xxs),
            child: Text(
              'on ${group.node.name}',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
          ),
        const SizedBox(height: FwSpacing.lg),
        if (single != null && key != null) ...[
          SceneNumberField(
            label: 'Time',
            value: key.at.inMilliseconds.toDouble(),
            shape: SceneNumberShape.milliseconds,
            onChanged: (v) => editor.setKeyTime(
              single,
              Duration(milliseconds: v.round()),
              mergeKey: 'keytime',
            ),
            onCommit: (v) {
              editor.setKeyTime(single, Duration(milliseconds: v.round()));
              editor.endMerge();
            },
          ),
          const SizedBox(height: FwSpacing.md),
          if (key.value case double number)
            SceneNumberField(
              label: 'Value',
              value: number,
              shape: SceneNumberShape.of(spec),
              onChanged: (v) =>
                  editor.setKeyValue(single, v, mergeKey: 'keyvalue'),
              onCommit: (v) {
                editor.setKeyValue(single, v);
                editor.endMerge();
              },
            )
          else if (key.value case SceneColor color) ...[
            _label(context, 'Value'),
            SceneSwatches(
              current: color,
              allowNone: false,
              onPick: (c) => editor.setKeyValue(single, c!),
            ),
          ],
          const SizedBox(height: FwSpacing.md),
        ],
        _label(context, 'Ease into this key'),
        SceneCurvePicker(
          name: shared.length == 1 ? shared.single : null,
          // The picker speaks names because a menu is a list of words; the
          // model holds the curve itself.
          onPick: (name) => editor.setKeyCurve(
            refs,
            name == null ? null : sceneCurvesByName[name],
          ),
        ),
        if (shared.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: FwSpacing.xs),
            child: Text(
              'Mixed — picking one sets them all',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
          ),
        const SizedBox(height: FwSpacing.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: FwActionButton(
            label: refs.length == 1 ? 'Delete' : 'Delete ${refs.length} keys',
            tooltip: 'Also Backspace, with the timeline focused',
            onPressed: () async => editor.deleteKeys(),
          ),
        ),
      ],
    );
  }

  static double _half(double v) => (v * 2).round() / 2;

  static String _propLabel(String prop) =>
      prop.startsWith('args.') ? prop.substring(5) : prop;

  /// The child's declared parameters, each at its override or its default.
  /// A parameter the child does not declare cannot be set here — the args
  /// map is the child's contract, not a free bag.
  /// An instance of another scene: its arguments, each at one of three
  /// places in the cascade — the child's default, an override written here,
  /// or a parameter of THIS scene it reads. Editing here writes the
  /// override (or the parameter it reads, the M1 rule); the child's own
  /// mockup is edited in its main, one door away.
  List<Widget> _sceneProps(BuildContext context, SceneRefNode r) {
    var inst = r.instance;
    var caption = context.type.caption.copyWith(color: context.colors.mut2);
    Widget state(SceneParamDecl p) {
      var prop = 'args.${p.name}';
      if (r.bindings[prop] case var b?) {
        return Text(
          '← $b',
          style: caption.copyWith(color: context.colors.accentDark),
        );
      }
      if (r.args.containsKey(p.name)) {
        return Tappable(
          onTap: () => _door('args', () => r.args.remove(p.name)),
          child: Tooltip(
            message: 'Back to the default: ${p.defaultValue}',
            child: Text(
              'overridden · reset',
              style: caption.copyWith(color: context.colors.accent),
            ),
          ),
        );
      }
      return Text('default', style: caption);
    }

    Widget head(SceneParamDecl p) => Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(p.name, style: caption)),
          state(p),
        ],
      ),
    );
    Object? value(SceneParamDecl p) => r.args[p.name] ?? p.defaultValue;
    return [
      Row(
        children: [
          Expanded(child: _label(context, 'Instance of ${r.sceneClassName}')),
          if (inst != null && onEnterNested != null)
            Tappable(
              onTap: () => onEnterNested!(r),
              child: Text(
                'go to main ›',
                style: caption.copyWith(color: context.colors.accent),
              ),
            ),
        ],
      ),
      if (inst == null)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Text(
            'No scene file by that name in this package',
            style: context.type.caption.copyWith(color: context.colors.red),
          ),
        )
      else if (inst.params.isEmpty)
        Text('${r.sceneClassName} takes no arguments', style: caption),
      const SizedBox(height: FwSpacing.md),
      for (var p in inst?.params ?? const <SceneParamDecl>[])
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.md),
          child: _bindable(
            context,
            r,
            'args.${p.name}',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                head(p),
                switch (p.kind) {
                  SceneParamKind.number => SceneNumberField(
                    value: (value(p)! as num).toDouble(),
                    shape: const SceneNumberShape(perPixel: 1, decimals: 2),
                    onChanged: (v) =>
                        _set('args.${p.name}', v, () => r.args[p.name] = v),
                    onCommit: (v) {
                      _set('args.${p.name}', v, () => r.args[p.name] = v);
                      editor.endMerge();
                    },
                  ),
                  SceneParamKind.bool => _check(
                    context,
                    value(p)! as bool ? 'on' : 'off',
                    value(p)! as bool,
                    () => _door(
                      'args',
                      () => r.args[p.name] = !(value(p)! as bool),
                    ),
                  ),
                  SceneParamKind.string => TextFormField(
                    key: ValueKey(
                      '${r.name}:${p.name}:${r.bindings['args.${p.name}']}',
                    ),
                    initialValue: '${value(p)}',
                    onChanged: (v) => _door('args', () => r.args[p.name] = v),
                  ),
                  SceneParamKind.color => SceneSwatches(
                    current: value(p) as SceneColor?,
                    allowNone: false,
                    onPick: (c) =>
                        _set('args.${p.name}', c!, () => r.args[p.name] = c),
                  ),
                  // A list is data, not a value with a field: the nested
                  // scene repeats over whatever it declares, and passing a
                  // different one is the caller's job.
                  SceneParamKind.list => Text(
                    '${p.items.length} items, from the scene itself',
                    style: caption,
                  ),
                },
              ],
            ),
          ),
        ),
    ];
  }
}
