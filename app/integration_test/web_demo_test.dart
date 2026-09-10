@Tags(['browser'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:test/test.dart';

/// The compiled web demo, opened in a real browser.
///
/// `flutter build web` proves the shell compiles without a filesystem. What
/// breaks the deployed page is a read that compiles fine and throws
/// `UnsupportedError` the moment a frame reaches it — a `Platform` lookup in
/// a default argument, a `statSync` in an `initState` — and every one of
/// those found so far was found by clicking. This is the clicking, done by a
/// machine: the bytes `tool/demo/build_web.dart` produces, served under the
/// same path as Pages, walked by Chrome through the semantics tree the demo
/// turns on at boot. A JavaScript error, a failed request, a response at 400
/// or above, or a screen that never shows what the recording holds, fails
/// it — with the list.
///
/// `FW_WEB_DEMO_BUILD` names a build to validate instead of building one; CI
/// passes the directory it is about to deploy. Chrome is puppeteer's own,
/// fetched into `.dart_tool/puppeteer/` the first time and cached by CI.
///
/// A screenshot of every step lands in `build/web_demo/shots/`, green or red,
/// so a run leaves a picture to look at.
void main() {
  late String packageRoot;
  late String buildDir;
  late String baseHref;
  late HttpServer server;
  late Browser browser;
  late Directory shots;

  setUpAll(() async {
    packageRoot = Directory.current.path;
    expect(
      File(p.join(packageRoot, 'lib', 'main_demo_web.dart')).existsSync(),
      isTrue,
      reason: 'run from app/: cd app && fvm dart test integration_test',
    );
    shots = Directory(p.join(packageRoot, 'build', 'web_demo', 'shots'));
    if (shots.existsSync()) shots.deleteSync(recursive: true);
    shots.createSync(recursive: true);

    var given = Platform.environment['FW_WEB_DEMO_BUILD'];
    buildDir = given != null
        ? p.normalize(p.absolute(given))
        : await _build(packageRoot);
    baseHref = _baseHrefOf(File(p.join(buildDir, 'index.html')));
    server = await shelf_io.serve(
      _serve(buildDir, under: baseHref),
      InternetAddress.loopbackIPv4,
      0,
    );

    var chrome = await downloadChrome(onDownloadProgress: _progress);
    browser = await puppeteer.launch(
      executablePath: chrome.executablePath,
      // A CI runner's Chrome runs as root, which its sandbox refuses.
      noSandboxFlag: Platform.isLinux,
    );
  });

  tearDownAll(() async {
    await browser.close();
    await server.close(force: true);
  });

  test('opens, walks to a recorded panel and back, with no error', () async {
    var page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 1400, height: 900));
    var errors = <String>[];
    var fetched = <String, int>{};
    page.onError.listen((e) => errors.add('page error: ${e.message}'));
    page.onConsole.listen((m) {
      if (m.type == ConsoleMessageType.error) {
        errors.add('console error: ${m.text}');
      }
    });
    page.onRequestFailed.listen(
      (r) => errors.add('request failed: ${r.url} (${r.failure})'),
    );
    page.onResponse.listen((r) {
      fetched[r.url] = r.status;
      if (r.status >= 400) errors.add('${r.status} ${r.url}');
    });

    var url = 'http://${server.address.host}:${server.port}$baseHref';
    var screen = _Screen(page, shots, errors: errors);
    await page.goto(url, wait: Until.load);

    // The rail is the recorded project's declared plugins.
    await screen.waitFor('Launcher icon');
    await screen.waitFor('Dependencies');
    await screen.shot('home');

    // The one recorded panel: its scan and its pictures come over HTTP from
    // beside the page, which is the whole of what the deploy has to get
    // right.
    await screen.tap('Launcher icon');
    await screen.waitFor('kiosk');
    await _waitUntil(
      () => fetched.entries.any(
        (e) => e.key.contains('launcher_icon/files/') && e.value == 200,
      ),
      what: 'a launcher icon picture fetched from beside the page',
    );
    await screen.settle();
    await screen.shot('launcher-icons');
    expect(
      fetched.entries.where((e) => e.key.contains('launcher_icon/root.json')),
      isNotEmpty,
      reason: 'the scan should be fetched from demo/fixture/ beside the page',
    );
    expect(await screen.texts(), isNot(contains(contains('Could not read'))));

    // A flavor, which is a second scan and a second set of pictures.
    await screen.tap('kiosk');
    await _waitUntil(
      () => fetched.entries.any(
        (e) => e.key.contains('root.kiosk.json') && e.value == 200,
      ),
      what: 'the kiosk scan fetched',
    );
    await screen.settle();
    await screen.shot('kiosk-flavor');

    // The second recorded panel: a scenario run, its frames fetched the same
    // way. Opening a scenario "runs" it, which over a recording is a read.
    await screen.tap('Scenarios');
    await screen.waitFor('Order a cappuccino');
    await screen.shot('scenarios');
    await screen.tap('Order a cappuccino');
    await screen.waitFor('Order placed');
    await _waitUntil(
      () => fetched.entries.any(
        (e) =>
            e.key.contains('/scenarios/root/') &&
            e.key.endsWith('.png') &&
            e.value == 200,
      ),
      what: 'a recorded scenario frame fetched from beside the page',
    );
    await screen.settle();
    await screen.shot('scenario-run');

    // The canvas zooms on a modified wheel. In a browser a trackpad scroll
    // is a wheel event, which is not what the desktop gets, so this is the
    // one place the gesture is exercised as the page receives it.
    var before = await screen.find('%');
    if (before == null) fail('the zoom readout should be on screen');
    var welcome = await screen.waitFor('1 · Welcome');
    await page.mouse.move(Point(welcome.x + welcome.w / 2, welcome.y + 200));
    await page.keyboard.down(Key.meta);
    await page.mouse.wheel(deltaY: -240);
    await page.keyboard.up(Key.meta);
    await _waitUntil(
      () async => (await screen.find('%'))?.text != before.text,
      what: 'the zoom readout to move off ${before.text} after cmd+wheel',
    );
    await screen.shot('zoomed-with-the-wheel');

    // A plugin with nothing recorded says so, rather than reaching for a
    // process or a disk.
    await screen.tap('Dependencies');
    await screen.waitFor('Not in this recording');
    await screen.shot('not-recorded');

    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}

/// `tool/demo/build_web.dart`, through the SDK running this test.
Future<String> _build(String packageRoot) async {
  var dart = Platform.resolvedExecutable;
  print('Building the web demo with $dart …');
  var result = await Process.run(dart, [
    'run',
    'tool/demo/build_web.dart',
    '--base-href',
    '/flutterware/',
  ], workingDirectory: packageRoot);
  if (result.exitCode != 0) {
    fail('build_web.dart failed:\n${result.stdout}\n${result.stderr}');
  }
  return p.join(packageRoot, 'build', 'web');
}

String _baseHrefOf(File index) {
  var match = RegExp(r'<base href="([^"]*)">')
      .firstMatch(index.readAsStringSync());
  if (match == null) fail('${index.path} has no <base href>');
  return match.group(1)!;
}

/// The build directory, served under [under] the way Pages serves it under
/// the repository's path — so a URL the page builds wrong is wrong here too.
shelf.Handler _serve(String buildDir, {required String under}) {
  var prefix = under.replaceAll(RegExp(r'^/|/$'), '');
  var files = createStaticHandler(buildDir, defaultDocument: 'index.html');
  return (request) {
    var path = request.url.path;
    if (prefix.isEmpty) return files(request);
    if (path == prefix || path.startsWith('$prefix/')) {
      return files(request.change(path: prefix));
    }
    return shelf.Response.notFound('Not under $under: /$path');
  };
}

int _lastReported = -1;
void _progress(int received, int total) {
  if (total <= 0) return;
  var percent = received * 100 ~/ total;
  if (percent ~/ 25 != _lastReported ~/ 25) {
    _lastReported = percent;
    print('Downloading Chrome: $percent%');
  }
}

Future<void> _waitUntil(
  FutureOr<bool> Function() condition, {
  required String what,
  Duration timeout = const Duration(seconds: 30),
}) async {
  var deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// The page as its semantics tree tells it: every `flt-semantics` element
/// with the words it carries and where it is.
///
/// A Flutter page is one canvas; the semantics tree the demo enables at boot
/// is the only DOM there is, and a screen reader and this test read the same
/// one. A label lives either in `aria-label` or in the element's own text
/// nodes, depending on the role — both are read, and a node's own words are
/// its own, not its children's, so that a container does not match for
/// everything inside it.
class _Screen {
  _Screen(this.page, this.shots, {required this.errors});

  final Page page;
  final Directory shots;

  /// What the page has already got wrong. A wait that would otherwise run to
  /// its timeout ends the moment one of these lands: a 404 on the recording
  /// is the answer, not the minute of nothing that follows it.
  final List<String> errors;
  var _shot = 0;

  static const _nodesJs = '''
() => Array.from(document.querySelectorAll('flt-semantics')).map(e => {
  const own = Array.from(e.childNodes)
    .filter(n => n.nodeName !== 'FLT-SEMANTICS'
              && n.nodeName !== 'FLT-SEMANTICS-CONTAINER')
    .map(n => n.textContent || '').join('');
  const r = e.getBoundingClientRect();
  return {
    text: ((e.getAttribute('aria-label') || '') + ' ' + own).trim(),
    x: r.x, y: r.y, w: r.width, h: r.height,
  };
})''';

  Future<List<_Node>> nodes() async {
    var raw = await page.evaluate<List<Object?>>(_nodesJs);
    return [for (var n in raw.cast<Map<String, Object?>>()) _Node.fromJson(n)];
  }

  Future<List<String>> texts() async => [
    for (var n in await nodes())
      if (n.text.isNotEmpty) n.text,
  ];

  /// The smallest visible node whose words contain [label].
  Future<_Node?> find(String label) async {
    _Node? best;
    for (var n in await nodes()) {
      if (!n.text.contains(label) || n.area <= 0) continue;
      if (best == null || n.area < best.area) best = n;
    }
    return best;
  }

  Future<_Node> waitFor(
    String label, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    var deadline = DateTime.now().add(timeout);
    while (true) {
      var found = await find(label);
      if (found != null) return found;
      if (errors.isNotEmpty) {
        // A stack arrives as one console line per frame; let it finish so
        // the failure names the frame and not just the exception.
        await Future<void>.delayed(const Duration(seconds: 2));
        fail(
          'The page reported errors while waiting for "$label":\n'
          '${errors.join('\n')}\nOn screen:\n${(await texts()).join('\n')}',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'Timed out waiting for "$label" on the page. On screen:\n'
          '${(await texts()).join('\n')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> tap(String label) async {
    var n = await waitFor(label);
    await page.mouse.click(Point(n.x + n.w / 2, n.y + n.h / 2));
  }

  /// A moment for fetched pictures to decode and paint before a screenshot.
  Future<void> settle() => Future<void>.delayed(const Duration(seconds: 1));

  Future<void> shot(String name) async {
    _shot++;
    var file = File(
      p.join(shots.path, '${_shot.toString().padLeft(2, '0')}-$name.png'),
    );
    file.writeAsBytesSync(await page.screenshot());
  }
}

class _Node {
  _Node(this.text, this.x, this.y, this.w, this.h);

  factory _Node.fromJson(Map<String, Object?> json) => _Node(
    json['text']! as String,
    json['x']! as num,
    json['y']! as num,
    json['w']! as num,
    json['h']! as num,
  );

  final String text;
  final num x, y, w, h;

  num get area => w * h;
}
