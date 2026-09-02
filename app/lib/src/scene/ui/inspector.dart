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

import '../../ui/design/design.dart';
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

  @override
  Widget build(BuildContext context) {
    if (editor.selectedKeys.isNotEmpty) return _keys(context);
    var node = editor.primary ?? doc.root;
    var parent = node == doc.root ? null : doc.parentOf(node);
    var inFlex = parent != null && parent.layout != NodeLayout.absolute;

    return ListView(
      key: ValueKey('inspector:${node.name}'),
      padding: const EdgeInsets.all(FwSpacing.lg),
      children: [
        Text('${node.typeName} · ${node.name}', style: context.type.bodyStrong),
        const SizedBox(height: FwSpacing.lg),
        if (inFlex)
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
          _optionalNumber('W', node.width, onChanged: (v) => node.width = v),
          _optionalNumber('H', node.height, onChanged: (v) => node.height = v),
        ]),
        const SizedBox(height: FwSpacing.md),
        _label(context, 'Fill'),
        _swatches(
          context,
          node.fill,
          (c) => _door('fill', () => node.fill = c),
        ),
        const SizedBox(height: FwSpacing.md),
        _row([
          _number(
            'corner',
            'Corner',
            node.cornerRadius,
            SceneNumberShape.pixels,
            apply: (v) => node.cornerRadius = v,
          ),
          _number(
            'opacity',
            'Opacity',
            node.opacity,
            SceneNumberShape.of(propSpecFor(node, 'opacity')),
            apply: (v) => node.opacity = v.clamp(0, 1),
          ),
        ]),
        const Divider(height: FwSpacing.xxl),
        ...switch (node) {
          TextNode t => _textProps(context, t),
          FrameNode f => _frameProps(context, f),
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
        onChanged: (v) => _door(prop, () => apply(v)),
        onCommit: (v) {
          _door(prop, () => apply(v));
          editor.endMerge();
        },
      ),
    ),
  );

  /// A nullable size: blank means hug, which is a different thing from zero.
  Widget _optionalNumber(
    String label,
    double? value, {
    required void Function(double?) onChanged,
  }) => Builder(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: context.type.caption.copyWith(color: context.colors.mut2),
            ),
            const Spacer(),
            // The link says what tapping does, not what the value is: a width
            // that hugs is offered a number, one that has a number is offered
            // back to hugging.
            Tappable(
              onTap: () =>
                  _door(label, () => onChanged(value == null ? 100 : null)),
              child: Text(
                value == null ? 'set' : 'hug',
                style: context.type.caption.copyWith(
                  color: context.colors.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FwSpacing.xs),
        if (value != null)
          SceneScrubNumber(
            value: value,
            shape: SceneNumberShape.pixels,
            onChanged: (v) => _door(label, () => onChanged(v)),
            onCommit: (v) {
              _door(label, () => onChanged(v));
              editor.endMerge();
            },
          )
        else
          Builder(
            builder: (context) => Container(
              height: 27,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.line),
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              ),
              child: Text(
                'hug',
                style: context.type.caption.copyWith(
                  color: context.colors.mut2,
                ),
              ),
            ),
          ),
      ],
    ),
  );

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
        t.fontSize,
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
    _label(context, 'Color'),
    _swatches(
      context,
      t.color,
      (c) => _door('color', () => t.color = c ?? const SceneColor(0xFF000000)),
    ),
  ];

  List<Widget> _frameProps(BuildContext context, FrameNode f) => [
    _label(context, 'Layout'),
    FwPicker<NodeLayout>(
      selected: f.layout,
      choices: const [
        FwChoice(value: NodeLayout.absolute, label: 'Free'),
        FwChoice(value: NodeLayout.row, label: 'Row'),
        FwChoice(value: NodeLayout.column, label: 'Column'),
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
    _row([
      _number(
        'gap',
        'Gap',
        f.gap,
        SceneNumberShape.of(propSpecFor(f, 'gap')),
        apply: (v) => f.gap = v,
      ),
      _number(
        'padding',
        'Padding',
        f.padding,
        SceneNumberShape.pixels,
        apply: (v) => f.padding = v,
      ),
    ]),
    if (f.layout != NodeLayout.absolute) ...[
      _label(context, 'Cross align'),
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
    var node = group == null ? null : doc.nodeNamed(group.target);
    var spec = node == null || single == null
        ? null
        : propSpecFor(node, single.prop);
    var shared = {for (var ref in refs) editor.keyOf(ref)?.curve};
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
              'on ${group.target}',
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
          onPick: (curve) => editor.setKeyCurve(refs, curve),
        ),
        if (shared.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: FwSpacing.xs),
            child: Text(
              'Mixed — picking one sets them all',
              style: context.type.caption.copyWith(color: colors.mut2),
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
