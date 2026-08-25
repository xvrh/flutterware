import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
import 'package:flutterware_app/src/previews/thumbnail_keys.dart';
import 'package:flutterware_app/src/previews/thumbnails.dart';
import 'package:path/path.dart' as p;

/// A thumbnail outliving the session that took it.
///
/// The popover used to render a picture per session and throw it away, which
/// was affordable while the bound was two dozen and the store was memory. It
/// stops being affordable the moment a whole catalog is wanted at once:
/// measured on this repo, 154 previews are ~13 seconds of `flutter_tester`,
/// and paying that on every launch — in every worktree — is the difference
/// between a page worth opening and one nobody waits for.
///
/// So a picture is filed under what *made* it rather than under the session:
/// the entry's whole import closure, the pixel inputs, the SDK. Two checkouts
/// of one commit have the same key and share the picture; an edit moves the
/// key of the entries that read what changed and of no others.
/// A real 2x2 PNG, because the store's PNG path is the one production takes:
/// it is what decides whether bytes are kept for a page to draw, and a fake
/// that handed back raw rgba would exercise the other branch entirely.
final _png = Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  2,
  8,
  6,
  0,
  0,
  0,
  114,
  182,
  13,
  36,
  0,
  0,
  0,
  17,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  104,
  104,
  104,
  248,
  15,
  194,
  12,
  48,
  6,
  0,
  86,
  244,
  9,
  253,
  75,
  75,
  233,
  44,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

void main() {
  const alpha = CatalogEntry(
    path: 'demo/a.dart',
    symbol: 'alpha',
    annotation: "Preview(name: 'Alpha')",
    name: 'Alpha',
  );
  const beta = CatalogEntry(
    path: 'demo/b.dart',
    symbol: 'beta',
    annotation: "Preview(name: 'Beta')",
    name: 'Beta',
  );
  const gamma = CatalogEntry(
    path: 'demo/c.dart',
    symbol: 'gamma',
    annotation: "Preview(name: 'Gamma')",
    name: 'Gamma',
  );

  late Directory root;
  late String packageRoot;
  late ShotCache shots;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_thumb_store');
    packageRoot = p.join(root.path, 'pkg');
    // A workspace as the tool meets one: the single `package_config.json` at
    // the checkout top level, the package below it. That is the shape
    // `ThumbnailKeys` derives its root from, so a fixture that put the config
    // inside the package would be testing an arrangement nothing produces.
    File(p.join(root.path, '.dart_tool', 'package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'pkg', 'rootUri': '../pkg', 'packageUri': 'lib/'},
          ],
        }),
      );
    File(p.join(packageRoot, 'pubspec.yaml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('name: pkg\n');
    // `b` reads a helper `a` does not, which is what makes an edit to it a
    // question about *which* keys move rather than whether any do.
    File(p.join(packageRoot, 'lib', 'helper.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('const helper = 1;\n');
    File(p.join(packageRoot, 'demo', 'c.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// gamma\n');
    File(p.join(packageRoot, 'demo', 'a.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// alpha\n');
    File(p.join(packageRoot, 'demo', 'b.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync("import 'package:pkg/helper.dart';\n// beta\n");

    shots = ShotCache(p.join(root.path, 'shots'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  ThumbnailKeys keysOf() => ThumbnailKeys(
    packageRoot: packageRoot,
    sdkKey: 'sdk-1',
    extra: const {'longest': '700'},
  );

  /// A store whose renders are counted, answering with a 2×2 raw frame.
  (PreviewThumbnails, List<String>) storeOf({
    ShotCache? cache,
    ThumbnailKeys? keys,
  }) {
    var asked = <String>[];
    var store = PreviewThumbnails(
      packageRoot: packageRoot,
      cache: cache,
      keys: keys,
      render: (entryId, outDir, {required sync}) async {
        asked.add(entryId);
        var file = File(p.join(outDir, 'frame.png'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(_png);
        return PreviewCaptureRow(
          id: entryId,
          image: file.path,
          format: 'png',
          width: 2,
          height: 2,
        );
      },
    );
    addTearDown(store.dispose);
    return (store, asked);
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('never arrived');
  }

  test("a second session is served the first session's picture", () async {
    var (first, askedFirst) = storeOf(cache: shots, keys: keysOf());
    first.want(alpha);
    await until(() => first.of(alpha) is ThumbnailReady);
    expect(askedFirst, [alpha.id]);

    // A different store over the same machine — which is also what a different
    // *worktree* is, since nothing in the key names one.
    var (second, askedSecond) = storeOf(cache: shots, keys: keysOf());
    second.want(alpha);
    await until(() => second.of(alpha) is ThumbnailReady);

    expect(
      askedSecond,
      isEmpty,
      reason: 'the harness is never brought up for a picture already taken',
    );
  });

  test('and renders what nobody has filed yet', () async {
    var (first, _) = storeOf(cache: shots, keys: keysOf());
    first.want(alpha);
    await until(() => first.of(alpha) is ThumbnailReady);

    var (second, asked) = storeOf(cache: shots, keys: keysOf());
    second.want(beta);
    await until(() => second.of(beta) is ThumbnailReady);

    expect(asked, [beta.id]);
  });

  test('an edit moves the key of what reads it, and only that', () {
    var before = keysOf();
    var alphaKey = before.keyFor(alpha);
    var betaKey = before.keyFor(beta);

    File(p.join(packageRoot, 'lib', 'helper.dart'))
        .writeAsStringSync('const helper = 2;\n');

    var after = keysOf();

    expect(
      after.keyFor(beta),
      isNot(betaKey),
      reason: 'beta imports the helper, so its pixels may have moved',
    );
    expect(
      after.keyFor(alpha),
      alphaKey,
      reason: 'alpha does not, so its picture is still good',
    );
  });

  test('the same source is the same key, twice over', () {
    // The property the whole store rests on. If this ever stopped holding,
    // nothing would be served from disk and nothing would say so — it would
    // simply be slow.
    expect(keysOf().keyFor(alpha), keysOf().keyFor(alpha));
  });

  test('a different SDK is a different picture', () {
    var other = ThumbnailKeys(
      packageRoot: packageRoot,
      sdkKey: 'sdk-2',
      extra: const {'longest': '700'},
    );
    expect(other.keyFor(alpha), isNot(keysOf().keyFor(alpha)));
  });

  test('warming off the isolate gives the very same keys', () async {
    // The whole safety of moving this work is that it is the same work: a
    // `warm` that produced different keys would not be slower or wrong-looking,
    // it would quietly stop matching anything in the store and re-render the
    // catalog for ever. Measured on this repo's 154 previews, warming costs
    // 352ms off the painting isolate against ~600ms on it.
    var direct = keysOf();
    var expected = {
      for (var e in [alpha, beta]) e.id: direct.keyFor(e),
    };

    var warmed = keysOf();
    await warmed.warm([alpha, beta]);

    expect({
      for (var e in [alpha, beta]) e.id: warmed.keyFor(e),
    }, expected);
  });

  test('and warming twice asks for nothing the second time', () async {
    var keys = keysOf();
    await keys.warm([alpha, beta]);
    var first = keys.keyFor(alpha);
    // Idempotent, because a page calls this on every scroll frame.
    await keys.warm([alpha, beta]);
    expect(keys.keyFor(alpha), first);
  });

  test('a store handed unreadable bytes renders rather than fails', () async {
    // A cache is an optimisation, so a broken one may cost time and nothing
    // else. Truncated files under a content key are what a killed process
    // leaves behind.
    var keys = keysOf();
    shots.write(
      keys.keyFor(alpha),
      Uint8List.fromList([1, 2, 3]),
      const ShotRecord(format: 'png', width: 2, height: 2),
    );

    var (store, asked) = storeOf(cache: shots, keys: keys);
    store.want(alpha);
    await until(() => store.of(alpha) is ThumbnailReady);

    expect(asked, [alpha.id], reason: 'it fell through to the harness');
  });

  group('an edit under a page of tiles', () {
    /// A store that records the `sync` of every ask as well as the entry.
    ///
    /// The flag is half the claim: a re-render that skips the sync asks a
    /// harness still holding the previous program, and files *that* picture
    /// under the new source — the failure the whole staleness rule exists for.
    (PreviewThumbnails, List<(String, bool)>) countingStore() {
      var asked = <(String, bool)>[];
      var store = PreviewThumbnails(
        packageRoot: packageRoot,
        cache: shots,
        keys: keysOf(),
        render: (entryId, outDir, {required sync}) async {
          asked.add((entryId, sync));
          var file = File(p.join(outDir, 'frame.png'))
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(_png);
          return PreviewCaptureRow(
            id: entryId,
            image: file.path,
            format: 'png',
            width: 2,
            height: 2,
          );
        },
      );
      addTearDown(store.dispose);
      return (store, asked);
    }

    void edit(String path) {
      var file = File(p.join(packageRoot, path))
        ..writeAsStringSync('// edited\n');
      // Stamped forward rather than trusted to the clock: the check is
      // "different from what was recorded", and a filesystem that rounds could
      // hand back the same microsecond for a write this soon after the last.
      file.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
    }

    test('is noticed, even though a tile is never marked ready', () async {
      // The bug this pins: a page's rows stay `ThumbnailPending` for ever —
      // that is how `_next` tells answered from outstanding — so a staleness
      // check that only looked at the thumbnail called every rendered tile
      // pending and found nothing to drop. An edit then re-read the *pre-edit*
      // key out of the store and re-filed that picture under the new mtime,
      // and the sheet showed the old render until the next rescan.
      var (store, asked) = countingStore();
      store.wantAll([alpha]);
      await until(() => store.bytesOf(alpha) != null);
      expect(asked, [(alpha.id, true)], reason: 'cold, so it synced');

      edit('demo/a.dart');
      store.wantAll([alpha]);

      await until(() => asked.length > 1);
      expect(asked.last, (
        alpha.id,
        true,
      ), reason: 'and it synced again, or the harness answers from stale code');
      await until(() => store.bytesOf(alpha) != null);
    });

    test('and an untouched neighbour is not re-asked for nothing', () async {
      // Everything is dropped, because the harness compiles one program — but
      // the *keys* of what did not change do not move, so the store answers
      // for them and only the edited entry costs a render.
      var (store, asked) = countingStore();
      store.wantAll([alpha, gamma]);
      await until(
        () => store.bytesOf(alpha) != null && store.bytesOf(gamma) != null,
      );
      expect(asked.length, 2);

      edit('demo/a.dart');
      store.wantAll([alpha, gamma]);
      await until(() => store.bytesOf(gamma) != null);
      await until(() => asked.length > 2);

      expect(
        asked.skip(2).map((a) => a.$1),
        everyElement(alpha.id),
        reason: 'gamma came back out of the store',
      );
    });
  });

  test('a picture is filed under the source it was rendered from', () async {
    // The key is taken before the render and written after, and a rescan can
    // land in between — `invalidate()` drops the memo, so a key taken again
    // afterwards describes source this picture was never made from. Filing it
    // there is not a stale picture but a permanently wrong one: the store is
    // content addressed, so every later session and every other worktree on
    // that commit finds it and serves it.
    var keys = keysOf();
    // The key as it stood before anything moved, so the assertion can say
    // "under neither of them" rather than only "not under the new one".
    var before = keys.keyFor(alpha);
    var rendered = 0;
    var store = PreviewThumbnails(
      packageRoot: packageRoot,
      cache: shots,
      keys: keys,
      render: (entryId, outDir, {required sync}) async {
        rendered++;
        // The disk moves while the harness is busy.
        File(p.join(packageRoot, 'demo', 'a.dart'))
          ..writeAsStringSync('// changed mid-render\n')
          ..setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
        keys.invalidate();
        var file = File(p.join(outDir, 'frame.png'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(_png);
        return PreviewCaptureRow(
          id: entryId,
          image: file.path,
          format: 'png',
          width: 2,
          height: 2,
        );
      },
    );
    addTearDown(store.dispose);

    store.want(alpha);
    // The render, not the picture: what came back is a photograph of source
    // that no longer exists, so `of` rightly refuses to serve it — the stamp
    // it was taken at is already behind the file. What is under test is what
    // reached the *store*.
    await until(() => rendered > 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      shots.read(keysOf().keyFor(alpha)),
      isNull,
      reason: 'nothing was filed under the source it never rendered',
    );
    // **Nor under the one it started from.** Which of the two this picture is
    // of is exactly what cannot be known: the harness syncs somewhere inside
    // the call, so an edit landing before that sweep is *in* the frame and one
    // landing after it is not. A store that guessed either way would be right
    // half the time and permanently wrong the rest.
    expect(
      shots.read(before),
      isNull,
      reason: 'the source it started from is no longer what it rendered',
    );
    expect(
      rendered,
      1,
      reason: 'and the dropped write is not retried in a loop',
    );
  });

  group('bytes a page cannot draw', () {
    test('are re-rendered once the widget says so', () async {
      // A page draws the encoded form, so nothing decodes a tile's picture
      // before it is painted — a truncated file under a live key is caught by
      // no guard here and simply throws in the tile for ever. The widget that
      // failed is the only witness, and `discard` is how it says so.
      var keys = keysOf();
      shots.write(
        keys.keyFor(alpha),
        Uint8List.fromList([1, 2, 3]),
        const ShotRecord(format: 'png', width: 2, height: 2),
      );
      var (store, asked) = storeOf(cache: shots, keys: keys);

      store.wantAll([alpha]);
      await until(() => store.bytesOf(alpha) != null);
      expect(asked, isEmpty, reason: 'the store answered, badly');

      store.discard(alpha);
      await until(() => asked.isNotEmpty);
      await until(() => store.bytesOf(alpha) != null);

      expect(store.bytesOf(alpha), _png, reason: 'the render overwrote it');
    });

    test('and twice is a failure rather than another round', () async {
      // Or the tile and the harness take turns for ever.
      var (store, _) = storeOf(cache: shots, keys: keysOf());
      store.wantAll([alpha]);
      await until(() => store.bytesOf(alpha) != null);

      store.discard(alpha);
      store.discard(alpha);

      expect(store.of(alpha), isA<ThumbnailFailed>());
      expect(store.bytesOf(alpha), isNull);
    });
  });

  test('a frame a page cannot hold is decoded rather than re-asked', () async {
    // Raw rgba has no header, so there is nothing to put in front of a tile.
    // Answering the round with neither bytes nor a thumbnail left the entry in
    // exactly the state `_next` picks by, and the pump rendered it for ever.
    var asked = <String>[];
    var store = PreviewThumbnails(
      packageRoot: packageRoot,
      render: (entryId, outDir, {required sync}) async {
        asked.add(entryId);
        var file = File(p.join(outDir, 'frame.raw'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(Uint8List(2 * 2 * 4));
        return PreviewCaptureRow(
          id: entryId,
          image: file.path,
          width: 2,
          height: 2,
        );
      },
    );
    addTearDown(store.dispose);

    store.wantAll([alpha]);
    await until(() => store.of(alpha) is ThumbnailReady);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(asked, [alpha.id], reason: 'once, not once a round');
  });

  group('a page asking for everything it shows', () {
    // What a page gets is **bytes**, not a decoded picture. Decoding a
    // 900x700 frame is real work and a tile draws from the encoded form
    // through Flutter's own image cache, so decoding for the page would be
    // 154 pictures made and thrown away. The popover is the caller that needs
    // a `ui.Image`, and it wants one at a time — so `of()` answering
    // `ThumbnailReady` is the hover's contract and `bytesOf()` is the page's.
    test('drains, rather than serving only the last ask', () async {
      // The hover's rule is latest-wins, because a pointer sweeping a list
      // produces a stream of asks of which only the last is still wanted. A
      // page is the opposite: every tile on it is wanted, and a queue that kept
      // only the last would leave a screenful of grey boxes.
      var (store, asked) = storeOf();
      store.wantAll([alpha, beta]);
      await until(
        () => store.bytesOf(alpha) != null && store.bytesOf(beta) != null,
      );
      expect(asked, unorderedEquals([alpha.id, beta.id]));
    });

    test('and a hover jumps the queue', () async {
      // The queue, not the render already in flight: a picture being taken
      // cannot be un-asked, and abandoning it would throw away the work and
      // still not answer sooner. So alpha finishes, and then the pointer's row
      // is served ahead of the rest of the page.
      var (store, asked) = storeOf();
      store.wantAll([alpha, gamma]);
      store.want(beta);
      await until(() => store.bytesOf(gamma) != null);

      expect(asked, [alpha.id, beta.id, gamma.id]);
      expect(
        store.of(beta),
        isA<ThumbnailReady>(),
        reason: 'the hovered one is decoded, because something draws it',
      );
      expect(
        store.of(gamma),
        isNot(isA<ThumbnailReady>()),
        reason: 'the page draws gamma from its bytes and needs no picture',
      );
    });

    test('what scrolled away is never started', () async {
      var (store, asked) = storeOf();
      store.wantAll([alpha, beta]);
      // Replaced while alpha is still rendering — which is what a scroll is.
      store.wantAll([alpha]);
      await until(() => store.bytesOf(alpha) != null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(asked, [
        alpha.id,
      ], reason: 'beta was asked for and scrolled away before its turn');
    });
  });

  test('a page larger than the picture bound still fills', () async {
    // **The bug this pins cost a minute of rendering and showed one tile.**
    // The MRU bound is two dozen, which is right for a pointer and hopeless
    // for a page: every arriving picture evicted an earlier one, the renderer
    // saw the gap as something still to do, and it rendered the same entries
    // round and round. So the bound counts decoded pictures only, and the
    // encoded bytes — 36kb each — are kept for everything.
    var many = [
      for (var i = 0; i < PreviewThumbnails.keep * 2; i++)
        CatalogEntry(
          path: 'demo/many/e$i.dart',
          symbol: 'e$i',
          annotation: "Preview(name: 'E$i')",
          name: 'E$i',
        ),
    ];
    for (var entry in many) {
      File(p.join(packageRoot, entry.path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// ${entry.symbol}\n');
    }

    var (store, asked) = storeOf();
    store.wantAll(many);
    await until(() => many.every((e) => store.bytesOf(e) != null));

    expect(
      asked.length,
      many.length,
      reason: 'each entry rendered exactly once, bound or no bound',
    );
  });

  test('a store with no cache keeps its old behaviour', () async {
    var (store, asked) = storeOf();
    store.want(alpha);
    await until(() => store.of(alpha) is ThumbnailReady);
    expect(asked, [alpha.id]);
  });
}
