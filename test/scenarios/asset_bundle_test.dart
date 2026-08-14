import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterware/flutter_test.dart';

/// The bundle a scenario reads through, and the deadlock it exists for.
///
/// Every source here answers the way the engine does: from a **root-zone**
/// timer, so a read started under fake time completes only once somebody
/// flushes the fake microtask queue. That is the whole shape of the bug, and
/// simulating it is the only way to have a test for it that does not hang.
void main() {
  testWidgets('a read the app left in flight does not wedge runAsync', (
    tester,
  ) async {
    var source = _Source();
    var bundle = ScenarioAssetBundle(source: source);

    // The app's read, started while the tree was building and still in flight:
    // a fake-zone future, completable by a pump and by nothing else.
    unawaited(bundle.loadString('logo.svg'));

    // The step that reads the same key. No pump can run in here, so anything
    // that hands this the future above never returns.
    String? read;
    await tester.runAsync(() async {
      read = await bundle
          .loadString('logo.svg')
          .timeout(const Duration(seconds: 2));
    });

    expect(read, 'logo.svg contents');
    // Two reads, deliberately: not sharing the in-flight one is exactly what
    // keeps the second out of the first's zone.
    expect(source.reads, 2);
  });

  testWidgets('which is what the SDK cache does instead', (tester) async {
    // The control. `CachingAssetBundle` — which `rootBundle` is — memoizes the
    // *future*, so the second read is handed the first read's fake-zone future
    // and waits for a pump that cannot come.
    var bundle = _CachingSource();
    unawaited(bundle.loadString('logo.svg'));

    var wedged = false;
    await tester.runAsync(() async {
      try {
        await bundle
            .loadString('logo.svg')
            .timeout(const Duration(milliseconds: 300));
      } on TimeoutException {
        wedged = true;
      }
    });

    expect(
      wedged,
      isTrue,
      reason:
          'if this ever goes green the SDK stopped memoizing futures, and '
          'ScenarioAssetBundle has nothing left to do',
    );
  });

  testWidgets('a value already read is served without scheduling anything', (
    tester,
  ) async {
    var source = _Source();
    var bundle = ScenarioAssetBundle(source: source);
    await tester.runAsync(() => bundle.loadString('logo.svg'));

    // A `SynchronousFuture` runs its callback inline — which is what makes a
    // hit safe in whichever zone asks for it.
    String? inline;
    unawaited(bundle.loadString('logo.svg').then((value) => inline = value));

    expect(inline, 'logo.svg contents');
    expect(source.reads, 1);
  });

  testWidgets('structured data is parsed once, then served the same way', (
    tester,
  ) async {
    var source = _Source();
    var bundle = ScenarioAssetBundle(source: source);
    var parses = 0;
    Future<int> parse(String value) async {
      parses++;
      return value.length;
    }

    await tester.runAsync(() => bundle.loadStructuredData('logo.svg', parse));
    int? inline;
    unawaited(
      bundle
          .loadStructuredData('logo.svg', parse)
          .then((value) => inline = value),
    );

    expect(inline, 'logo.svg contents'.length);
    expect(parses, 1);
    expect(source.reads, 1);
  });

  testWidgets('evict and clear drop what was cached', (tester) async {
    var source = _Source();
    var bundle = ScenarioAssetBundle(source: source);
    await tester.runAsync(() => bundle.loadString('logo.svg'));
    expect(source.reads, 1);

    bundle.evict('logo.svg');
    await tester.runAsync(() => bundle.loadString('logo.svg'));
    expect(source.reads, 2);

    bundle.clear();
    await tester.runAsync(() => bundle.loadString('logo.svg'));
    expect(source.reads, 3);
  });

  // What a scenario memoized on `rootBundle` is a *future*, and it belongs to
  // that scenario's FakeAsync zone. Left in flight it can never complete
  // again — nothing will ever flush that zone — so the next scenario awaiting
  // it waits for the rest of the run. Every scenario starts by clearing it,
  // and this is that clear: the parser runs a second time, on the same key,
  // because the second scenario genuinely re-read it.
  var parses = 0;
  Future<int> count(String value) async {
    parses++;
    return value.length;
  }

  scenario('one scenario fills the root bundle cache', (s) async {
    await rootBundle.loadStructuredData('FontManifest.json', count);
    expect(parses, 1);
  });

  scenario('and the next one does not inherit it', (s) async {
    await rootBundle.loadStructuredData('FontManifest.json', count);
    expect(parses, 2);
  });

  scenario('the app is pumped with the scenario bundle over it', (s) async {
    AssetBundle? seen;
    await s.pumpWidget(
      Builder(
        builder: (context) {
          seen = DefaultAssetBundle.of(context);
          return const SizedBox.shrink();
        },
      ),
      shot: Shot.skip,
    );

    // Everything that resolves an asset from a context — `Image.asset`,
    // `AssetImage`, `SvgPicture.asset` — reads through this one.
    expect(seen, same(s.assets));
  });
}

/// An asset source that answers the way the engine does: from the real event
/// loop, which under fake time means "not until something flushes".
class _Source extends AssetBundle {
  var reads = 0;

  @override
  Future<ByteData> load(String key) {
    reads++;
    var completer = Completer<ByteData>();
    Zone.root.createTimer(
      const Duration(milliseconds: 10),
      () => completer.complete(
        ByteData.sublistView(Uint8List.fromList(utf8.encode('$key contents'))),
      ),
    );
    return completer.future;
  }
}

/// The same source, behind the SDK's caching bundle — `rootBundle`'s class.
class _CachingSource extends CachingAssetBundle {
  final _source = _Source();

  @override
  Future<ByteData> load(String key) => _source.load(key);
}
