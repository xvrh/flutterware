import 'dart:convert';

import 'package:flutterware/channels.dart';
import 'package:test/test.dart';

void main() {
  late InspectorCore core;
  late VmServiceTransport transport;
  late List<String> nudges;

  setUp(() {
    core = InspectorCore(identity: () => const {});
    nudges = [];
    transport = VmServiceTransport(
      core: core,
      postEvent: (kind, data) => nudges.add('${data['peer']}'),
    );
  });

  Future<List<Map<String, Object?>>> call(
    String peer, [
    Map<String, Object?>? frame,
  ]) async {
    var reply = await transport.exchange({
      'peer': peer,
      if (frame != null) 'frame': jsonEncode(frame),
    });
    return [
      for (var frame in reply['frames']! as List)
        (frame as Map).cast<String, Object?>(),
    ];
  }

  Map<String, Object?> request(
    String channel,
    String method, [
    Map<String, Object?> params = const {},
  ]) => {'ch': channel, 't': 'req', 'id': 1, 'm': method, 'p': params};

  test('an attach is answered in-call, with no nudge', () async {
    core.addEvent('feed', {'n': 1});
    var frames = await call('a', request('meta', 'attach'));
    expect(frames.map((f) => f['t']), ['res', 'event', 'event']);
    expect(nudges, isEmpty, reason: 'the call itself carried the answer');
  });

  test("an event during another peer's call still nudges this peer", () async {
    // The database panel's regression, 2026-08-12: with the in-call
    // suppression global, an event broadcast while an MCP peer's action ran
    // queued silently on the cockpit and was never nudged about — a feed
    // that stays empty until an unrelated re-attach.
    await call('cockpit', request('meta', 'attach'));
    await call('mcp', request('meta', 'attach'));
    core.registerHandler('panel', 'act', (_) {
      core.addEvent('panel/feed', {'n': 1});
      return {'ok': true};
    });

    var mcpReply = await call('mcp', request('panel', 'act'));

    expect(mcpReply.map((f) => f['t']), [
      'event',
      'res',
    ], reason: "the acting peer's call carries its own broadcast and reply");
    expect(nudges, ['cockpit']);
    var cockpitFrames = await call('cockpit');
    expect(cockpitFrames.single['ch'], 'panel/feed');
  });

  test('a nudge is coalesced until the peer drains', () async {
    await call('a', request('meta', 'attach'));
    core.addEvent('feed', {'n': 1});
    core.addEvent('feed', {'n': 2});
    core.addEvent('feed', {'n': 3});
    expect(nudges, ['a'], reason: 'three events, one nudge');

    var frames = await call('a');
    expect(frames, hasLength(3));
    core.addEvent('feed', {'n': 4});
    expect(nudges, ['a', 'a'], reason: 'draining re-arms the nudge');
  });

  test('an async handler answers on a later pull, via a nudge', () async {
    // The schema read's shape: the handler outlives the exchange that
    // delivered the request, so the response has to be nudged about.
    await call('a', request('meta', 'attach'));
    core.registerHandler('db', 'schema', (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return {'tables': []};
    });

    var first = await call('a', request('db', 'schema'));
    expect(first, isEmpty, reason: 'the reply was not ready in the window');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(nudges, ['a']);
    var second = await call('a');
    expect(second.single['t'], 'res');
  });
}
