import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

void main() {
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
    expect(emitted, contains('late final headline = Text('));
    expect(emitted, contains('late final badge = Ext('));
    expect(emitted, contains('DrinkBadge,'));
    expect(emitted, contains('children: [headline, subtitle, cta]'));
    // Canonical order: a field is declared before the field that places it.
    var root = emitted.indexOf('late final root');
    expect(root, greaterThan(emitted.indexOf('late final headline')));
    expect(root, greaterThan(emitted.indexOf('late final copy')));
  });

  test('emit ∘ parse is the identity on canonical files', () {
    var canonical = emitSceneFile(coffeeBannerDraft());
    var once = emitSceneFile(parseSceneFile(canonical).doc!);
    expect(once, canonical);
  });

  test('accepted non-canonical spellings converge in one emit', () {
    // `final` for `late final`, root first (forward references), 1024.0 for
    // 1024, lowercase hex, double quotes, a quoted Ext entry: accepted, then
    // canonical.
    var parsed = parseSceneFile('''
$sceneFileMarker
class S {
  final root = Frame(
    width: 1024.0,
    height: 500,
    fill: Color(0xff2b1b12),
    children: [badge, caption],
  );
  final badge = Ext('DrinkBadge');
  final caption = Text("Banner");
}
''');
    expect(parsed.refusals, isEmpty);
    var emitted = emitSceneFile(parsed.doc!, className: 'S');
    expect(emitted, contains('width: 1024,'));
    expect(emitted, contains('Color(0xFF2B1B12)'));
    expect(emitted, contains('late final badge = Ext(DrinkBadge)'));
    expect(emitted, contains("Text('Banner')"));
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
class BannerScene({
  final String title = 'Fresh coffee, faster',
  final Color accent = const Color(0xFFE8632B),
  final double slide = 24,
}) {
  late final headline = Text(title, fontSize: 54);
  late final cta = Frame(x: slide, fill: accent, children: [label]);
  late final label = Text('Get the app');
  late final root = Frame(width: 1024, height: 500, children: [headline, cta]);
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
      expect(headline.paramRefs['text'], 'title');
      var cta = doc.root.children[1] as FrameNode;
      expect(cta.x, 24);
      expect(cta.fill, const SceneColor(0xFFE8632B));

      var emitted = emitSceneFile(doc, className: 'BannerScene');
      expect(emitted, contains('class BannerScene({'));
      expect(emitted, contains("final String title = 'Fresh coffee, faster'"));
      expect(emitted, contains('const Color(0xFFE8632B)'));
      var again = emitSceneFile(
        parseSceneFile(emitted).doc!,
        className: 'BannerScene',
      );
      expect(again, emitted);
      // The references survived the round trip as identifiers.
      expect(emitted, contains('Text(title'));
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

    test(
      'an edited value bakes in; the stale reference is dropped, not the edit',
      () {
        var doc = parseSceneFile(banner).doc!;
        (doc.root.children[0] as TextNode).text = 'Hand-tuned headline';
        var emitted = emitSceneFile(doc, className: 'BannerScene');
        expect(emitted, contains("Text('Hand-tuned headline'"));
        expect(emitted, isNot(contains('Text(title')));
        // And the untouched references survive.
        expect(emitted, contains('x: slide'));
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
  late final root = Frame(fill: title);
}''', 'parameter type');
    refusesParam('a header type disagreeing with its default', '''
class S({final double title = 'x'}) {
  late final root = Frame();
}''', 'parameter type');
    refusesParam('a non-literal default', '''
class S({final String title = compute()}) {
  late final root = Frame();
}''', 'parameter default');
    refusesParam('a parameter without a default', '''
class S({required final String title}) {
  late final root = Frame();
}''', 'no default');
    refusesParam('a parameter name colliding with a node name', '''
class S({final double glow = 1}) {
  late final glow = Shape();
  late final root = Frame(children: [glow]);
}''', 'duplicate name');
    refusesParam('a this. formal in the header', '''
class S({this.x = 2}) {
  late final root = Frame();
}''', 'parameter');
    refusesParam("the old grammar's body constructor", '''
class S {
  S({this.title = 'x'});
  final String title;
  late final root = Frame();
}''', 'constructor');
    refusesParam('a parameter placed as a child', '''
class S({final String title = 'x'}) {
  late final root = Frame(children: [title]);
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
      "late final t = Text('x');\n"
          '  late final root = '
          'Frame(children: [for (var i = 0; i < 3; i++) t]);',
      construct: 'for element',
    );
    refuses(
      'string interpolation',
      "late final t = Text('hello \$name');\n"
          '  late final root = Frame(children: [t]);',
      construct: 'interpolation',
    );
    refuses(
      'a method call as a value',
      'late final root = Frame(padding: computePadding());',
      construct: 'method call',
    );
    refuses(
      'a conditional',
      'late final root = Frame(opacity: dark ? 1 : 0.5);',
      construct: 'conditional',
    );
    refuses(
      'an identifier off the allowlist',
      'late final root = Frame(fill: brandColor);',
      construct: 'identifier',
    );
    refuses(
      'a Colors.* alias',
      'late final root = Frame(fill: Colors.white);',
      construct: 'identifier',
    );
    refuses(
      'arithmetic',
      'late final root = Frame(x: 2 + 3);',
      construct: 'arithmetic',
    );
    refuses(
      'an unknown property',
      'late final root = Frame(flavor: 1);',
      construct: 'unknown property',
    );
    refuses(
      'an unknown node type',
      'late final s = Sparkle();\n'
          '  late final root = Frame(children: [s]);',
      construct: 'unknown node',
    );
    refuses(
      'a duplicate field name',
      'late final a = Shape();\n'
          '  late final a = Shape();\n'
          '  late final root = Frame(children: [a]);',
      construct: 'duplicate name',
    );
    refuses(
      'adjacent strings',
      "late final t = Text('one' ' two');\n"
          '  late final root = Frame(children: [t]);',
      construct: 'adjacent strings',
    );
    refuses(
      'an inline node in children',
      "late final root = Frame(children: [Text('x')]);",
      construct: 'inline node',
    );
    refuses(
      'a reference to an undeclared node',
      'late final root = Frame(children: [ghost]);',
      construct: 'unknown reference',
    );
    refuses(
      'a node placed twice',
      'late final a = Shape();\n'
          '  late final root = Frame(children: [a, a]);',
      construct: 'placed twice',
    );
    refuses(
      'an orphan field',
      'late final a = Shape();\n'
          '  late final root = Frame();',
      construct: 'orphan node',
    );
    refuses(
      'root placed as a child',
      'late final root = Frame(children: [root]);',
      construct: 'root as child',
    );
    refuses(
      'a cycle off the root',
      'late final a = Frame(children: [b]);\n'
          '  late final b = Frame(children: [a]);\n'
          '  late final root = Frame();',
      construct: 'unreachable node',
    );
    refuses(
      "the old grammar's positional name",
      "late final root = Frame('banner');",
      construct: 'positional argument',
    );
    refuses(
      'a method member on the class',
      'late final root = Frame();\n'
          '  int f() => 1;',
      construct: 'member',
    );

    test('a comment inside the scene', () {
      var parsed = parseSceneFile('''
$sceneFileMarker
class S {
  // tuned by hand, do not touch
  late final root = Frame();
}
''');
      expect(parsed.ok, isFalse);
      expect(parsed.refusals.map((r) => r.construct), contains('comment'));
    });

    test('a missing marker', () {
      var parsed = parseSceneFile('class S { late final root = Frame(); }');
      expect(parsed.ok, isFalse);
      expect(
        parsed.refusals.map((r) => r.construct),
        contains('missing marker'),
      );
    });

    test('several hostile constructs are all reported at once', () {
      var parsed = parseSceneFile('''
$sceneFileMarker
class S {
  late final root = Frame(
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
      var frame = FrameNode(name)
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
      node = TextNode(name, _randomString(r))
        ..fontSize = 8 + _randomDouble(r).abs() % 90
        ..weight = SceneFontWeight.values[r.nextInt(9)]
        ..color = _randomColor(r);
    case 2:
      node = ShapeNode(name, circle: r.nextBool());
    default:
      var ext = ExternalNode(name, 'Entry${r.nextInt(4)}');
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
    ..cornerRadius = r.nextBool() ? 0 : _randomDouble(r).abs()
    ..opacity = r.nextBool() ? 1 : (r.nextInt(10) / 10);
  return node;
}

SceneDocument _randomDoc(Random r) {
  var root = FrameNode('root')
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
          t.paramRefs['text'] = name;
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
        n.paramRefs['x'] = name;
      default:
        var decl = SceneParamDecl(name, SceneParamKind.color, _randomColor(r));
        doc.params.add(decl);
        var n = nodes[r.nextInt(nodes.length)];
        n.fill = decl.defaultValue as SceneColor;
        n.paramRefs['fill'] = name;
    }
  }
  return doc;
}
