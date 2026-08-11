import 'package:flutterware/channels.dart';
import 'package:test/test.dart';

/// A peer that keeps what it was sent.
class _Peer implements InspectorPeer {
  final frames = <Map<String, Object?>>[];

  @override
  void send(Map<String, Object?> frame) => frames.add(frame);

  @override
  void close() {}
}

void main() {
  late InspectorCore core;
  late Panels panels;

  setUp(() {
    core = InspectorCore(identity: () => const {});
    panels = Panels(core);
  });

  Future<Object?> call(
    String channel,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    var peer = _Peer();
    core.handleFrame(peer, {
      'ch': channel,
      't': 'req',
      'id': 1,
      'm': method,
      'p': params,
    });
    await Future<void>.delayed(Duration.zero);
    var frame = peer.frames.single;
    if (frame['t'] == 'err') {
      throw StateError('${(frame['p']! as Map)['message']}');
    }
    return frame['p'];
  }

  test('a panel describes only what it can answer', () async {
    var panel = panels.add('network', 'Network', description: 'HTTP traffic');
    panel.feed(
      'requests',
      'Requests',
      durationKey: 'ms',
      fields: const [
        FieldDescriptor('path', 'Path', primary: true),
        FieldDescriptor('ms', 'Time', kind: FieldKind.duration),
      ],
    );
    panel.itemAction(
      'requests',
      const PluginAction('curl', 'Copy as curl'),
      (args) => {'event': args['event']},
    );
    panel.state('config', 'Config', read: () => {'baseUrl': 'https://x'});
    panel.knob(
      const KnobDescriptor(
        name: 'verbose',
        kind: KnobKind.boolean,
        value: false,
        defaultValue: false,
      ),
      read: () => false,
      write: (_) {},
    );
    panel.action(const PluginAction('clear', 'Clear'), (_) => null);

    var json = panel.descriptor.toJson();
    var decoded = PanelDescriptor.fromJson(json);

    expect(decoded.id, 'network');
    expect(decoded.description, 'HTTP traffic');
    expect(decoded.feeds.single.durationKey, 'ms');
    expect(decoded.feeds.single.fields.first.primary, isTrue);
    expect(decoded.feeds.single.fields.last.kind, FieldKind.duration);
    expect(decoded.feeds.single.itemActions.single.id, 'curl');
    expect(decoded.states.single.id, 'config');
    expect(decoded.knobs.single.name, 'verbose');
    expect(decoded.actions.single.label, 'Clear');
    // Round-tripped, not just built: this shape crosses a wire.
    expect(decoded.toJson(), json);
  });

  test('panels/list answers with every panel', () async {
    panels.add('a', 'A').feed('f', 'F');
    panels.add('b', 'B');

    var reply = (await call(panelsChannel, panelsList))! as Map;
    expect(
      [for (var p in reply['panels']! as List) (p as Map)['id']],
      ['a', 'b'],
    );
  });

  test('a feed emits on its own qualified channel', () async {
    var one = panels.add('one', 'One')..feed('requests', 'R');
    var two = panels.add('two', 'Two')..feed('requests', 'R');

    one.emit('requests', {'path': '/one'});
    two.emit('requests', {'path': '/two'});

    var peer = _Peer();
    core.attach(peer, 1);
    var feedEvents = [
      for (var frame in peer.frames)
        if (frame['t'] == 'event' && '${frame['ch']}'.contains('/')) frame,
    ];
    expect(feedEvents.map((e) => e['ch']), ['one/requests', 'two/requests']);
    expect(feedEvents.map((e) => (e['p']! as Map)['path']), ['/one', '/two']);
    expect(panelFeedChannel('one', 'requests'), 'one/requests');
  });

  test('emitting on an undeclared feed is refused, not dropped', () {
    var panel = panels.add('p', 'P')..feed('known', 'Known');
    expect(
      () => panel.emit('typo', const {}),
      throwsA(
        isA<ArgumentError>().having((e) => '$e', 'message', contains('known')),
      ),
    );
  });

  test(
    'a knob reports what it currently is, not what it was declared',
    () async {
      var value = 3;
      panels
          .add('p', 'P')
          .knob(
            const KnobDescriptor(
              name: 'retries',
              kind: KnobKind.integer,
              value: 0,
              defaultValue: 1,
              min: 0,
              max: 10,
              step: 1,
            ),
            read: () => value,
            write: (v) => value = v! as int,
          );

      var read = (await call('p', panelKnobsMethod))! as Map;
      var knob = KnobDescriptor.fromJson(
        ((read['knobs']! as List).single as Map).cast<String, Object?>(),
      );
      expect(knob.value, 3, reason: 'the live value, not the declared 0');
      expect(knob.defaultValue, 1);
      expect(knob.step, 1);
    },
  );

  test(
    'setting a knob answers with what the app kept, not what was asked',
    () async {
      var value = 5;
      panels
          .add('p', 'P')
          .knob(
            const KnobDescriptor(
              name: 'volume',
              kind: KnobKind.integer,
              value: 5,
              defaultValue: 5,
              min: 0,
              max: 10,
            ),
            read: () => value,
            // An app is allowed to clamp.
            write: (v) => value = (v! as int).clamp(0, 10),
          );

      var reply =
          (await call('p', panelSetKnobMethod, {'id': 'volume', 'value': 99}))!
              as Map;
      var knob = (reply['knobs']! as List).single as Map;

      expect(knob['value'], 10);
      expect(value, 10);
    },
  );

  test('an unknown knob or state is refused with what exists', () async {
    panels.add('p', 'P').state('real', 'Real', read: () => const {});

    await expectLater(
      call('p', panelStateMethod, {'id': 'ghost'}),
      throwsA(
        isA<StateError>().having((e) => '$e', 'message', contains('real')),
      ),
    );
    await expectLater(
      call('p', panelSetKnobMethod, {'id': 'ghost', 'value': 1}),
      throwsA(isA<StateError>()),
    );
  });

  test('an action runs in the app and its result comes back', () async {
    Map<String, Object?>? seen;
    panels.add('notify', 'Notify').action(
      const PluginAction(
        'send',
        'Send',
        parameters: [
          ActionParameter('title', 'Title'),
          ActionParameter('link', 'Link', required: false),
        ],
      ),
      (args) {
        seen = args;
        return {'sent': true};
      },
    );

    var reply = await call('notify', 'send', {'title': 'Hi', 'link': 'x://y'});

    expect(reply, {'sent': true});
    expect(seen, {'title': 'Hi', 'link': 'x://y'});
  });

  test('two actions cannot claim one method', () {
    var panel = panels.add('p', 'P')..feed('f', 'F');
    panel.action(const PluginAction('go', 'Go'), (_) => null);

    expect(
      () => panel.action(const PluginAction('go', 'Again'), (_) => null),
      throwsArgumentError,
    );
    expect(
      () => panel.itemAction('f', const PluginAction('go', 'Go'), (_) => null),
      throwsArgumentError,
      reason: 'an item action shares the method namespace with panel actions',
    );
  });

  test('removing a panel takes its handlers with it', () async {
    panels.add('p', 'P').action(const PluginAction('go', 'Go'), (_) => null);
    expect(await call('p', 'go'), isNotNull);

    panels.remove('p');

    await expectLater(
      call('p', 'go'),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'message',
          contains('no handler'),
        ),
      ),
    );
    expect(core.channels, isNot(contains('p')));
  });

  test(
    're-adding a panel replaces it rather than half-installing a second',
    () async {
      panels
          .add('p', 'P')
          .action(const PluginAction('old', 'Old'), (_) => null);
      panels
          .add('p', 'P')
          .action(const PluginAction('new', 'New'), (_) => null);

      expect(panels.descriptors.single.actions.map((a) => a.id), ['new']);
      await expectLater(call('p', 'old'), throwsA(isA<StateError>()));
      expect(await call('p', 'new'), isNotNull);
    },
  );

  test('every change announces itself on the panels channel', () async {
    var peer = _Peer();
    core.attach(peer, 1);
    var before = peer.frames.length;

    var panel = panels.add('p', 'P');
    panel.feed('f', 'F');
    panel.action(const PluginAction('go', 'Go'), (_) => null);
    panels.remove('p');

    var announced = [
      for (var frame in peer.frames.skip(before))
        if (frame['ch'] == panelsChannel) frame,
    ];
    expect(announced, hasLength(4));
    expect((announced.last['p']! as Map)['count'], 0);
  });

  /// The in-app path, for an overlay drawing a panel from its own descriptor.
  ///
  /// The point of these is that there is no *second* implementation to test:
  /// the wire handlers are written in terms of these, so a renderer inside the
  /// app cannot drift from the cockpit by re-deriving what an action does.
  group('in process', () {
    test('reaches the same handlers the wire does', () async {
      var ran = <String, Object?>{};
      var volume = 3;
      var panel = panels.add('p', 'P')
        ..action(const PluginAction('go', 'Go'), (args) {
          ran['go'] = args['n'];
          return {'ok': true};
        })
        ..state('info', 'Info', read: () => {'volume': volume})
        ..knob(
          const KnobDescriptor(
            name: 'volume',
            kind: KnobKind.integer,
            value: 3,
            defaultValue: 3,
            max: 5,
          ),
          read: () => volume,
          // Clamped, so the read-back is provably not an echo.
          write: (value) => volume = (value! as int).clamp(0, 5),
        );

      expect(await panel.run('go', {'n': 1}), {'ok': true});
      expect(ran['go'], 1);
      expect(await panel.readState('info'), {'volume': 3});

      var knobs = await panel.writeKnob('volume', 9);
      expect(volume, 5, reason: 'the app clamped it');
      expect(
        knobs.single.value,
        5,
        reason: 'and the caller is told what it kept',
      );

      // And the wire agrees, because it is the same code underneath.
      expect(await call('p', panelStateMethod, {'id': 'info'}), {'volume': 5});
    });

    test("an item action's handler is reachable too", () async {
      var opened = <int>[];
      var panel = panels.add('p', 'P')..feed('rows', 'Rows');
      panel.itemAction('rows', const PluginAction('open', 'Open'), (args) {
        opened.add(args['event']! as int);
        return null;
      });

      var event = panel.emit('rows', {'a': 1});
      await panel.run('open', {'event': event});

      expect(opened, [event]);
    });

    test('an id nothing declared is refused, and lists what exists', () {
      var panel = panels.add('p', 'P')
        ..action(const PluginAction('go', 'Go'), (_) => null);

      expect(
        () => panel.run('nope'),
        throwsA(isArgumentError.having((e) => '$e', 'message', contains('go'))),
      );
      expect(() => panel.readState('nope'), throwsArgumentError);
      expect(panel.writeKnob('nope', 1), throwsArgumentError);
    });
  });
}
