import 'dart:io';

import 'package:flutterware_app/src/motion/discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A package root with one file in `lib/`, scanned.
MotionScanResult scanOf(String source, {String file = 'screen.dart'}) {
  var root = Directory.systemTemp.createTempSync('motion_scan');
  addTearDown(() => root.deleteSync(recursive: true));
  var target = File(p.join(root.path, 'lib', file));
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(source);
  return MotionScanner(packageRoot: root.path).scan();
}

void main() {
  group('the scan', () {
    test('finds a scope, its values and its targets', () {
      var result = scanOf('''
Widget build(BuildContext context) => MotionScope(
  motion: inboxMotion,
  builder: (m) {
    var title = m.target('title');
    var cta = m.target('cta');
    return Column(children: [
      Opacity(opacity: title.opacity, child: Text('hi')),
      FilledButton(style: style(cta.color), onPressed: go, child: label),
    ]);
  },
);
''');

      expect(result.diagnostics, isEmpty);
      var motion = result.motions.single;
      expect(motion.values, 'inboxMotion');
      expect(motion.file, 'lib/screen.dart');
      expect(motion.line, 1);
      expect(motion.targets.map((t) => t.name), ['title', 'cta']);
      expect(motion.targets.first.properties, ['opacity']);
      expect(motion.targets.last.properties, ['color']);
    });

    test('reads the builder parameter rather than assuming it is m', () {
      // The convention is `m`. The rule is "whatever the closure called it",
      // and reading the convention instead would quietly find nothing.
      var result = scanOf('''
var w = MotionScope(
  motion: values,
  builder: (motion) {
    var title = motion.target('title');
    return Opacity(opacity: title.opacity, child: child);
  },
);
''');
      expect(result.motions.single.targets.single.name, 'title');
      expect(result.motions.single.targets.single.properties, ['opacity']);
    });

    test('a MotionBox is recorded as wiring, not as nothing', () {
      // Without this the scan disagrees with the runtime on the commonest way
      // to use the API: a box reads nothing here and eight things at run time.
      var result = scanOf('''
var w = MotionScope(
  motion: values,
  builder: (m) {
    var title = m.target('title');
    return MotionBox(title, child: Text('hi'));
  },
);
''');
      var target = result.motions.single.targets.single;
      expect(target.boxed, isTrue);
      expect(target.properties, isEmpty);
    });

    test('an inline read needs no local', () {
      var result = scanOf('''
var w = MotionScope(
  motion: values,
  builder: (m) => Opacity(
    opacity: m.target('title').opacity,
    child: MotionBox(m.target('cta'), child: button),
  ),
);
''');
      var targets = result.motions.single.targets;
      expect(targets.map((t) => t.name), containsAll(['title', 'cta']));
      expect(targets.firstWhere((t) => t.name == 'title').properties, [
        'opacity',
      ]);
      expect(targets.firstWhere((t) => t.name == 'cta').boxed, isTrue);
    });

    test('one target read twice is one target', () {
      var result = scanOf('''
var w = MotionScope(
  motion: values,
  builder: (m) {
    var a = m.target('title');
    var b = m.target('title');
    return Row(children: [Opacity(opacity: a.opacity, child: x), scale(b.scale)]);
  },
);
''');
      var target = result.motions.single.targets.single;
      expect(target.name, 'title');
      expect(target.properties, ['opacity', 'scale']);
    });

    test('a name outside the vocabulary is not a property', () {
      // A local holding a target is an ordinary object. `title.name` is a real
      // getter and `title.hashCode` is not a typo, so neither is a lane.
      var result = scanOf(r'''
var w = MotionScope(
  motion: values,
  builder: (m) {
    var title = m.target('title');
    print('${title.name} ${title.hashCode}');
    return Opacity(opacity: title.opacity, child: x);
  },
);
''');
      expect(result.motions.single.targets.single.properties, ['opacity']);
    });

    test('a computed target name is listed as a diagnostic, not guessed', () {
      var result = scanOf(r'''
var w = MotionScope(
  motion: values,
  builder: (m) {
    var row = m.target('row$index');
    return MotionBox(row, child: x);
  },
);
''');
      expect(result.motions.single.targets, isEmpty);
      expect(result.diagnostics.single, contains('not a string literal'));
    });

    test('a computed motion argument still lists the scope', () {
      var result = scanOf('''
var w = MotionScope(
  motion: pickValues(flavour),
  builder: (m) => MotionBox(m.target('title'), child: x),
);
''');
      var motion = result.motions.single;
      expect(motion.values, isNull);
      expect(motion.targets.single.name, 'title');
      expect(result.diagnostics.single, contains('not a plain identifier'));
    });

    test('two scopes on one const are reported as ambiguous', () {
      var result = scanOf('''
var a = MotionScope(motion: shared, builder: (m) => x);
var b = MotionScope(motion: shared, builder: (m) => y);
''');
      expect(result.motions, hasLength(2));
      expect(result.diagnostics.single, contains('is scoped 2 times'));
    });

    test('two scopes in one file are two motions', () {
      var result = scanOf('''
var a = MotionScope(motion: first, builder: (m) => MotionBox(m.target('a'), child: x));
var b = MotionScope(motion: second, builder: (m) => MotionBox(m.target('b'), child: y));
''');
      expect(result.motions.map((m) => m.values), ['first', 'second']);
      expect(result.motions.map((m) => m.targets.single.name), ['a', 'b']);
      expect(result.diagnostics, isEmpty);
    });

    test('a file with no scope costs nothing and yields nothing', () {
      expect(scanOf('var x = 1;').motions, isEmpty);
    });
  });

  group('against the real demos', () {
    // Synthetic sources prove the visitor; these prove it against code nobody
    // wrote to be parsed. The first version of this scanner passed every test
    // above and found nothing at all here, because unresolved a widget
    // constructor is a `MethodInvocation` and it only looked for constructions.
    test('finds both motions, their values and their wiring', () {
      var demos = _findDemos();
      if (demos == null) return; // Not in a checkout; nothing to check against.
      var result = MotionScanner(
        packageRoot: demos.$1,
        directory: demos.$2,
      ).scan();

      var byValues = {for (var motion in result.motions) motion.values: motion};
      expect(byValues.keys, containsAll(['receiptMotion', 'playerMotion']));

      var receipt = byValues['receiptMotion']!;
      expect(receipt.targets.map((t) => t.name), [
        'scrim',
        'badge',
        'ring',
        'title',
        'card',
        'total',
        'cta',
      ]);

      // The receipt mixes both halves of the API, so the scan sees both: a
      // target wearing a box *and* reading a property the box does not apply.
      var title = receipt.targets.firstWhere((t) => t.name == 'title');
      expect(title.boxed, isTrue);
      expect(title.properties, ['fontSize']);

      var card = receipt.targets.firstWhere((t) => t.name == 'card');
      expect(card.boxed, isTrue);
      expect(card.properties, ['borderRadius', 'elevation']);

      // And one that is read and never boxed.
      var scrim = receipt.targets.firstWhere((t) => t.name == 'scrim');
      expect(scrim.boxed, isFalse);
      expect(scrim.properties, ['blur', 'opacity']);

      // Reads written in the builder and passed down are visible. The player
      // hands whole targets to helper widgets instead, and several of its seven
      // show nothing here while being fully wired at run time. Both are legal;
      // only one is scannable, which is why the receipt is the demo to copy.
      var player = byValues['playerMotion']!;
      expect(player.targets.every((t) => !t.boxed), isTrue);
      expect(
        player.targets.where((t) => t.properties.isEmpty).length,
        greaterThan(3),
      );

      expect(result.diagnostics, isEmpty);
    });
  });
}

/// `(packageRoot, directory)` for the catalog demos, found by walking up from
/// wherever the runner happens to have started.
(String, String)? _findDemos() {
  const relative = 'tool/catalog/demos';
  for (var dir = Directory.current; ; dir = dir.parent) {
    for (var root in [dir.path, p.join(dir.path, 'app')]) {
      if (Directory(p.join(root, relative)).existsSync()) {
        return (root, relative);
      }
    }
    if (dir.parent.path == dir.path) return null;
  }
}
