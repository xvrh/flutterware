import 'dart:convert';

import 'package:flutterware/src/inspect/error.dart';
import 'package:flutterware/src/inspect/node.dart';
import 'package:test/test.dart';

/// The wire format, which is the half of inspection that needs no guest.
///
/// Worth its own tests because the one defect that took a whole read down was
/// here rather than in the walk: `jsonEncode` throws on `double.infinity`, and
/// an unbounded `maxWidth` is what most of a real tree is laid out under. A
/// live check caught it only because somebody ran it; this catches it in
/// milliseconds, on every push, without an SDK or a GPU.
void main() {
  group('InspectSource', () {
    test('prints a file URI as a path relative to the worktree', () {
      var source = const InspectSource(
        file: 'file:///repo/app/demo/tile.dart',
        line: 12,
        column: 5,
      );
      expect(source.describe(relativeTo: '/repo'), 'app/demo/tile.dart:12:5');
    });

    test('leaves a path outside the worktree absolute', () {
      var source = const InspectSource(
        file: 'file:///sdk/flutter/widgets.dart',
        line: 1,
        column: 1,
      );
      expect(
        source.describe(relativeTo: '/repo'),
        '/sdk/flutter/widgets.dart:1:1',
      );
    });
  });

  group('InspectConstraints', () {
    test('an unbounded edge survives jsonEncode', () {
      var constraints = const InspectConstraints(
        minWidth: 0,
        maxWidth: double.infinity,
        minHeight: 0,
        maxHeight: 700,
      );
      // The assertion is that this does not throw. It did.
      var encoded = jsonEncode(constraints.toJson());
      expect(encoded, contains('"maxWidth":null'));
    });

    test('and comes back unbounded rather than zero', () {
      var round = InspectConstraints.fromJson(
        jsonDecode(
              jsonEncode(
                const InspectConstraints(
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 8,
                  maxHeight: double.infinity,
                ).toJson(),
              ),
            )
            as Map<String, Object?>,
      );
      expect(round.maxWidth, double.infinity);
      expect(round.maxHeight, double.infinity);
      expect(round.minHeight, 8);
    });

    test('describes infinity as something a terminal can print', () {
      expect(
        const InspectConstraints(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: 700,
        ).describe(),
        'w 0.0..∞, h 0.0..700.0',
      );
    });
  });

  group('InspectLayout', () {
    test('a non-finite size does not take the encode down', () {
      var layout = const InspectLayout(
        x: 0,
        y: double.nan,
        width: double.infinity,
        height: 40,
      );
      expect(() => jsonEncode(layout.toJson()), returnsNormally);
    });

    test('carries flex both ways round', () {
      var round = InspectLayout.fromJson(
        jsonDecode(
              jsonEncode(
                const InspectLayout(
                  x: 1,
                  y: 2,
                  width: 3,
                  height: 4,
                  flex: InspectFlex(
                    direction: 'horizontal',
                    mainAxisAlignment: 'start',
                  ),
                  flexFactor: 2,
                  flexFit: 'tight',
                ).toJson(),
              ),
            )
            as Map<String, Object?>,
      );
      expect(round.flex?.direction, 'horizontal');
      expect(round.flexFactor, 2);
      expect(round.flexFit, 'tight');
    });
  });

  group('InspectTree', () {
    var tree = InspectTree(
      entryId: 'demo/a.dart#a',
      root: const InspectNode(
        id: '',
        type: 'Column',
        children: [
          InspectNode(id: '0', type: 'Padding'),
          InspectNode(
            id: '1',
            type: 'Row',
            children: [InspectNode(id: '1/0', type: 'Text')],
          ),
        ],
      ),
    );

    test('walks depth first, root included', () {
      expect([for (var node in tree.nodes) node.id], ['', '0', '1', '1/0']);
    });

    test('resolves a node by its id', () {
      expect(tree.nodeAt('1/0')?.type, 'Text');
    });

    test('answers null for an id that no longer names anything', () {
      // Deliberately not a nearest match: a caller that edited the demo
      // between two reads is asking about a position that may now hold
      // something else, and answering with whatever moved into it would be a
      // confident wrong answer.
      expect(tree.nodeAt('1/9'), isNull);
    });

    test('an unbuilt entry is an empty answer, not a broken one', () {
      var empty = InspectTree.fromJson(
        const InspectTree(entryId: 'x', root: null).toJson(),
      );
      expect(empty.root, isNull);
      expect(empty.nodes, isEmpty);
      expect(empty.entryId, 'x');
    });

    test('survives a round trip whole', () {
      var round = InspectTree.fromJson(
        jsonDecode(jsonEncode(tree.toJson())) as Map<String, Object?>,
      );
      expect([for (var n in round.nodes) n.id], ['', '0', '1', '1/0']);
      expect(round.entryId, 'demo/a.dart#a');
    });
  });

  group('InspectError', () {
    test('two reports of one fault share a key', () {
      const a = InspectError(
        exception: 'overflowed by 4 pixels',
        library: 'rendering library',
        context: 'during layout',
      );
      const b = InspectError(
        exception: 'overflowed by 4 pixels',
        library: 'rendering library',
        // Deliberately different: the same overflow reported during layout and
        // while painting is one bug.
        context: 'while painting',
      );
      expect(a.key, b.key);
    });

    test('a count of one is left off the wire', () {
      expect(
        const InspectError(exception: 'x').toJson().containsKey('count'),
        isFalse,
      );
      expect(const InspectError(exception: 'x', count: 7).toJson()['count'], 7);
    });

    test('an entry with nothing to say is empty rather than absent', () {
      var report = InspectErrors.fromJson(
        const InspectErrors(entryId: 'x', errors: []).toJson(),
      );
      expect(report.isEmpty, isTrue);
      expect(report.entryId, 'x');
    });
  });
}
