import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
  test('a scene file is named from its class, not asked for', () {
    // One name to type. The class is the scene's identity everywhere else,
    // so a file name asked for separately is only a way for the two to
    // disagree.
    expect(sceneFileNameFor('PromoBadge'), 'promo_badge.scene.dart');
    expect(sceneFileNameFor('Invoice'), 'invoice.scene.dart');
    expect(sceneFileNameFor('StoreBanner2'), 'store_banner2.scene.dart');
    expect(sceneFileNameFor('ABTest'), 'abtest.scene.dart');
  });

  test('the coffee banner round-trips', () {
    var doc = coffeeBannerDraft();
    var emitted = emitSceneFile(doc, className: 'BannerScene');
    var parsed = parseSceneFile(emitted);
    expect(parsed.refusals, isEmpty);
    expect(parsed.ok, isTrue);
    expect(parsed.className, 'BannerScene');
    var again = emitSceneFile(parsed.doc!, className: 'BannerScene');
    expect(again, emitted);
  });

  test('every node is a late final field, root last', () {
    var emitted = emitSceneFile(coffeeBannerDraft());
    expect(emitted, contains('late final headline = TextNode('));
    expect(emitted, contains('late final badge = ExternalNode('));
    expect(emitted, contains('const DrinkBadgeArgs(size: 140)'));
    expect(emitted, contains('children: [headline, subtitle, cta]'));
    // Canonical order: a field is declared before the field that places it.
    var root = emitted.indexOf('late final root');
    expect(root, greaterThan(emitted.indexOf('late final headline')));
    expect(root, greaterThan(emitted.indexOf('late final copy')));
  });

  group('the file owns its imports', () {
    String withImports(String extra) =>
        '''
$sceneFileMarker
$sceneAuthoringImport
$extra

class S extends SceneDefinition {
  @override
  late final root = FrameNode(width: 100, height: 100);
}
''';

    test('an import the tool did not write survives a save', () {
      // The tool rewrites this whole file, so an import it drops is gone —
      // and an Ext names an app widget, which only the author can locate.
      var parsed = parseSceneFile(
        withImports("import '../shop/shop_app.dart' as app;"),
      );
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      expect(parsed.imports, ["import '../shop/shop_app.dart' as app;"]);
      var out = emitSceneFile(
        parsed.doc!,
        className: 'S',
        imports: parsed.imports,
      );
      expect(out, contains("import '../shop/shop_app.dart' as app;"));
      var again = parseSceneFile(out);
      expect(again.refusals, isEmpty);
      expect(
        emitSceneFile(again.doc!, className: 'S', imports: again.imports),
        out,
      );
    });

    test('and converges on one order', () {
      var parsed = parseSceneFile(
        withImports(
          "import '../b.dart';\n"
          "import 'package:z/z.dart';\n"
          "import '../a.dart';",
        ),
      );
      expect(parsed.refusals, isEmpty);
      var out = emitSceneFile(
        parsed.doc!,
        className: 'S',
        imports: parsed.imports,
      );
      expect(
        out.indexOf('package:z/z.dart'),
        lessThan(out.indexOf('../a.dart')),
        reason: 'package imports first',
      );
      expect(
        out.indexOf('../a.dart'),
        lessThan(out.indexOf('../b.dart')),
        reason: 'each group sorted',
      );
    });

    test('a file without the authoring import is refused', () {
      var parsed = parseSceneFile('''
$sceneFileMarker

class S extends SceneDefinition {
  @override
  late final root = FrameNode(width: 100, height: 100);
}
''');
      expect(parsed.ok, isFalse);
      expect(
        parsed.refusals.map((r) => r.construct),
        contains('missing import'),
      );
    });

    test('an export is refused — the tool rewrites the whole file', () {
      var parsed = parseSceneFile(
        withImports("export '../shop/shop_app.dart';"),
      );
      expect(parsed.ok, isFalse);
      expect(parsed.refusals.first.construct, 'directive');
    });
  });

  test('emit ∘ parse is the identity on canonical files', () {
    var canonical = emitSceneFile(coffeeBannerDraft());
    var once = emitSceneFile(parseSceneFile(canonical).doc!);
    expect(once, canonical);
  });

  test('accepted non-canonical spellings converge in one emit', () {
    // `final` for `late final`, root first (forward references), 1024.0 for
    // 1024, lowercase hex, double quotes, and no `extends SceneDefinition`:
    // accepted, then canonical.
    var parsed = parseSceneFile('''
$sceneFileMarker
$sceneAuthoringImport
class S {
  final root = FrameNode(
    width: 1024.0,
    height: 500,
    fill: SceneColor(0xff2b1b12),
    children: [badge, caption],
  );
  final badge = ExternalNode(const DrinkBadgeArgs());
  final caption = TextNode("Banner");
}
''');
    expect(parsed.refusals, isEmpty);
    var emitted = emitSceneFile(parsed.doc!, className: 'S');
    expect(emitted, contains('width: 1024,'));
    expect(emitted, contains('SceneColor(0xFF2B1B12)'));
    expect(
      emitted,
      contains('late final badge = ExternalNode(const DrinkBadgeArgs())'),
    );
    expect(emitted, contains("TextNode('Banner')"));
    expect(
      emitted.indexOf('late final badge'),
      lessThan(emitted.indexOf('late final root')),
    );
    var again = emitSceneFile(parseSceneFile(emitted).doc!, className: 'S');
    expect(again, emitted);
  });

  test('fuzz: 300 random documents survive emit → parse → emit', () {
    var random = Random(20260831);
    for (var i = 0; i < 300; i++) {
      var doc = _randomDoc(random);
      var emitted = emitSceneFile(doc, className: 'Fuzz$i');
      var parsed = parseSceneFile(emitted);
      expect(
        parsed.refusals,
        isEmpty,
        reason:
            'iteration $i refused its own emit:\n'
            '${parsed.refusals.join('\n')}\n$emitted',
      );
      var again = emitSceneFile(parsed.doc!, className: 'Fuzz$i');
      expect(again, emitted, reason: 'iteration $i drifted');
    }
  });

  group('parameters — typed holes with the mockup as the default', () {
    const banner =
        '''
$sceneFileMarker
$sceneAuthoringImport
class BannerScene({
  final String title = 'Fresh coffee, faster',
  final SceneColor accent = const SceneColor(0xFFE8632B),
  final double slide = 24,
}) {
  late final headline = TextNode(title, fontSize: 54);
  late final cta = FrameNode(x: slide, fill: accent, children: [label]);
  late final label = TextNode('Get the app');
  late final root = FrameNode(width: 1024, height: 500, children: [headline, cta]);
}
''';

    test('a parameterized scene round-trips', () {
      var parsed = parseSceneFile(banner);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var doc = parsed.doc!;
      expect(doc.params.map((p) => p.name), ['title', 'accent', 'slide']);
      // The default is the mockup: properties hold resolved values.
      var headline = doc.root.children[0] as TextNode;
      expect(headline.text, 'Fresh coffee, faster');
      expect(headline.bindings['text'], const ParamRef('title'));
      var cta = doc.root.children[1] as FrameNode;
      expect(cta.x, 24);
      expect(cta.fill, const SceneColor(0xFFE8632B));

      var emitted = emitSceneFile(doc, className: 'BannerScene');
      expect(emitted, contains('class BannerScene({'));
      expect(emitted, contains("final String title = 'Fresh coffee, faster'"));
      expect(emitted, contains('const SceneColor(0xFFE8632B)'));
      var again = emitSceneFile(
        parseSceneFile(emitted).doc!,
        className: 'BannerScene',
      );
      expect(again, emitted);
      // The references survived the round trip as identifiers.
      expect(emitted, contains('TextNode(title'));
      expect(emitted, contains('x: slide'));
      expect(emitted, contains('fill: accent'));
    });

    test('two argument sets from one file', () {
      var german = parseSceneFile(banner).doc!
        ..applyArgs({'title': 'Frischer Kaffee, schneller', 'slide': 40});
      var french = parseSceneFile(banner).doc!
        ..applyArgs({'title': 'Du café frais, plus vite'});
      expect(
        (german.root.children[0] as TextNode).text,
        'Frischer Kaffee, schneller',
      );
      expect((german.root.children[1] as FrameNode).x, 40);
      expect(
        (french.root.children[0] as TextNode).text,
        'Du café frais, plus vite',
      );
      expect((french.root.children[1] as FrameNode).x, 24);
    });

    test('an edit to a bound property moves the default, not the binding', () {
      var doc = parseSceneFile(banner).doc!;
      (doc.root.children[0] as TextNode).text = 'Hand-tuned headline';
      expect(reconcileBindings(doc), isEmpty);
      // The default IS the mockup: the file now declares the edited text
      // as the parameter's default and the property still reads it.
      expect(doc.paramNamed('title')!.defaultValue, 'Hand-tuned headline');
      var emitted = emitSceneFile(doc, className: 'BannerScene');
      expect(emitted, contains("final String title = 'Hand-tuned headline'"));
      expect(emitted, contains('TextNode(title'));
      expect(emitted, isNot(contains("TextNode('Hand-tuned headline'")));
      // And the untouched references survive.
      expect(emitted, contains('x: slide'));
    });

    test('a save spells the reference even when nothing reconciled', () {
      // The binding is the stronger of the two: a value written behind the
      // editor's back is what gets lost, never the reference.
      var doc = parseSceneFile(banner).doc!;
      (doc.root.children[1] as FrameNode).x = 99;
      var emitted = emitSceneFile(doc, className: 'BannerScene');
      expect(emitted, contains('x: slide'));
      expect(emitted, contains('final double slide = 24'));
    });

    test('every reader of a parameter follows an edit to one of them', () {
      var source =
          '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Twins({final SceneColor accent = const SceneColor(0xFF112233)})
    extends SceneDefinition {
  late final a = FrameNode(width: 10, height: 10, fill: accent);
  late final b = FrameNode(x: 20, width: 10, height: 10, fill: accent);
  @override
  late final root = FrameNode(width: 100, height: 100, children: [a, b]);
}
''';
      var doc = parseSceneFile(source).doc!;
      var a = doc.root.children[0] as FrameNode;
      var b = doc.root.children[1] as FrameNode;
      a.fill = const SceneColor(0xFFABCDEF);
      reconcileBindings(doc);
      expect(b.fill, const SceneColor(0xFFABCDEF));
      expect(
        doc.paramNamed('accent')!.defaultValue,
        const SceneColor(0xFFABCDEF),
      );
      expect(a.bindings['fill'], const ParamRef('accent'));
      expect(b.bindings['fill'], const ParamRef('accent'));
    });

    test(
      'a cleared property, or a parameter that is gone, drops its binding',
      () {
        var doc = parseSceneFile(banner).doc!;
        var cta = doc.root.children[1] as FrameNode;
        cta.fill = null;
        doc.params.removeWhere((p) => p.name == 'slide');
        expect(reconcileBindings(doc), unorderedEquals(['cta.fill', 'cta.x']));
        expect(cta.bindings, isEmpty);
        // The value the node had is what the file now says — baked in, but
        // by an explicit step that reported it, not by a save.
        expect(emitSceneFile(doc, className: 'BannerScene'), contains('x: 24'));
      },
    );

    void refusesParam(String description, String source, String construct) {
      test(description, () {
        var parsed = parseSceneFile('$sceneFileMarker\n$source');
        expect(parsed.ok, isFalse, reason: 'accepted');
        expect(
          parsed.refusals.map((r) => r.construct),
          contains(construct),
          reason: parsed.refusals.join('\n'),
        );
      });
    }

    refusesParam('a String parameter where a color is expected', '''
class S({final String title = 'x'}) {
  late final root = FrameNode(fill: title);
}''', 'parameter type');
    refusesParam('a header type disagreeing with its default', '''
class S({final double title = 'x'}) {
  late final root = FrameNode();
}''', 'parameter type');
    refusesParam('a non-literal default', '''
class S({final String title = compute()}) {
  late final root = FrameNode();
}''', 'parameter default');
    refusesParam('a parameter without a default', '''
class S({required final String title}) {
  late final root = FrameNode();
}''', 'no default');
    refusesParam('a parameter name colliding with a node name', '''
class S({final double glow = 1}) {
  late final glow = ShapeNode();
  late final root = FrameNode(children: [glow]);
}''', 'duplicate name');
    refusesParam('a this. formal in the header', '''
class S({this.x = 2}) {
  late final root = FrameNode();
}''', 'parameter');
    refusesParam("the old grammar's body constructor", '''
class S {
  S({this.title = 'x'});
  final String title;
  late final root = FrameNode();
}''', 'constructor');
    refusesParam('a parameter placed as a child', '''
class S({final String title = 'x'}) {
  late final root = FrameNode(children: [title]);
}''', 'parameter as child');
  });

  group('hostile hand edits are refused with a name and a line', () {
    void refuses(
      String description,
      String members, {
      required String construct,
    }) {
      test(description, () {
        var source = '$sceneFileMarker\nclass S {\n  $members\n}\n';
        late SceneParse parsed;
        expect(() => parsed = parseSceneFile(source), returnsNormally);
        expect(parsed.ok, isFalse, reason: 'accepted:\n$source');
        expect(
          parsed.refusals.map((r) => r.construct),
          contains(construct),
          reason: parsed.refusals.join('\n'),
        );
        for (var refusal in parsed.refusals) {
          expect(refusal.line, greaterThan(0));
          expect(refusal.message, isNotEmpty);
        }
      });
    }

    refuses(
      'a for element in children',
      "late final t = TextNode('x');\n"
          '  late final root = '
          'FrameNode(children: [for (var i = 0; i < 3; i++) t]);',
      construct: 'for element',
    );
    refuses(
      'string interpolation',
      "late final t = TextNode('hello \$name');\n"
          '  late final root = FrameNode(children: [t]);',
      construct: 'interpolation',
    );
    refuses(
      'a method call as a value',
      'late final root = FrameNode(padding: computePadding());',
      construct: 'method call',
    );
    refuses(
      'a conditional',
      'late final root = FrameNode(opacity: dark ? 1 : 0.5);',
      construct: 'conditional',
    );
    refuses(
      'an identifier off the allowlist',
      'late final root = FrameNode(fill: brandColor);',
      construct: 'identifier',
    );
    refuses(
      'a Colors.* alias',
      'late final root = FrameNode(fill: Colors.white);',
      construct: 'identifier',
    );
    refuses(
      'arithmetic',
      'late final root = FrameNode(x: 2 + 3);',
      construct: 'arithmetic',
    );
    refuses(
      'an unknown property',
      'late final root = FrameNode(flavor: 1);',
      construct: 'unknown property',
    );
    refuses(
      'an unknown node type',
      'late final s = Sparkle();\n'
          '  late final root = FrameNode(children: [s]);',
      construct: 'unknown node',
    );
    refuses(
      'a duplicate field name',
      'late final a = ShapeNode();\n'
          '  late final a = ShapeNode();\n'
          '  late final root = FrameNode(children: [a]);',
      construct: 'duplicate name',
    );
    refuses(
      'adjacent strings',
      "late final t = TextNode('one' ' two');\n"
          '  late final root = FrameNode(children: [t]);',
      construct: 'adjacent strings',
    );
    refuses(
      'an inline node in children',
      "late final root = FrameNode(children: [TextNode('x')]);",
      construct: 'inline node',
    );
    refuses(
      'a reference to an undeclared node',
      'late final root = FrameNode(children: [ghost]);',
      construct: 'unknown reference',
    );
    refuses(
      'a node placed twice',
      'late final a = ShapeNode();\n'
          '  late final root = FrameNode(children: [a, a]);',
      construct: 'placed twice',
    );
    refuses(
      'an orphan field',
      'late final a = ShapeNode();\n'
          '  late final root = FrameNode();',
      construct: 'orphan node',
    );
    refuses(
      'root placed as a child',
      'late final root = FrameNode(children: [root]);',
      construct: 'root as child',
    );
    refuses(
      'a cycle off the root',
      'late final a = FrameNode(children: [b]);\n'
          '  late final b = FrameNode(children: [a]);\n'
          '  late final root = FrameNode();',
      construct: 'unreachable node',
    );
    refuses(
      "the old grammar's positional name",
      "late final root = FrameNode('banner');",
      construct: 'positional argument',
    );
    refuses(
      'a method member on the class',
      'late final root = FrameNode();\n'
          '  int f() => 1;',
      construct: 'member',
    );

    test('a comment inside the scene', () {
      var parsed = parseSceneFile('''
$sceneFileMarker
$sceneAuthoringImport
class S {
  // tuned by hand, do not touch
  late final root = FrameNode();
}
''');
      expect(parsed.ok, isFalse);
      expect(parsed.refusals.map((r) => r.construct), contains('comment'));
    });

    test('a missing marker', () {
      var parsed = parseSceneFile('class S { late final root = FrameNode(); }');
      expect(parsed.ok, isFalse);
      expect(
        parsed.refusals.map((r) => r.construct),
        contains('missing marker'),
      );
    });

    test('several hostile constructs are all reported at once', () {
      var parsed = parseSceneFile('''
$sceneFileMarker
$sceneAuthoringImport
class S {
  late final root = FrameNode(
    x: 2 + 3,
    fill: brandColor,
    children: [ghost],
  );
}
''');
      expect(parsed.ok, isFalse);
      expect(parsed.refusals.length, greaterThanOrEqualTo(3));
    });

    test('broken syntax reports rather than throws', () {
      late SceneParse parsed;
      expect(
        () => parsed = parseSceneFile('$sceneFileMarker\nclass S { final ='),
        returnsNormally,
      );
      expect(parsed.ok, isFalse);
      expect(parsed.refusals, isNotEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Fuzzer
// ---------------------------------------------------------------------------

const _chars = [
  'a',
  'b',
  'z',
  'A',
  'Z',
  '0',
  '9',
  ' ',
  "'",
  '"',
  r'$',
  r'\',
  '\n',
  '\t',
  '☕',
  'é',
  '{',
  '}',
  '(',
  ')',
  '//',
  '*',
];

String _randomString(Random r) =>
    [for (var i = 0; i < r.nextInt(14); i++) _chars[r.nextInt(_chars.length)]]
        .join();

double _randomDouble(Random r) {
  var v = r.nextDouble() * 2000 - 400;
  // Limited precision keeps the generator away from float-format noise the
  // canonical spelling already handles; the spelling is tested either way.
  v = (v * 10).roundToDouble() / 10;
  return v == 0 ? 1 : v;
}

SceneColor _randomColor(Random r) => SceneColor(r.nextInt(0xFFFFFFFF) + 1);

int _counter = 0;

SceneNode _randomNode(Random r, int depth) {
  var name = 'n${_counter++}';
  SceneNode node;
  switch (depth < 3 ? r.nextInt(4) : 1 + r.nextInt(3)) {
    case 0:
      var frame = FrameNode(name: name)
        ..layout = NodeLayout.values[r.nextInt(3)]
        ..gap = _randomDouble(r).abs()
        ..padding = switch (r.nextInt(3)) {
          0 => SceneEdges.zero,
          1 => SceneEdges.all(_randomDouble(r).abs()),
          _ => SceneEdges(
            left: _randomDouble(r).abs(),
            top: _randomDouble(r).abs(),
            right: _randomDouble(r).abs(),
            bottom: _randomDouble(r).abs(),
          ),
        }
        ..mainAlign = SceneMainAxisAlignment.values[r.nextInt(4)]
        ..crossAlign = SceneCrossAxisAlignment.values[r.nextInt(4)];
      for (var i = 0; i < r.nextInt(5); i++) {
        frame.children.add(_randomNode(r, depth + 1));
      }
      node = frame;
    case 1:
      node = TextNode(_randomString(r), name: name)
        ..fontSize = 8 + _randomDouble(r).abs() % 90
        ..weight = SceneFontWeight.values[r.nextInt(9)]
        ..color = _randomColor(r);
    case 2:
      node = ShapeNode(name: name, circle: r.nextBool());
    default:
      var ext = ExternalNode.read('Entry${r.nextInt(4)}', name: name);
      for (var i = 0; i < r.nextInt(3); i++) {
        ext.args['k$i'] = switch (r.nextInt(3)) {
          0 => _randomDouble(r),
          1 => _randomString(r),
          _ => r.nextBool(),
        };
      }
      node = ext;
  }
  node
    ..x = r.nextBool() ? 0 : _randomDouble(r)
    ..y = r.nextBool() ? 0 : _randomDouble(r)
    ..width = r.nextBool() ? null : _randomDouble(r).abs() + 1
    ..height = r.nextBool() ? null : _randomDouble(r).abs() + 1
    ..fill = r.nextBool() ? null : _randomColor(r)
    ..corner = r.nextBool() ? 0 : _randomDouble(r).abs()
    ..opacity = r.nextBool() ? 1 : (r.nextInt(10) / 10);
  return node;
}

SceneDocument _randomDoc(Random r) {
  var root = FrameNode(name: 'root')
    ..width = 1024
    ..height = 500;
  for (var i = 0; i < 1 + r.nextInt(6); i++) {
    root.children.add(_randomNode(r, 0));
  }
  var doc = SceneDocument(root);
  // Parameters: typed holes bound onto some of the nodes just built. A
  // bound property holds the default (a live reference only survives while
  // value == default — the divergence rule is itself under test).
  var nodes = [for (var (n, _) in doc.walk()) n];
  for (var i = r.nextInt(4); i > 0; i--) {
    var name = 'p${_counter++}';
    switch (r.nextInt(3)) {
      case 0:
        var decl = SceneParamDecl(
          name,
          SceneParamKind.string,
          _randomString(r),
        );
        doc.params.add(decl);
        var texts = nodes.whereType<TextNode>().toList();
        if (texts.isNotEmpty) {
          var t = texts[r.nextInt(texts.length)];
          t.text = decl.defaultValue as String;
          t.bindings['text'] = ParamRef(name);
        }
      case 1:
        var decl = SceneParamDecl(
          name,
          SceneParamKind.number,
          _randomDouble(r),
        );
        doc.params.add(decl);
        var n = nodes[r.nextInt(nodes.length)];
        n.x = decl.defaultValue as double;
        n.bindings['x'] = ParamRef(name);
      default:
        var decl = SceneParamDecl(name, SceneParamKind.color, _randomColor(r));
        doc.params.add(decl);
        var n = nodes[r.nextInt(nodes.length)];
        n.fill = decl.defaultValue as SceneColor;
        n.bindings['fill'] = ParamRef(name);
    }
  }
  return doc;
}
