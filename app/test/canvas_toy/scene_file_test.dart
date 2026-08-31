import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/canvas_toy/model.dart';
import 'package:flutterware_app/canvas_toy/scene_file.dart';

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

  test('emit ∘ parse is the identity on canonical files', () {
    var canonical = emitSceneFile(coffeeBannerDraft());
    var once = emitSceneFile(parseSceneFile(canonical).doc!);
    expect(once, canonical);
  });

  test('accepted non-canonical spellings converge in one emit', () {
    // 64.0 for 64, double quotes, lowercase hex: accepted, then canonical.
    var parsed = parseSceneFile('''
$sceneFileMarker
class S {
  final root = Frame(
    "Banner",
    width: 1024.0,
    height: 500,
    fill: Color(0xff2b1b12),
  );
}
''');
    expect(parsed.refusals, isEmpty);
    var emitted = emitSceneFile(parsed.doc!, className: 'S');
    expect(emitted, contains('width: 1024,'));
    expect(emitted, contains('Color(0xFF2B1B12)'));
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

  group('hostile hand edits are refused with a name and a line', () {
    void refuses(String description, String body, {required String construct}) {
      test(description, () {
        var source = '$sceneFileMarker\nclass S {\n  final root = $body;\n}\n';
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
      "Frame('a', children: [for (var i = 0; i < 3; i++) Text('t', 'x')])",
      construct: 'for element',
    );
    refuses(
      'string interpolation',
      r"Frame('a', children: [Text('t', 'hello $name')])",
      construct: 'interpolation',
    );
    refuses(
      'a method call as a value',
      "Frame('a', padding: computePadding())",
      construct: 'method call',
    );
    refuses(
      'a conditional',
      "Frame('a', opacity: dark ? 1 : 0.5)",
      construct: 'conditional',
    );
    refuses(
      'an identifier off the allowlist',
      "Frame('a', fill: brandColor)",
      construct: 'identifier',
    );
    refuses(
      'a Colors.* alias',
      "Frame('a', fill: Colors.white)",
      construct: 'identifier',
    );
    refuses('arithmetic', "Frame('a', x: 2 + 3)", construct: 'arithmetic');
    refuses(
      'an unknown property',
      "Frame('a', flavor: 1)",
      construct: 'unknown property',
    );
    refuses(
      'an unknown node type',
      "Frame('a', children: [Sparkle('s')])",
      construct: 'unknown node',
    );
    refuses(
      'a duplicate node name',
      "Frame('a', children: [Shape('b'), Shape('b')])",
      construct: 'duplicate name',
    );
    refuses(
      'adjacent strings',
      "Frame('a', children: [Text('t', 'one' ' two')])",
      construct: 'adjacent strings',
    );

    test('a comment inside the scene', () {
      var parsed = parseSceneFile('''
$sceneFileMarker
class S {
  // tuned by hand, do not touch
  final root = Frame('a');
}
''');
      expect(parsed.ok, isFalse);
      expect(parsed.refusals.map((r) => r.construct), contains('comment'));
    });

    test('a second member on the class', () {
      var parsed = parseSceneFile('''
$sceneFileMarker
class S {
  final root = Frame('a');
  final extra = 1;
}
''');
      expect(parsed.ok, isFalse);
      expect(parsed.refusals.map((r) => r.construct), contains('member'));
    });

    test('a missing marker', () {
      var parsed = parseSceneFile("class S { final root = Frame('a'); }");
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
  final root = Frame(
    'a',
    x: 2 + 3,
    fill: brandColor,
    children: [Sparkle('s')],
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

Color _randomColor(Random r) => Color(r.nextInt(0xFFFFFFFF) + 1);

int _counter = 0;

SceneNode _randomNode(Random r, int depth) {
  var name = 'n${_counter++}';
  SceneNode node;
  switch (depth < 3 ? r.nextInt(4) : 1 + r.nextInt(3)) {
    case 0:
      var frame = FrameNode(name)
        ..layout = NodeLayout.values[r.nextInt(3)]
        ..gap = _randomDouble(r).abs()
        ..padding = r.nextBool() ? 0 : _randomDouble(r).abs()
        ..mainAlign = MainAxisAlignment.values[r.nextInt(4)]
        ..crossAlign = CrossAxisAlignment.values[r.nextInt(4)];
      for (var i = 0; i < r.nextInt(5); i++) {
        frame.children.add(_randomNode(r, depth + 1));
      }
      node = frame;
    case 1:
      node = TextNode(name, _randomString(r))
        ..fontSize = 8 + _randomDouble(r).abs() % 90
        ..weight = FontWeight.values[r.nextInt(9)]
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
  return SceneDocument(root);
}
