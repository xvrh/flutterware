import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/action_button.dart';
import '../../ui/design/design.dart';
import '../../ui/picker.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../tokens_library.dart';
import 'drawer_pane.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';
import 'tokens_host.dart';

/// One token, open in the drawer under the canvas — the place a parameter
/// opens too, because both are values you edit while looking at the
/// nodes reading them above.
///
/// A library token is one column per mode — the default first, then each
/// mode the library names — with the value in the kind's own control, or
/// a style's fields; a mode column left equal to the default says so, and
/// an edit there makes it the mode's own. Every reader in every open scene
/// follows an edit. An export is one column saying what it is — the
/// app's, so nothing to edit. Last, who reads it.
class SceneTokenPane extends StatelessWidget {
  const SceneTokenPane(this.editor, this.name, {super.key, this.host});

  final SceneEditor editor;
  final String name;
  final SceneTokensHost? host;

  @override
  Widget build(BuildContext context) {
    var library = host?.libraryOf(name);
    if (library == null) return _body(context, null);
    // The library's own edits — from this pane, or another scene's —
    // redraw it; the readers follow through the document.
    return AnimatedBuilder(
      animation: library.listenable,
      builder: (context, _) => _body(context, library),
    );
  }

  Widget _body(BuildContext context, TokensLibrary? library) {
    // Read here, not in build: the library's edit reached the document
    // before this rebuild.
    var decl = editor.doc.tokenNamed(name);
    if (decl == null) return const SizedBox.shrink();
    var readers = editor.readersOfToken(name);
    var elsewhere = host?.readersElsewhere?.call(name) ?? const <String>[];
    var colors = context.colors;
    var micro = context.type.micro.copyWith(color: colors.mut2);
    List<DrawerSection> value;
    if (decl.isExport) {
      value = [
        DrawerSection(
          title: 'From the app',
          width: 320,
          child: Text(
            'A ${decl.type} the app exports — its own value, drawn by the '
            'canvas. Nothing to edit here: change it in the app.',
            style: context.type.body,
          ),
        ),
      ];
    } else if (library == null) {
      value = [
        DrawerSection(
          title: 'Library',
          width: 320,
          child: Text(
            'Declared in a library this workspace did not open.',
            style: micro,
          ),
        ),
      ];
    } else {
      value = [
        for (var mode in [null, ...library.modes])
          decl.isStyle
              ? _styleSection(context, library, decl, mode)
              : _valueSection(context, library, decl, mode),
      ];
    }
    return DrawerPane(
      key: ValueKey('pane:token:$name'),
      sections: [
        ...value,
        readersSection(
          context,
          editor,
          readers,
          elsewhere: elsewhere,
          action: decl.hasValue && !decl.isStyle
              ? FwActionButton(
                  label: 'Make local',
                  tooltip:
                      'A parameter of this scene, with this value — '
                      'the token stays for the other scenes',
                  onPressed: () async => editor.localizeToken(name),
                )
              : null,
        ),
      ],
    );
  }

  /// The title row's right end of a mode column: what the column is to the
  /// default — nothing, for the default itself; *same as default* for a
  /// mode with no value of its own; a link back to that when it has one.
  Widget? _modeTrailing(
    TokensLibrary library,
    SceneTokenDecl decl,
    String? mode,
    VoidCallback reset,
  ) {
    if (mode == null) return null;
    var own = decl.modes.containsKey(mode);
    return DrawerLink('same as default', onTap: own ? reset : null);
  }

  DrawerSection _valueSection(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    String? mode,
  ) {
    var value = decl.valueIn(mode)!;
    return DrawerSection(
      key: ValueKey('token-mode:${mode ?? 'default'}'),
      title: mode ?? 'Default',
      width: 260,
      trailing: _modeTrailing(
        library,
        decl,
        mode,
        () => library.setValue(decl.name, decl.value!, mode: mode),
      ),
      child: _control(context, decl, value, (v, {String? mergeKey}) {
        library.setValue(decl.name, v, mode: mode, mergeKey: mergeKey);
      }, endMerge: library.endMerge),
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

  /// A style's fields in one mode: size, weight and align on a row, the
  /// colour under them — each unset-able, because a style sets only what
  /// it sets, and a text takes it whole.
  DrawerSection _styleSection(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    String? mode,
  ) {
    var style = decl.styleIn(mode)!;
    var key = 'style:${decl.name}:${mode ?? ''}';
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    void put(SceneTextStyle next, {String? mergeKey}) =>
        library.setStyle(decl.name, next, mode: mode, mergeKey: mergeKey);
    Widget field(String label, Widget control, {VoidCallback? unset}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: caption,
                ),
              ),
              if (unset != null) DrawerLink('unset', onTap: unset),
            ],
          ),
        ),
        control,
      ],
    );
    return DrawerSection(
      key: ValueKey('style-mode:${mode ?? 'default'}'),
      title: mode ?? 'Default',
      width: 360,
      trailing: _modeTrailing(
        library,
        decl,
        mode,
        () => library.setStyle(decl.name, decl.style!, mode: mode),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: FwSpacing.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: FwSpacing.md,
            children: [
              Expanded(
                child: field(
                  style.fontSize == null ? 'Size · unset' : 'Size',
                  SceneNumberField(
                    value: style.fontSize ?? 16,
                    shape: const SceneNumberShape(perPixel: 1, decimals: 2),
                    onChanged: (v) =>
                        put(_with(style, fontSize: v), mergeKey: key),
                    onCommit: (v) {
                      put(_with(style, fontSize: v), mergeKey: key);
                      library.endMerge();
                    },
                  ),
                  unset: style.fontSize == null
                      ? null
                      : () => put(_with(style, clearFontSize: true)),
                ),
              ),
              Expanded(
                flex: 2,
                child: field(
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
              ),
              Expanded(
                flex: 2,
                child: field(
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
              ),
            ],
          ),
          field(
            style.color == null ? 'Colour · unset' : 'Colour',
            SceneSwatches(
              current: style.color,
              onPick: (c) => put(_with(style, color: c, clearColor: c == null)),
            ),
          ),
        ],
      ),
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
