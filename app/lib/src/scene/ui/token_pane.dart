import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/action_button.dart';
import '../../ui/design/design.dart';
import '../../ui/picker.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../tokens_library.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';
import 'tokens_host.dart';

/// One token, open in the drawer under the canvas — the place a parameter
/// opens too, because both are values you edit while looking at the
/// nodes reading them above.
///
/// A library token shows its value in the kind's own control, one column
/// per mode the library names (the default first); every reader in every
/// open scene follows an edit. A style shows its fields, each unset-able.
/// An export shows what it is and where it comes from — the app's, so
/// nothing here to edit. Then who reads it: in this scene, each a step to
/// the node, and elsewhere in the group.
class SceneTokenPane extends StatelessWidget {
  const SceneTokenPane(this.editor, this.name, {super.key, this.host});

  final SceneEditor editor;
  final String name;
  final SceneTokensHost? host;

  @override
  Widget build(BuildContext context) {
    var decl = editor.doc.tokenNamed(name);
    if (decl == null) return const SizedBox.shrink();
    var library = host?.libraryOf(name);
    var readers = editor.readersOfToken(name);
    var elsewhere = host?.readersElsewhere?.call(name) ?? const [];
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    return Container(
      key: ValueKey('pane:token:$name'),
      color: colors.panel,
      padding: const EdgeInsets.all(FwSpacing.lg),
      alignment: Alignment.topLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: FwSpacing.xxl,
        children: [
          SizedBox(
            width: 360,
            child: decl.isExport
                ? _export(context, decl, caption)
                : library == null
                ? Text(
                    'Declared in a library this workspace did not open.',
                    style: caption,
                  )
                : decl.isStyle
                ? _style(context, library, decl, caption)
                : _values(context, library, decl, caption),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: FwSpacing.xs),
                  child: Text(
                    readers.isEmpty ? 'Read by nothing here' : 'Read by',
                    style: caption,
                  ),
                ),
                if (readers.isEmpty)
                  Text(
                    'Right-click a property of a node to bind it here.',
                    style: context.type.micro.copyWith(color: colors.mut2),
                  ),
                Wrap(
                  spacing: FwSpacing.md,
                  runSpacing: FwSpacing.xxs,
                  children: [
                    for (var (node, prop) in readers)
                      Tappable(
                        onTap: () => editor.select(node),
                        borderRadius: BorderRadius.circular(
                          context.radii.radiusSmall,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FwSpacing.xs,
                            vertical: FwSpacing.xxs,
                          ),
                          child: Text(
                            '${node.name} · $prop',
                            style: context.type.mono.copyWith(
                              color: colors.accentDark,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (elsewhere.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: FwSpacing.md,
                      bottom: FwSpacing.xs,
                    ),
                    child: Text('Elsewhere in the group', style: caption),
                  ),
                  Wrap(
                    spacing: FwSpacing.md,
                    runSpacing: FwSpacing.xxs,
                    children: [
                      for (var r in elsewhere)
                        Text(
                          r,
                          style: context.type.mono.copyWith(color: colors.mut),
                        ),
                    ],
                  ),
                ],
                if (decl.hasValue && !decl.isStyle)
                  Padding(
                    padding: const EdgeInsets.only(top: FwSpacing.lg),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FwActionButton(
                        label: 'Make local',
                        tooltip:
                            'A parameter of this scene, with this value — '
                            'the token stays for the other scenes',
                        onPressed: () async => editor.localizeToken(name),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _export(BuildContext context, SceneTokenDecl decl, TextStyle caption) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('From the app', style: caption),
        const SizedBox(height: FwSpacing.xs),
        Text(
          'A ${decl.type} the app exports — its own value, drawn by the '
          'canvas. Nothing to edit here: change it in the app.',
          style: context.type.body,
        ),
      ],
    );
  }

  /// The value, one column per mode: the default, then each mode the
  /// library names. A mode column left equal to the default is the
  /// default.
  Widget _values(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    TextStyle caption,
  ) {
    var modes = library.modes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: FwSpacing.md,
      children: [
        _column(context, 'Default', decl, null, library, caption),
        for (var mode in modes)
          _column(context, mode, decl, mode, library, caption),
      ],
    );
  }

  Widget _column(
    BuildContext context,
    String label,
    SceneTokenDecl decl,
    String? mode,
    TokensLibrary library,
    TextStyle caption,
  ) {
    var value = decl.valueIn(mode)!;
    var own = mode == null || decl.modes.containsKey(mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text(own ? label : '$label · same as default', style: caption),
        ),
        _control(context, decl, value, (v, {String? mergeKey}) {
          library.setValue(decl.name, v, mode: mode, mergeKey: mergeKey);
        }, endMerge: library.endMerge),
      ],
    );
  }

  Widget _control(
    BuildContext context,
    SceneTokenDecl decl,
    Object value,
    void Function(Object value, {String? mergeKey}) set, {
    required VoidCallback endMerge,
  }) {
    var key = 'token:${decl.name}';
    switch (decl.kind!) {
      case SceneParamKind.number:
        return SceneNumberField(
          value: value as double,
          shape: const SceneNumberShape(perPixel: 1, decimals: 2),
          onChanged: (v) => set(v, mergeKey: key),
          onCommit: (v) {
            set(v, mergeKey: key);
            endMerge();
          },
        );
      case SceneParamKind.string:
        return TextFormField(
          key: ValueKey('$key:${value.hashCode}'),
          initialValue: value as String,
          maxLines: 3,
          minLines: 1,
          onChanged: (v) => set(v, mergeKey: key),
        );
      case SceneParamKind.color:
        return SceneSwatches(
          current: value as SceneColor,
          allowNone: false,
          onPick: (c) => set(c!),
        );
      case SceneParamKind.bool:
        var on = value as bool;
        return Tappable(
          onTap: () => set(!on),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.check_box : Icons.check_box_outline_blank,
                size: FwIconSize.md,
                color: on ? context.colors.accent : context.colors.mut2,
              ),
              const SizedBox(width: FwSpacing.sm),
              Text(on ? 'on' : 'off', style: context.type.body),
            ],
          ),
        );
      case SceneParamKind.list:
        return const SizedBox.shrink();
    }
  }

  /// A style's fields: size, weight, colour, align, max lines — each
  /// unset-able, because a style sets only what it sets.
  Widget _style(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    TextStyle caption,
  ) {
    var style = decl.style!;
    var key = 'style:${decl.name}';
    void put(SceneTextStyle next, {String? mergeKey}) =>
        library.setStyle(decl.name, next, mergeKey: mergeKey);
    Widget field(String label, Widget control, {VoidCallback? unset}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Row(
            children: [
              Text(label, style: caption),
              const Spacer(),
              if (unset != null)
                Tappable(
                  onTap: unset,
                  child: Text(
                    'unset',
                    style: caption.copyWith(color: context.colors.accent),
                  ),
                ),
            ],
          ),
        ),
        control,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: FwSpacing.md,
      children: [
        Text(
          'A text style: what it sets, a text takes whole and may override '
          'property by property.',
          style: context.type.micro.copyWith(color: context.colors.mut2),
        ),
        field(
          style.fontSize == null ? 'Size · unset' : 'Size',
          SceneNumberField(
            value: style.fontSize ?? 16,
            shape: const SceneNumberShape(perPixel: 1, decimals: 2),
            onChanged: (v) => put(_with(style, fontSize: v), mergeKey: key),
            onCommit: (v) {
              put(_with(style, fontSize: v), mergeKey: key);
              library.endMerge();
            },
          ),
          unset: style.fontSize == null
              ? null
              : () => put(_with(style, clearFontSize: true)),
        ),
        field(
          'Weight',
          FwPicker<SceneFontWeight?>(
            selected: style.weight,
            choices: const [
              FwChoice(value: null, label: 'unset'),
              FwChoice(value: SceneFontWeight.w400, label: 'Regular'),
              FwChoice(value: SceneFontWeight.w500, label: 'Medium'),
              FwChoice(value: SceneFontWeight.w600, label: 'Semibold'),
              FwChoice(value: SceneFontWeight.w700, label: 'Bold'),
              FwChoice(value: SceneFontWeight.w900, label: 'Black'),
            ],
            onChanged: (w) =>
                put(_with(style, weight: w, clearWeight: w == null)),
          ),
        ),
        field(
          style.color == null ? 'Colour · unset' : 'Colour',
          SceneSwatches(
            current: style.color,
            onPick: (c) => put(_with(style, color: c, clearColor: c == null)),
          ),
        ),
        field(
          'Align',
          FwPicker<SceneTextAlign?>(
            selected: style.align,
            choices: const [
              FwChoice(value: null, label: 'unset'),
              FwChoice(value: SceneTextAlign.left, label: 'Left'),
              FwChoice(value: SceneTextAlign.center, label: 'Center'),
              FwChoice(value: SceneTextAlign.right, label: 'Right'),
              FwChoice(value: SceneTextAlign.justify, label: 'Justify'),
            ],
            onChanged: (a) =>
                put(_with(style, align: a, clearAlign: a == null)),
          ),
        ),
      ],
    );
  }

  static SceneTextStyle _with(
    SceneTextStyle s, {
    double? fontSize,
    bool clearFontSize = false,
    SceneFontWeight? weight,
    bool clearWeight = false,
    SceneColor? color,
    bool clearColor = false,
    SceneTextAlign? align,
    bool clearAlign = false,
  }) => SceneTextStyle(
    fontSize: clearFontSize ? null : fontSize ?? s.fontSize,
    weight: clearWeight ? null : weight ?? s.weight,
    color: clearColor ? null : color ?? s.color,
    align: clearAlign ? null : align ?? s.align,
    maxLines: s.maxLines,
  );
}
