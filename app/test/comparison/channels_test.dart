import 'dart:typed_data';

import 'package:flutterware/app_events.dart';
import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/pixel_diff.dart';
import 'package:flutterware_app/src/comparison/tree_diff.dart';
import 'package:test/test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

/// One thing compared on every channel that had something to say, and the
/// verdict that comes out of them.
void main() {
  Uint8List frame(int value) => Uint8List(4 * 4 * 4)..fillRange(0, 64, value);

  PixelDiff pixels({int base = 0, int head = 0}) => PixelDiff.of(
    base: frame(base),
    baseWidth: 4,
    baseHeight: 4,
    head: frame(head),
    headWidth: 4,
    headHeight: 4,
  );

  InspectNode node(String type, {String? description}) => InspectNode(
    id: '',
    type: type,
    description: description,
    createdByLocalProject: true,
    children: const [],
  );

  test('nothing on any channel is the same picture', () {
    var item = ComparedItem.of(id: 'a#b', pixels: pixels());

    expect(item.state, ComparedState.same);
    expect(item.texts, isNull);
  });

  test('a changed channel is enough to make the item changed', () {
    var item = ComparedItem.of(id: 'a#b', pixels: pixels(head: 255));

    expect(item.state, ComparedState.changed);
    expect(item.toJson()['channels'], isA<Map<String, Object?>>());
  });

  // The text channel costs nothing and is the most legible one in a terminal:
  // pixels can only say what fraction of the screen moved.
  test('text alone can carry the finding', () {
    var item = ComparedItem.of(
      id: 'a#b',
      pixels: pixels(),
      baseTexts: ['Save'],
      headTexts: ['Pay'],
    );

    expect(item.state, ComparedState.changed);
    expect(item.texts!.added, ['Pay']);
    expect(item.texts!.removed, ['Save']);
  });

  // A list gaining a second "Buy" is a change, and two sets would call it
  // nothing.
  test('a repeated text is counted, not deduplicated', () {
    var channel = TextChannel.of(base: ['Buy'], head: ['Buy', 'Buy']);

    expect(channel.added, ['Buy']);
    expect(channel.removed, isEmpty);
  });

  test('a reordered text list is not a change', () {
    var channel = TextChannel.of(base: ['A', 'B'], head: ['B', 'A']);

    expect(channel.changed, isFalse);
  });

  // A tree that differs only below a resized ancestor has not changed;
  // something above it did, and that is already reported.
  test('a tree of nothing but shifts is not itself a change', () {
    var channel = TreeChannel(
      const TreeDiff([
        TreeDelta(
          kind: TreeDeltaKind.shifted,
          path: 'Column › Text',
          property: 'offset',
          base: '0,20',
          head: '0,44',
        ),
      ]),
    );

    expect(channel.changed, isFalse);
  });

  test('a tree delta alone can carry the finding', () {
    var item = ComparedItem.of(
      id: 'a#b',
      pixels: pixels(),
      tree: TreeDiff.of(
        node('Text', description: 'Text("Save")'),
        node('Text', description: 'Text("Pay")'),
      ),
    );

    expect(item.state, ComparedState.changed);
  });

  group('the severity ladder', () {
    // The one result the tool exists to catch: a percentage next to it would
    // be answering a smaller question.
    test('a head that stopped rendering outranks everything', () {
      var item = ComparedItem.of(
        id: 'a#b',
        headRendered: false,
        pixels: pixels(head: 255),
      );

      expect(item.state, ComparedState.broke);
      expect(item.note, contains('throws here'));
      expect(item.pixels, isNull);
    });

    test('a base that never rendered is said once, quietly', () {
      var item = ComparedItem.of(id: 'a#b', baseRendered: false);

      expect(item.state, ComparedState.wasBroken);
      expect(item.note, contains('already broken'));
    });

    test('neither side rendering is its own state', () {
      var item = ComparedItem.of(
        id: 'a#b',
        baseRendered: false,
        headRendered: false,
      );

      expect(item.state, ComparedState.failed);
    });

    test('the states are declared worst-first, so a sort is a ranking', () {
      expect(
        ComparedState.broke.index,
        lessThan(ComparedState.wasBroken.index),
      );
      expect(ComparedState.changed.index, lessThan(ComparedState.same.index));
      expect(ComparedState.same.index, lessThan(ComparedState.skipped.index));
    });
  });

  test('the json says the state, and the channels when there are any', () {
    var json = ComparedItem.of(
      id: 'demo/card.dart#card',
      label: 'Card',
      pixels: pixels(head: 255),
      baseTexts: ['Save'],
      headTexts: ['Pay'],
    ).toJson();

    expect(json['id'], 'demo/card.dart#card');
    expect(json['state'], 'changed');
    expect(json['label'], 'Card');
    var channels = json['channels']! as Map<String, Object?>;
    expect(channels['pixels'], isNotNull);
    expect(channels['texts'], isNotNull);
    expect(channels.containsKey('tree'), isFalse);
  });

  group('db events are told apart by their statement', () {
    /// Two different statements, both formatted the way a person formats
    /// them: the keyword alone on the first line.
    AppEvent tasks() => AppEvent.query(
      sql:
          'select\n  t.*,\n  count(te.id)\nfrom task as t\nwhere t.done is null',
    );
    AppEvent users() =>
        AppEvent.query(sql: 'select\n  u.id,\n  u.email\nfrom users as u');

    test('a branch that swapped one query for another says so', () {
      // `mask` keys an event on its channel and its title. While `AppEvent
      // .query` titled from the first line, both of these were `db select …`
      // — one key — and this diff came back empty: a silent false negative,
      // on the channel whose entire job is to notice.
      var diff = EventChannel.of(
        base: [tasks().toJson()],
        head: [users().toJson()],
      );

      expect(diff.added, hasLength(1));
      expect(diff.removed, hasLength(1));
      expect(diff.added.single, contains('users'));
      expect(diff.removed.single, contains('task'));
    });

    test('the same query on both sides is still no change', () {
      var diff = EventChannel.of(
        base: [tasks().toJson()],
        head: [tasks().toJson()],
      );

      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
    });

    test('an N+1 sibling still meets its twin, because digits fold', () {
      // Folding whitespace keeps the literals, so grouping leans on `mask`'s
      // digits-to-`#` rule exactly as it did before — the queries of an N+1
      // differ precisely in an id, and must not read as a change.
      var diff = EventChannel.of(
        base: [AppEvent.query(sql: 'select * from t\nwhere id = 1').toJson()],
        head: [AppEvent.query(sql: 'select * from t\nwhere id = 2').toJson()],
      );

      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
    });
  });
}
