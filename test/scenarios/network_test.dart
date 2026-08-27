import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/app_events/events.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';
import 'package:http/http.dart' as http;

/// What a scenario's http requests reach, end to end.
///
/// The server is a real one on the loopback interface, because the whole
/// question is whether a socket is reachable from inside FakeAsync — a fake
/// server would answer it by construction and prove nothing.
void main() {
  late HttpServer server;
  late String base;
  var hits = <String>[];
  var captures = <ScenarioStepCapture>[];

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      hits.add('${request.method} ${request.uri.path}');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('image', 'png')
        ..add(scenarioPlaceholderPng(width: 8, height: 8));
      await request.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  setUp(() {
    hits = [];
    captures = [];
    scenarioRunListener = captures.add;
    // The harness's, in a real run. Here the test is the harness.
    appEventBuffer = AppEventBuffer();
  });
  tearDown(() {
    scenarioRunListener = null;
    appEventBuffer = null;
  });

  group('off — the default', () {
    scenario('refuses a request nothing stated, and names it', (s) async {
      await s.pumpWidget(_Blank());
      var refusal = await s.runAsync(() async {
        try {
          await http.get(Uri.parse('$base/api/messages'));
          return 'no refusal';
        } on ScenarioNetworkRefusal catch (error) {
          return '$error';
        }
      });
      expect(refusal, contains(ScenarioNetworkRefusal.short));
      expect(refusal, contains('$base/api/messages'));
      expect(refusal, contains("s.network.get('/api/messages'"));
      expect(hits, isEmpty);
      expect(s.network.requests.single.outcome, 'off');
    });

    scenario('does not hang on https, where flutter_test does', (s) async {
      // Under `flutter_test`'s own mock this url opens a real TLS connection
      // whose timers are armed under FakeAsync and never fire — the step
      // reports a blank frame and nothing else. Here it is answered at once.
      await s.pumpWidget(_Blank());
      var refused = await s.runAsync(() async {
        try {
          await http.get(Uri.parse('https://example.invalid/logo.png'));
          return false;
        } on ScenarioNetworkRefusal {
          return true;
        }
      });
      expect(refused, isTrue);
    });

    // Asserted in a tearDown because a capture is held pending until the body
    // returns — a named step adopts the one before it, and nothing can be
    // adopted after somebody has been handed the picture.
    group('reports the refusal on the step', () {
      scenario('as a network event, marked as an error', (s) async {
        await s.pumpWidget(_Blank());
        await s.runAsync(() async {
          try {
            await http.get(Uri.parse('$base/api/me'));
          } on ScenarioNetworkRefusal {
            // The event is the assertion.
          }
        });
        await s.screen('after');
      });
      tearDown(() {
        var events = captures.expand((c) => c.events).toList();
        var refusal = events.singleWhere(
          (e) => e.channel == AppChannel.network,
        );
        expect(refusal.title, endsWith('/api/me'));
        expect(refusal.error, isTrue);
        expect(refusal.detail, ScenarioNetworkRefusal.short);
        expect(refusal.body, contains('was not made'));
      });
    });
  });

  group('stubs', () {
    scenario('a stated json answer beats the mode', (s) async {
      s.network.get('/api/messages', json: ['one', 'two']);
      await s.pumpWidget(_Blank());
      var body = await s.runAsync(
        () async => (await http.get(Uri.parse('$base/api/messages'))).body,
      );
      expect(jsonDecode(body!), ['one', 'two']);
      expect(hits, isEmpty, reason: 'a stub answers without a socket');
      expect(s.network.requests.single.outcome, 'stub');
      expect(s.network.requests.single.status, 200);
    });

    scenario('a status with no body', (s) async {
      s.network.get('/api/messages', status: 503);
      await s.pumpWidget(_Blank());
      var status = await s.runAsync(
        () async =>
            (await http.get(Uri.parse('$base/api/messages'))).statusCode,
      );
      expect(status, 503);
    });

    scenario('throws: is what an app catches', (s) async {
      s.network.any(throws: const SocketException('Network is unreachable'));
      await s.pumpWidget(_Blank());
      var caught = await s.runAsync(() async {
        try {
          await http.get(Uri.parse('$base/anything'));
          return 'nothing';
        } on SocketException catch (error) {
          return error.message;
        }
      });
      expect(caught, 'Network is unreachable');
    });

    scenario('a fallback never swallows a stub after it', (s) async {
      s.network.any(status: 500);
      s.network.get('/api/me', json: {'name': 'Ada'});
      await s.pumpWidget(_Blank());
      var answers = await s.runAsync(
        () async => [
          (await http.get(Uri.parse('$base/api/me'))).statusCode,
          (await http.get(Uri.parse('$base/api/other'))).statusCode,
        ],
      );
      expect(answers, [200, 500]);
    });

    scenario('re-stating a url changes what it answers from there on', (
      s,
    ) async {
      s.network.get('/api/items', json: []);
      await s.pumpWidget(_Blank());
      var before = await s.runAsync(
        () async => (await http.get(Uri.parse('$base/api/items'))).body,
      );
      s.network.get('/api/items', json: ['new']);
      var after = await s.runAsync(
        () async => (await http.get(Uri.parse('$base/api/items'))).body,
      );
      expect(jsonDecode(before!), isEmpty);
      expect(jsonDecode(after!), ['new']);
    });

    scenario('a path stub does not match by substring', (s) async {
      s.network.get('/api/me', json: {'name': 'Ada'});
      await s.pumpWidget(_Blank());
      var refused = await s.runAsync(() async {
        try {
          await http.get(Uri.parse('$base/api/messages'));
          return false;
        } on ScenarioNetworkRefusal {
          return true;
        }
      });
      expect(refused, isTrue);
    });

    group('a stubbed image decodes and paints', () {
      scenario('with no socket opened', (s) async {
        s.network.image(
          '/avatars/1.png',
          scenarioPlaceholderPng(width: 32, height: 32, red: 0xE0, green: 0x40),
        );
        await s.pumpWidget(_Avatar(url: '$base/avatars/1.png'));
        await s.screen('the avatar');
      });
      tearDown(() {
        expect(captures.last.texts, isNot(contains('ERR')));
        expect(captures.last.landed, isTrue);
        expect(hits, isEmpty);
      });
    });
  });

  group('live', () {
    scenario('reaches a real socket', network: ScenarioNetwork.live, (s) async {
      await s.pumpWidget(_Blank());
      var status = await s.runAsync(
        () async =>
            (await http.get(Uri.parse('$base/api/messages'))).statusCode,
      );
      expect(status, 200);
      expect(hits, ['GET /api/messages']);
      expect(s.network.requests.single.outcome, 'live');
    });

    // The measurement this whole file is about: a request the *widget tree*
    // made — not the body — completing inside the step that mounted it, under
    // fake time, with no extra pumping asked for.
    group('an image the widget tree asked for', () {
      scenario(
        'lands in the step that mounts it',
        network: ScenarioNetwork.live,
        (s) async {
          await s.pumpWidget(_Avatar(url: '$base/avatars/live.png'));
          await s.screen('the avatar');
        },
      );
      tearDown(() {
        expect(hits, ['GET /avatars/live.png']);
        expect(captures.last.texts, isNot(contains('ERR')));
        expect(captures.last.landed, isTrue);
      });
    });

    scenario('a stub still beats the mode', network: ScenarioNetwork.live, (
      s,
    ) async {
      s.network.get('/api/me', json: {'name': 'Ada'});
      await s.pumpWidget(_Blank());
      await s.runAsync(() async {
        await http.get(Uri.parse('$base/api/me'));
        await http.get(Uri.parse('$base/api/other'));
      });
      expect(hits, ['GET /api/other']);
    });
  });

  group('splits', () {
    // A body runs once per path through its splits, from the top. Each path
    // states its own answers, and must not see the ones the path before it
    // stated — nor the requests it made.
    var seen = <String, List<int>>{};
    scenario('each branch states its own answers', (s) async {
      s.network.get('/api/items', status: 200);
      await s.pumpWidget(_Blank());
      await s.split({
        'plenty': () async {
          s.network.get('/api/items', json: ['a', 'b']);
          seen['plenty'] = await _statuses(s, base);
        },
        'nothing': () async {
          // States nothing of its own past the prefix, so the prefix's 200
          // stands and the branch before it is nowhere.
          seen['nothing'] = await _statuses(s, base);
        },
      });
    });
    tearDown(() {
      expect(seen['plenty'], [200]);
      expect(seen['nothing'], [200]);
    });
  });

  group('the shape of the funnel', () {
    scenario('an app that builds its own client goes through it too', (
      s,
    ) async {
      s.network.get('/api/me', json: {'name': 'Ada'});
      // Built under fake time, the way an app builds one at boot.
      var client = HttpClient();
      await s.pumpWidget(_Blank());
      var status = await s.runAsync(() async {
        var request = await client.getUrl(Uri.parse('$base/api/me'));
        var response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      });
      // Closing "its" client must not take the shared pool with it.
      client.close();
      expect(status, 200);
    });

    scenario('the requests log is what the body can assert on', (s) async {
      s.network.post('/api/orders', json: {'id': 7}, status: 201);
      await s.pumpWidget(_Blank());
      await s.runAsync(() => http.post(Uri.parse('$base/api/orders')));
      expect(s.network.requests.last.method, 'POST');
      expect(s.network.requests.last.url.path, '/api/orders');
      expect(s.network.requests.last.status, 201);
    });
  });
}

Future<List<int>> _statuses(ScenarioTester s, String base) async {
  await s.runAsync(
    () async => (await http.get(Uri.parse('$base/api/items'))).statusCode,
  );
  return [for (var request in s.network.requests) request.status ?? 0];
}

class _Blank extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('ready'))),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Image.network(
          url,
          width: 32,
          height: 32,
          errorBuilder: (context, error, stack) => const Text('ERR'),
        ),
      ),
    ),
  );
}
