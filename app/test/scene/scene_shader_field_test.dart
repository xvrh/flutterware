// The shader pass's editor, driven through the paint field that mounts it: a
// picker over the package's declared shaders, then a control per uniform the
// reflection lists, drawn from the shader's own comments.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/shader_library.dart';
import 'package:flutterware_app/src/scene/ui/number_field.dart';
import 'package:flutterware_app/src/scene/ui/number_shape.dart';
import 'package:flutterware_app/src/scene/ui/paint_field.dart';
import 'package:flutterware_app/src/scene/ui/shader_field.dart';
import 'package:flutterware_app/src/scene/ui/swatches.dart';
import 'package:flutterware_app/src/ui/tappable.dart';
import 'package:flutterware_app/src/ui/theme.dart';

const _red = SceneColor(0xFFFF0000);

const _foilDefaults = ShaderPaint(
  'shaders/foil.frag',
  uniforms: {
    'uAngle': [0.6],
    'uShine': [1, 0.85, 0.4],
  },
);

/// Declares one shader and never finishes reading it.
class _Compiling extends ChangeNotifier implements SceneShaders {
  @override
  List<String> get declared => const ['shaders/foil.frag'];

  @override
  SceneShaderInfo? info(String key) => null;
}

void main() {
  final shaders = FixedSceneShaders({
    'shaders/foil.frag': SceneShaderInfo(
      key: 'shaders/foil.frag',
      uniforms: [
        SceneShaderUniform(name: 'uSize', size: 2, location: 0),
        SceneShaderUniform(
          name: 'uAngle',
          size: 1,
          location: 1,
          range: (0, 6.283),
          defaults: [0.6],
        ),
        SceneShaderUniform(
          name: 'uShine',
          size: 3,
          location: 2,
          isColor: true,
          defaults: [1, 0.85, 0.4],
        ),
        SceneShaderUniform(name: 'uOffset', size: 2, location: 3),
      ],
    ),
    'shaders/plain.frag': SceneShaderInfo(key: 'shaders/plain.frag'),
  });

  late ScenePaint? paint;
  late List<(String, String?)> writes;

  Future<void> pump(
    WidgetTester tester,
    ScenePaint? start, {
    SceneShaders? using,
  }) async {
    paint = start;
    writes = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) => ScenePaintField(
                  paint: paint,
                  own: _red,
                  shaders: using ?? shaders,
                  onChanged: (next, {required label, mergeKey}) {
                    writes.add((label, mergeKey));
                    setState(() => paint = next);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pick(WidgetTester tester, Key picker, String choice) async {
    await tester.tap(find.byKey(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  SceneNumberField field(WidgetTester tester, String label) =>
      tester.widget<SceneNumberField>(
        find.byWidgetPredicate(
          (w) => w is SceneNumberField && w.label == label,
        ),
      );

  Map<String, List<double>> uniforms() => (paint! as ShaderPaint).uniforms;

  testWidgets('choosing Shader takes the first declared shader, with its '
      'defaults', (tester) async {
    await pump(tester, const SolidPaint(_red));
    await pick(tester, const ValueKey('paint:kind'), 'Shader');
    expect(paint, _foilDefaults);
    expect(find.byType(SceneShaderField), findsOneWidget);
  });

  testWidgets("the renderer's uniforms are not offered", (tester) async {
    await pump(tester, _foilDefaults);
    expect(find.textContaining('uSize'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is SceneNumberField && (w.label ?? '').startsWith('uSize'),
      ),
      findsNothing,
    );
  });

  testWidgets('a ranged float is a slider', (tester) async {
    await pump(tester, _foilDefaults);
    var angle = field(tester, 'uAngle');
    expect(angle.shape.editor, SceneEditorShape.slider);
    expect(angle.value, 0.6);
    angle.onCommit(1.5);
    await tester.pump();
    expect(uniforms()['uAngle'], [1.5]);
    expect(uniforms()['uShine'], [1, 0.85, 0.4]);
    expect(writes.last.$1, 'Shader uniform');
  });

  testWidgets('a vec2 is one field per component', (tester) async {
    await pump(tester, _foilDefaults);
    expect(field(tester, 'uOffset.x').value, 0);
    field(tester, 'uOffset.y').onCommit(3);
    await tester.pump();
    expect(uniforms()['uOffset'], [0, 3]);
    expect(field(tester, 'uOffset.y').value, 3);
  });

  testWidgets('a colour uniform is a colour field', (tester) async {
    await pump(tester, _foilDefaults);
    expect(find.byType(SceneColorField), findsOneWidget);
    expect(find.text('uShine'), findsOneWidget);
    await tester.tap(find.byType(SceneColorField));
    await tester.pumpAndSettle();
    // 0xFFE8632B, the palette's orange.
    await tester.tap(
      find
          .descendant(
            of: find.byType(SceneSwatches),
            matching: find.byType(Tappable),
          )
          .at(6),
    );
    await tester.pumpAndSettle();
    var shine = uniforms()['uShine']!;
    expect(shine, [0.91, 0.388, 0.169]);
    expect(shine.every((v) => v >= 0 && v <= 1), isTrue);
  });

  testWidgets('picking another shader starts from its defaults', (
    tester,
  ) async {
    await pump(tester, _foilDefaults);
    await pick(tester, const ValueKey('paint:shader'), 'plain.frag');
    expect(paint, const ShaderPaint('shaders/plain.frag'));
    expect(writes.last.$1, 'Shader');
  });

  testWidgets('an undeclared asset says so', (tester) async {
    await pump(tester, const ShaderPaint('shaders/gone.frag'));
    expect(find.textContaining('is not declared'), findsOneWidget);
  });

  testWidgets('a stray uniform says so', (tester) async {
    await pump(
      tester,
      const ShaderPaint(
        'shaders/foil.frag',
        uniforms: {
          'uNope': [1],
        },
      ),
    );
    expect(find.textContaining('declares no such uniform'), findsOneWidget);
  });

  testWidgets('while it compiles, it says so', (tester) async {
    var compiling = _Compiling();
    addTearDown(compiling.dispose);
    await pump(tester, _foilDefaults, using: compiling);
    expect(find.text('Reading uniforms…'), findsOneWidget);
  });
}
