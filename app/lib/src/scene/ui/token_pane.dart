import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/picker.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../tokens_library.dart';
import '../../ui/disclosure.dart';
import 'drawer_pane.dart';
import 'layer_list.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';
import 'tokens_host.dart';

/// One token, open in the drawer under the canvas — the place a parameter
/// opens too, because both are values you edit while looking at the
/// nodes reading them above.
///
/// A library token is its value column: one row per mode — the default
/// first, then each mode the library names — with the value in the kind's
/// own control, or a style's fields; a mode left equal to the default says
/// so, and an edit there makes it the mode's own. Every reader in every
/// open scene follows an edit. An export says what it is — the app's, so
/// nothing to edit. Who reads it is on the drawer's header, and Make local
/// in its menu.
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
      var modes = library.modes;
      value = [
        DrawerSection(
          title: modes.isEmpty
              ? 'Value'
              : 'Value · default and ${modes.length} '
                    '${modes.length == 1 ? 'mode' : 'modes'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var (i, mode) in [null, ...modes].indexed)
                _modeRow(
                  context,
                  library,
                  decl,
                  mode,
                  first: i == 0,
                  child: decl.isStyle
                      ? _styleFields(context, library, decl, mode)
                      : _valueControl(context, library, decl, mode),
                ),
            ],
          ),
        ),
      ];
    }
    return DrawerPane(key: ValueKey('pane:token:$name'), sections: value);
  }

  /// One mode's row: its name, what it is to the default — nothing, for
  /// the default itself; *same as default* for a mode with no value of its
  /// own; a link back to that when it has one — and the value under it.
  Widget _modeRow(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    String? mode, {
    required bool first,
    required Widget child,
  }) {
    var colors = context.colors;
    Widget? trailing;
    if (mode != null) {
      var own = decl.modes.containsKey(mode);
      trailing = DrawerLink(
        'same as default',
        onTap: !own
            ? null
            : decl.isStyle
            ? () => library.setStyle(decl.name, decl.style!, mode: mode)
            : () => library.setValue(decl.name, decl.value!, mode: mode),
      );
    }
    return Container(
      key: ValueKey(
        '${decl.isStyle ? 'style' : 'token'}-mode:${mode ?? 'default'}',
      ),
      margin: EdgeInsets.only(top: first ? 0 : FwSpacing.md),
      padding: EdgeInsets.only(top: first ? 0 : FwSpacing.md),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: colors.line)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    mode ?? 'Default',
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodyStrong,
                  ),
                ),
                if (trailing != null) Flexible(child: trailing),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _valueControl(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    String? mode,
  ) => _control(context, decl, decl.valueIn(mode)!, (v, {String? mergeKey}) {
    library.setValue(decl.name, v, mode: mode, mergeKey: mergeKey);
  }, endMerge: library.endMerge);

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
        return SceneColorField(
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

  /// A style's fields in one mode. Every field the table carries, each
  /// unset-able, because a style sets only what it sets and a text takes it
  /// whole.
  ///
  /// The write goes through [SceneTextStyle.values] and
  /// [SceneTextStyle.fromValues] — the table's own round trip — rather than
  /// through a hand-written constructor call. The hand-written one named
  /// five fields and silently dropped the other eleven: setting the weight
  /// on a token that had a tracking, a stack of paint passes or a typeface
  /// deleted them from the file on the next autosave.
  Widget _styleFields(
    BuildContext context,
    TokensLibrary library,
    SceneTokenDecl decl,
    String? mode,
  ) {
    var style = decl.styleIn(mode)!;
    var key = 'style:${decl.name}:${mode ?? ''}';
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);

    void put(String prop, Object? value, {String? mergeKey}) {
      var values = Map<String, Object?>.of(style.values);
      if (value == null) {
        values.remove(prop);
      } else {
        values[prop] = value;
      }
      library.setStyle(
        decl.name,
        SceneTextStyle.fromValues(values),
        mode: mode,
        mergeKey: mergeKey,
      );
    }

    Widget field(String prop, String label, Widget control) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  style.sets(prop) ? label : '$label · unset',
                  overflow: TextOverflow.ellipsis,
                  style: caption,
                ),
              ),
              if (style.sets(prop))
                DrawerLink('unset', onTap: () => put(prop, null)),
            ],
          ),
        ),
        control,
      ],
    );

    Widget number(
      String prop,
      String label,
      double fallback, {
      SceneNumberShape shape = const SceneNumberShape(perPixel: 1, decimals: 2),
    }) => field(
      prop,
      label,
      SceneNumberField(
        value: (style.values[prop] as double?) ?? fallback,
        shape: shape,
        onChanged: (v) => put(prop, v, mergeKey: '$key:$prop'),
        onCommit: (v) {
          put(prop, v, mergeKey: '$key:$prop');
          library.endMerge();
        },
      ),
    );

    Widget choice<T>(String prop, String label, List<FwChoice<T?>> choices) =>
        field(
          prop,
          label,
          FwPicker<T?>(
            selected: style.values[prop] as T?,
            choices: [
              const FwChoice(value: null, label: 'unset'),
              ...choices,
            ],
            onChanged: (v) => put(prop, v),
          ),
        );

    Widget colour(String prop, String label) => field(
      prop,
      label,
      SceneColorField(
        current: style.values[prop] as SceneColor?,
        onPick: (c) => put(prop, c),
      ),
    );

    Widget row(List<Widget> children) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var (i, child) in children.indexed) ...[
          if (i > 0) const Gap(FwSpacing.md),
          Expanded(child: child),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: FwSpacing.md,
      children: [
        field(
          'fontFamily',
          'Typeface',
          TextFormField(
            key: ValueKey('$key:family:${style.fontFamily}'),
            initialValue: style.fontFamily ?? '',
            decoration: const InputDecoration(hintText: "the app's own"),
            onChanged: (v) =>
                put('fontFamily', v.trim().isEmpty ? null : v.trim()),
          ),
        ),
        row([
          number('fontSize', 'Size', 16),
          choice<SceneFontWeight>('weight', 'Weight', const [
            FwChoice(value: SceneFontWeight.w400, label: 'Regular'),
            FwChoice(value: SceneFontWeight.w500, label: 'Medium'),
            FwChoice(value: SceneFontWeight.w600, label: 'Semibold'),
            FwChoice(value: SceneFontWeight.w700, label: 'Bold'),
            FwChoice(value: SceneFontWeight.w900, label: 'Black'),
          ]),
        ]),
        row([
          number('letterSpacing', 'Tracking', 0),
          number('lineHeight', 'Leading', 1.15),
        ]),
        row([
          choice<SceneTextAlign>('align', 'Align', const [
            FwChoice(value: SceneTextAlign.left, label: 'Left'),
            FwChoice(value: SceneTextAlign.center, label: 'Center'),
            FwChoice(value: SceneTextAlign.right, label: 'Right'),
            FwChoice(value: SceneTextAlign.justify, label: 'Justify'),
          ]),
          choice<SceneTextCase>('textCase', 'Case', const [
            FwChoice(value: SceneTextCase.none, label: 'As typed'),
            FwChoice(value: SceneTextCase.upper, label: 'UPPER'),
            FwChoice(value: SceneTextCase.lower, label: 'lower'),
            FwChoice(value: SceneTextCase.title, label: 'Title'),
          ]),
        ]),
        colour('color', 'Colour'),
        // A treatment is what a shared style is FOR — a poster's outline
        // belongs in the library beside the size it was drawn at, not
        // copied onto each text that wants it.
        SceneLayerList(
          layers: style.layers ?? const [],
          fontSize: style.fontSize ?? 16,
          color: Color(style.color?.argb ?? 0xFF000000),
          onChanged: (next, {required label, mergeKey}) =>
              put('layers', next, mergeKey: mergeKey),
        ),
        Disclosure(
          label: 'More type',
          children: [
            row([
              choice<bool>('italic', 'Style', const [
                FwChoice(value: false, label: 'Roman'),
                FwChoice(value: true, label: 'Italic'),
              ]),
              number('wordSpacing', 'Word spacing', 0),
            ]),
            const Gap(FwSpacing.md),
            row([
              choice<SceneTextDecoration>('decoration', 'Decoration', const [
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
              ]),
              // An int, not a double: the field scrubs a number and the
              // style holds a count, so it rounds on the way in and unsets
              // at zero.
              field(
                'maxLines',
                'Max lines',
                SceneNumberField(
                  value: (style.maxLines ?? 0).toDouble(),
                  shape: const SceneNumberShape(
                    perPixel: 0.1,
                    decimals: 0,
                    min: 0,
                    softMax: 10,
                  ),
                  onChanged: (v) => put('maxLines', v < 1 ? null : v.round()),
                  onCommit: (v) {
                    put('maxLines', v < 1 ? null : v.round());
                    library.endMerge();
                  },
                ),
              ),
            ]),
            if (style.decoration != null &&
                style.decoration != SceneTextDecoration.none) ...[
              const Gap(FwSpacing.md),
              row([
                choice<SceneTextDecorationStyle>(
                  'decorationStyle',
                  'Line style',
                  const [
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
                ),
                number('decorationThickness', 'Line thickness', 1),
              ]),
              const Gap(FwSpacing.md),
              colour('decorationColor', 'Line color'),
            ],
          ],
        ),
      ],
    );
  }
}
