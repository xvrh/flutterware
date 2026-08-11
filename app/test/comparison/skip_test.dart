import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/closure.dart';
import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:flutterware_app/src/comparison/shot_key.dart';
import 'package:flutterware_app/src/comparison/skip.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The skip rule and the cache it feeds: what makes a comparison of a large
/// catalog take seconds instead of a minute.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_skip'));
  tearDown(() => root.deleteSync(recursive: true));

  /// A checkout holding [files], relative path → content.
  String checkout(String name, Map<String, String> files) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    files.forEach((relative, content) {
      var file = File(p.join(dir.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });
    return dir.path;
  }

  ClosureMemo memoWith(String entryId, List<String> paths) =>
      ClosureMemo(p.join(root.path, 'memo'))..remember(entryId, paths);

  group('closure', () {
    // The reason this hashes content rather than calling `stat`: a fresh
    // `git worktree add` stamps every file with the moment it was created, so
    // an mtime comparison across two checkouts reports that everything
    // changed, always.
    test('two checkouts of identical files agree', () {
      var files = {'lib/a.dart': 'const a = 1;', 'lib/b.dart': 'const b = 2;'};
      var base = SourceClosure.of(files.keys, root: checkout('base', files));
      var head = SourceClosure.of(files.keys, root: checkout('head', files));

      expect(head.fingerprint, base.fingerprint);
      expect(head.changedAgainst(base), isEmpty);
    });

    test('a changed byte moves the fingerprint and is named', () {
      var paths = ['lib/a.dart', 'lib/b.dart'];
      var base = SourceClosure.of(
        paths,
        root: checkout('base', {'lib/a.dart': '1', 'lib/b.dart': '2'}),
      );
      var head = SourceClosure.of(
        paths,
        root: checkout('head', {'lib/a.dart': '1', 'lib/b.dart': '3'}),
      );

      expect(head.fingerprint, isNot(base.fingerprint));
      expect(head.changedAgainst(base), ['lib/b.dart']);
    });

    // Recorded rather than skipped: a deleted file has to read as a change,
    // not as one fewer entry in the map.
    test('a file that is gone on one side is a change', () {
      var paths = ['lib/a.dart'];
      var base = SourceClosure.of(
        paths,
        root: checkout('base', {'lib/a.dart': '1'}),
      );
      var head = SourceClosure.of(paths, root: checkout('head', {}));

      expect(head.digests['lib/a.dart'], SourceClosure.missing);
      expect(head.changedAgainst(base), ['lib/a.dart']);
    });

    // What lies outside a checkout is the SDK and the pub cache, and neither
    // can change without changing something inside it.
    test('a path outside the checkout is dropped', () {
      var outside = File(p.join(root.path, 'elsewhere.dart'))
        ..writeAsStringSync('x');
      var closure = SourceClosure.of([
        'lib/a.dart',
        outside.path,
      ], root: checkout('base', {'lib/a.dart': '1'}));

      expect(closure.digests.keys, ['lib/a.dart']);
    });
  });

  group('the skip rule', () {
    test('an untouched entry is skipped without rendering', () {
      var files = {'lib/card.dart': 'const x = 1;'};
      var decision = SkipDecision.of(
        entryId: 'demo/card.dart#card',
        memo: memoWith('demo/card.dart#card', ['lib/card.dart']),
        baseRoot: checkout('base', files),
        headRoot: checkout('head', files),
      );

      expect(decision.skip, isTrue);
      expect(decision.reason, isNull);
    });

    test('a touched entry is rendered, and says what touched it', () {
      var decision = SkipDecision.of(
        entryId: 'demo/card.dart#card',
        memo: memoWith('demo/card.dart#card', ['lib/card.dart']),
        baseRoot: checkout('base', {'lib/card.dart': 'const x = 1;'}),
        headRoot: checkout('head', {'lib/card.dart': 'const x = 2;'}),
      );

      expect(decision.skip, isFalse);
      expect(decision.changed, ['lib/card.dart']);
      expect(decision.reason, contains('lib/card.dart'));
    });

    // The entry's own file is untouched; a theme three imports away moved.
    // Nothing but the compiler's list would catch that, which is why the list
    // is the compiler's.
    test('a change anywhere in the closure counts', () {
      var decision = SkipDecision.of(
        entryId: 'demo/card.dart#card',
        memo: memoWith('demo/card.dart#card', [
          'demo/card.dart',
          'lib/theme.dart',
        ]),
        baseRoot: checkout('base', {
          'demo/card.dart': 'card',
          'lib/theme.dart': 'blue',
        }),
        headRoot: checkout('head', {
          'demo/card.dart': 'card',
          'lib/theme.dart': 'green',
        }),
      );

      expect(decision.skip, isFalse);
      expect(decision.changed, ['lib/theme.dart']);
    });

    // A path wrongly included costs one render; a path wrongly left out
    // reports a regression as clean.
    test('an input the compiler never names still blocks a skip', () {
      var decision = SkipDecision.of(
        entryId: 'demo/card.dart#card',
        memo: memoWith('demo/card.dart#card', ['demo/card.dart']),
        baseRoot: checkout('base', {
          'demo/card.dart': 'card',
          'assets/logo.png': 'old pixels',
        }),
        headRoot: checkout('head', {
          'demo/card.dart': 'card',
          'assets/logo.png': 'new pixels',
        }),
        extraPaths: ['assets/logo.png'],
      );

      expect(decision.skip, isFalse);
      expect(decision.changed, ['assets/logo.png']);
    });

    test('an entry nothing has compiled is never skipped', () {
      var decision = SkipDecision.of(
        entryId: 'demo/new.dart#fresh',
        memo: ClosureMemo(p.join(root.path, 'memo')),
        baseRoot: checkout('base', {}),
        headRoot: checkout('head', {}),
      );

      expect(decision.skip, isFalse);
      expect(decision.reason, contains('unknown'));
    });

    test('the memo survives being written and read again', () {
      var directory = p.join(root.path, 'memo');
      ClosureMemo(directory).remember('demo/a.dart#one', ['lib/b.dart']);

      expect(ClosureMemo(directory).recall('demo/a.dart#one'), ['lib/b.dart']);
      expect(ClosureMemo(directory).recall('demo/a.dart#two'), isNull);
    });
  });

  group('the key', () {
    String key({
      String entry = 'demo/a.dart#one',
      String closure = 'abc',
      String sdk = 'engine-1',
      Map<String, String> axes = const {},
      Map<String, String> knobs = const {},
    }) => ShotKey.of(
      kind: 'preview',
      entryId: entry,
      closure: closure,
      sdk: sdk,
      axes: axes,
      knobs: knobs,
    );

    test('the same inputs name the same picture', () {
      expect(key(), key());
    });

    test('every input that can move a pixel moves the key', () {
      expect(key(entry: 'demo/b.dart#two'), isNot(key()));
      expect(key(closure: 'def'), isNot(key()));
      expect(key(sdk: 'engine-2'), isNot(key()));
      expect(key(axes: {'brightness': 'dark'}), isNot(key()));
      expect(key(knobs: {'count': '3'}), isNot(key()));
    });

    // A map's iteration order is its insertion order, so two callers applying
    // the same two axes in the other order would otherwise render twice.
    test('the order axes were applied in is not an input', () {
      expect(
        key(axes: {'brightness': 'dark', 'locale': 'fr'}),
        key(axes: {'locale': 'fr', 'brightness': 'dark'}),
      );
    });

    test('an empty section cannot be confused with a filled one', () {
      expect(key(axes: {'knobs': 'x'}), isNot(key(knobs: {'x': ''})));
    });
  });

  group('the cache', () {
    test('a picture comes back as it went in', () {
      var cache = ShotCache(p.join(root.path, 'shots'));
      var bytes = Uint8List.fromList([1, 2, 3, 4]);

      cache.write(
        'abcdef0123',
        bytes,
        const ShotRecord(format: 'raw', width: 1, height: 1, entryId: 'a#b'),
      );

      expect(cache.has('abcdef0123'), isTrue);
      expect(cache.read('abcdef0123'), bytes);
      expect(cache.meta('abcdef0123')?.format, 'raw');
      expect(cache.meta('abcdef0123')?.entryId, 'a#b');
    });

    test('nothing is claimed for a key that was never written', () {
      var cache = ShotCache(p.join(root.path, 'shots'));

      expect(cache.has('0000000000'), isFalse);
      expect(cache.read('0000000000'), isNull);
      expect(cache.meta('0000000000'), isNull);
    });

    // A comparison can be killed at any moment, and a half-written picture
    // under a content key is a lie that never expires.
    test('a partial write is not visible under its key', () {
      var cache = ShotCache(p.join(root.path, 'shots'));
      cache.write(
        'abcdef0123',
        Uint8List.fromList([9]),
        const ShotRecord(format: 'raw', width: 1, height: 1),
      );

      var staging = Directory(
        p.join(root.path, 'shots'),
      ).listSync(recursive: true).where((e) => e.path.endsWith('.part'));

      expect(staging, isEmpty);
    });
  });
}
