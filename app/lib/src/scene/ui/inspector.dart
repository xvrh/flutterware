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
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/action_button.dart';
import '../../ui/menu.dart';
import '../../ui/picker.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import 'curve_picker.dart';
import 'number_shape.dart';
import 'number_field.dart';

/// The palette a scene's colours are picked from. A scene's own palette will
/// come from the project (its theme, its tokens); until then this is the
/// spike's, kept so the panel is usable.
const _palette = <SceneColor?>[
  null,
  SceneColor(0xFFFFFFFF),
  SceneColor(0xFF1A1A1A),
  SceneColor(0xFF2B1B12),
  SceneColor(0xFF4A2F1F),
  SceneColor(0xFF6B4226),
  SceneColor(0xFFD8C9BD),
  SceneColor(0xFFE8632B),
  SceneColor(0xFFF2B705),
  SceneColor(0xFF3E7C4F),
  SceneColor(0xFF4A64D0),
];

/// The three states a size can be in, in the order the menu offers them.
enum _SizeMode {
  fixed('fixed'),
  hug('hug'),
  fill('fill');

  const _SizeMode(this.label);
  final String label;
}

class SceneInspector extends StatelessWidget {
  const SceneInspector(this.editor, {super.key});

  final SceneEditor editor;

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
          _size(
            'W',
            node,
            node.width,
            horizontal: true,
            onChanged: (v) => node.width = v,
          ),
          _size(
            'H',
            node,
            node.height,
            horizontal: false,
            onChanged: (v) => node.height = v,
          ),
        ]),
        const SizedBox(height: FwSpacing.md),
        _label(context, 'Fill'),
        _swatches(
          context,
          editor.records(node, 'fill') && node.hasFx('fill')
              ? node.fxRendered('fill') as SceneColor
              : node.fill,
          // No fill is not a colour a key can hold: that one edits the node.
          (c) => c == null
              ? _door('fill', () => node.fill = null)
              : _set('fill', c, () => node.fill = c),
        ),
        const SizedBox(height: FwSpacing.md),
        _label(context, 'Border'),
        _swatches(context, node.borderColor, (c) {
          _door('borderColor', () => node.borderColor = c);
        }),
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
            'Corner',
            node.corner,
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
  }) => Opacity(
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
  );

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

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: FwSpacing.xs),
    child: Text(
      text,
      style: context.type.caption.copyWith(color: context.colors.mut2),
    ),
  );

  List<Widget> _textProps(BuildContext context, TextNode t) => [
    _label(context, 'Content'),
    TextFormField(
      key: ValueKey('text:${t.name}'),
      initialValue: t.text,
      maxLines: 3,
      minLines: 1,
      onChanged: (v) => _door('text', () => t.text = v),
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
      _number(
        'maxLines',
        'Max lines (0 = all)',
        (t.maxLines ?? 0).toDouble(),
        const SceneNumberShape(perPixel: 0.1, decimals: 0, min: 0, softMax: 10),
        apply: (v) => t.maxLines = v < 1 ? null : v.round(),
      ),
    ]),
    _label(context, 'Color'),
    _swatches(context, _shown(t, 'color', t.color), (c) {
      var color = c ?? const SceneColor(0xFF000000);
      _set('color', color, () => t.color = color);
    }),
  ];

  List<Widget> _frameProps(BuildContext context, FrameNode f) => [
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

  /// Drawn once, or once per item of a list parameter.
  ///
  /// A repeat is not a kind of node — any node can be one — so it sits with
  /// the properties every node has rather than in a type's section. The
  /// node stays one node: what multiplies is the picture.
  List<Widget> _repeat(BuildContext context, SceneNode node) {
    var lists = [
      for (var p in doc.params)
        if (p.kind == SceneParamKind.list) p,
    ];
    if (lists.isEmpty && node.repeat == null) return const [];
    var count = node.repeat == null ? 0 : doc.itemsOf(node.repeat!).length;
    return [
      const SizedBox(height: FwSpacing.md),
      _label(context, 'Repeat'),
      FwPicker<String>(
        selected: node.repeat ?? '',
        choices: [
          const FwChoice(value: '', label: 'Drawn once'),
          for (var p in lists)
            FwChoice(
              value: p.name,
              label: 'Once per ${p.name}',
              detail:
                  '${p.items.length} items, '
                  '${p.items.isEmpty ? 'no fields' : p.items.first.keys.join(' · ')}',
            ),
        ],
        onChanged: (v) =>
            _door('repeat', () => node.repeat = v.isEmpty ? null : v),
      ),
      if (node.repeat != null)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Text(
            count == 0
                ? 'no items, so nothing is drawn'
                : 'drawn $count times — this one is the first',
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
    Tappable(
      onTap: () => _door('circle', () => s.circle = !s.circle),
      child: Row(
        children: [
          Icon(
            s.circle ? Icons.check_box : Icons.check_box_outline_blank,
            size: FwIconSize.md,
            color: s.circle ? context.colors.accent : context.colors.mut2,
          ),
          const SizedBox(width: FwSpacing.sm),
          Text('Circle', style: context.type.body),
        ],
      ),
    ),
  ];

  List<Widget> _extProps(BuildContext context, ExternalNode e) => [
    _label(context, 'Entry'),
    Text(e.entry, style: context.type.body),
    const SizedBox(height: FwSpacing.md),
    for (var arg in e.args.entries) ...[
      if (arg.value case num number)
        _number(
          'args.${arg.key}',
          arg.key,
          number.toDouble(),
          const SceneNumberShape(perPixel: 1, decimals: 2),
          apply: (v) => e.args[arg.key] = v,
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.md),
          child: TextFormField(
            key: ValueKey('${e.name}:${arg.key}'),
            initialValue: '${arg.value}',
            decoration: InputDecoration(labelText: arg.key, isDense: true),
            onChanged: (v) => _door('args', () => e.args[arg.key] = v),
          ),
        ),
    ],
  ];

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
            _swatches(
              context,
              color,
              (c) => editor.setKeyValue(single, c ?? const SceneColor(0)),
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
  List<Widget> _sceneProps(BuildContext context, SceneRefNode r) {
    var inst = r.instance;
    return [
      _label(context, 'Scene'),
      Text(r.sceneClassName, style: context.type.body),
      if (inst == null)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Text(
            'No scene file by that name in this package',
            style: context.type.caption.copyWith(color: context.colors.red),
          ),
        ),
      const SizedBox(height: FwSpacing.md),
      for (var p in inst?.params ?? const <SceneParamDecl>[]) ...[
        switch (p.kind) {
          SceneParamKind.number => _number(
            'args.${p.name}',
            p.name,
            ((r.args[p.name] ?? p.defaultValue) as num).toDouble(),
            const SceneNumberShape(perPixel: 1, decimals: 2),
            apply: (v) => r.args[p.name] = v,
          ),
          SceneParamKind.string => Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: TextFormField(
              key: ValueKey('${r.name}:${p.name}'),
              initialValue: '${r.args[p.name] ?? p.defaultValue}',
              decoration: InputDecoration(labelText: p.name, isDense: true),
              onChanged: (v) => _door('args', () => r.args[p.name] = v),
            ),
          ),
          SceneParamKind.color => Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: FwSpacing.sm,
              children: [
                _label(context, p.name),
                _swatches(
                  context,
                  (r.args[p.name] ?? p.defaultValue) as SceneColor?,
                  (c) => _door('args', () => r.args[p.name] = c),
                ),
              ],
            ),
          ),
          // A list is data, not a value with a field: the nested scene
          // repeats over whatever it declares, and passing a different one
          // is the caller's job until there is an editor for it.
          SceneParamKind.list => Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.md),
            child: Text(
              '${p.name} — ${p.items.length} items, from the scene itself',
              style: context.type.caption.copyWith(color: context.colors.mut),
            ),
          ),
        },
      ],
    ];
  }

  Widget _swatches(
    BuildContext context,
    SceneColor? current,
    void Function(SceneColor?) onPick,
  ) => Wrap(
    spacing: FwSpacing.sm,
    runSpacing: FwSpacing.sm,
    children: [
      for (var color in _palette)
        Tappable(
          onTap: () => onPick(color),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color?.flutter,
              shape: BoxShape.circle,
              border: Border.all(
                color: current == color
                    ? context.colors.accent
                    : context.colors.line,
                width: current == color ? 2 : 1,
              ),
            ),
            child: color == null
                ? Icon(
                    Icons.block,
                    size: FwIconSize.sm,
                    color: context.colors.mut2,
                  )
                : null,
          ),
        ),
    ],
  );
}
