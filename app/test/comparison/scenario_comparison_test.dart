import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/scenario_alignment.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:test/test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

/// One scenario's two runs, compared: the alignment on top, the channels
/// underneath, and pass/fail outranking both.
void main() {
  Uint8List frame(int value) =>
      Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, value);

  ScenarioStepShot shot(
    int index, {
    String? name,
    String? verb,
    String? target,
    int? parent,
    String? branch,
    String? position,
    int pixels = 0,
    List<String> texts = const [],
    List<Map<String, Object?>> events = const [],
    String? failure,
    String? description,
  }) => ScenarioStepShot(
    step: AlignableStep(
      index: index,
      position: position ?? '#$index',
      parent: parent,
      branch: branch,
      name: name,
      verb: verb,
      target: target,
    ),
    rgba: frame(pixels),
    width: 8,
    height: 8,
    tree: InspectNode(
      id: '',
      type: 'Screen',
      description: description,
      createdByLocalProject: true,
      children: const [],
    ),
    texts: texts,
    events: events,
    failure: failure,
  );

  ScenarioComparison compare(
    List<ScenarioStepShot> base,
    List<ScenarioStepShot> head,
  ) => ScenarioComparison.of(
    scenario: 'test/checkout.dart#Checkout',
    base: base,
    head: head,
  );

  test('two identical runs say nothing changed', () {
    var run = [shot(1, name: 'Cart'), shot(2, name: 'Pay', parent: 1)];

    var result = compare(run, run);

    expect(result.state, ComparedState.same);
    expect(result.items.every((i) => i.state == ComparedState.same), isTrue);
  });

  test('a step whose picture moved is the one row that changed', () {
    var base = [shot(1, name: 'Cart'), shot(2, name: 'Pay', parent: 1)];
    var head = [
      shot(1, name: 'Cart'),
      shot(2, name: 'Pay', parent: 1, pixels: 255),
    ];

    var result = compare(base, head);

    expect(result.state, ComparedState.changed);
    expect(result.items.first.state, ComparedState.same);
    expect(result.items.last.state, ComparedState.changed);
  });

  test('an inserted step is added, and the rest still match', () {
    var base = [shot(1, name: 'Cart'), shot(2, name: 'Pay', parent: 1)];
    var head = [
      shot(1, name: 'Cart'),
      shot(2, name: 'Consent', parent: 1),
      shot(3, name: 'Pay', parent: 2),
    ];

    var result = compare(base, head);

    expect(result.items.map((i) => '${i.id}:${i.state.name}'), [
      'Cart:same',
      'Consent:added',
      'Pay:same',
    ]);
  });

  // `added` outranks `changed`, so carrying a step's own word up sorted a flow
  // that gained one line above a flow that genuinely came out different — and
  // called a scenario that has existed for months new.
  test('a scenario that gained a step changed, it was not added', () {
    var result = compare(
      [shot(1, name: 'Cart')],
      [shot(1, name: 'Cart'), shot(2, name: 'Pay', parent: 1)],
    );

    expect(result.items.last.state, ComparedState.added);
    expect(result.state, ComparedState.changed);
  });

  // A new split branch is one decision in the source; listing its steps as N
  // additions describes that decision N times.
  test('a branch that appeared is a row of its own, not N rows', () {
    var base = [
      shot(1, name: 'Cart'),
      shot(2, name: 'Address', parent: 1, branch: 'guest', position: '0#1'),
    ];
    var head = [
      ...base,
      shot(3, name: 'Sheet', parent: 1, branch: 'apple pay', position: '1#1'),
      shot(4, name: 'Done', parent: 3, position: '1#2'),
    ];

    var result = compare(base, head);

    expect(result.branches, hasLength(1));
    expect(result.branches.single.label, 'apple pay');
    expect(result.branches.single.steps, 2);
    expect(result.state, ComparedState.changed);
    expect(result.items.every((i) => i.state == ComparedState.same), isTrue);
  });

  group('the channels', () {
    test('the tree explains a step whose pixels moved', () {
      var base = [shot(1, name: 'Cart', description: 'Text("Save")')];
      var head = [
        shot(1, name: 'Cart', pixels: 255, description: 'Text("Pay")'),
      ];

      var result = compare(base, head);

      expect(result.items.single.tree!.diff.deltas.single.head, 'Text("Pay")');
    });

    // The channel that catches what no picture can: a duplicated request, a
    // new analytics call, an N+1 that appeared.
    test('an extra request is a change with no changed pixel', () {
      var base = [
        shot(
          1,
          name: 'Cart',
          events: [
            {'channel': 'network', 'title': 'GET /cart'},
          ],
        ),
      ];
      var head = [
        shot(
          1,
          name: 'Cart',
          events: [
            {'channel': 'network', 'title': 'GET /cart'},
            {'channel': 'network', 'title': 'GET /cart'},
          ],
        ),
      ];

      var result = compare(base, head);

      expect(result.items.single.state, ComparedState.changed);
      expect(result.items.single.events!.added, ['network GET /cart']);
      expect(result.items.single.pixels!.changed, isFalse);
    });

    // An id in a path is the commonest way a run differs from itself for no
    // reason at all.
    test('an id in a url is masked away', () {
      List<Map<String, Object?>> events(String url) => [
        {'channel': 'network', 'title': 'GET $url'},
      ];

      var result = compare(
        [shot(1, name: 'Cart', events: events('/order/8814'))],
        [shot(1, name: 'Cart', events: events('/order/9921'))],
      );

      expect(result.items.single.state, ComparedState.same);
    });

    test('a request that was not made before is named', () {
      var result = compare(
        [shot(1, name: 'Cart')],
        [
          shot(
            1,
            name: 'Cart',
            events: [
              {'channel': 'analytics', 'title': 'checkout_started'},
            ],
          ),
        ],
      );

      expect(result.items.single.events!.added, ['analytics checkout_started']);
    });

    test('texts carry a finding on their own', () {
      var result = compare(
        [
          shot(1, name: 'Cart', texts: ['Save']),
        ],
        [
          shot(1, name: 'Cart', texts: ['Pay']),
        ],
      );

      expect(result.items.single.texts!.added, ['Pay']);
    });
  });

  group('failure outranks everything', () {
    test('a scenario that stopped completing is the verdict', () {
      var base = [shot(1, name: 'Cart'), shot(2, name: 'Pay', parent: 1)];
      var head = [
        shot(1, name: 'Cart'),
        shot(2, name: 'Pay', parent: 1, failure: 'nothing matches "Pay"'),
      ];

      var result = compare(base, head);

      expect(result.state, ComparedState.broke);
      expect(result.items.last.note, contains('nothing matches'));
      expect(result.items.last.pixels, isNull);
    });

    test('a step that already failed on base says so quietly', () {
      var result = compare(
        [shot(1, name: 'Cart', failure: 'boom')],
        [shot(1, name: 'Cart')],
      );

      expect(result.state, ComparedState.wasBroken);
    });
  });

  // Two identical pictures are the *reason* a retarget is worth saying, not a
  // reason to stay quiet: the same step now names something else.
  test('a retargeted step is reported even when nothing moved', () {
    var result = compare(
      [shot(1, verb: 'tap', target: "key 'pay'")],
      [shot(1, verb: 'tap', target: "key 'pay_now'")],
    );

    expect(result.items.single.state, ComparedState.changed);
    expect(result.items.single.note, contains("key 'pay' → key 'pay_now'"));
  });

  test('the json carries the steps, the branches and the verdict', () {
    var base = [shot(1, name: 'Cart')];
    var head = [
      shot(1, name: 'Cart'),
      shot(2, name: 'Extra', parent: 1, branch: 'new', position: '0#1'),
    ];

    var json = compare(base, head).toJson();

    expect(json['id'], 'test/checkout.dart#Checkout');
    expect(json['state'], 'changed');
    expect((json['branches']! as List).single, containsPair('label', 'new'));
    expect(json['steps']! as List, hasLength(1));
  });
}
