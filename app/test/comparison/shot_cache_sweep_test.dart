import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The store had no eviction of any kind — no sweep, no cap, no age — while
/// holding raw rgba shared by every worktree on the machine. These are the
/// rules that bound it without throwing away the frames that make it worth
/// having.
void main() {
  late Directory root;
  late ShotCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_shot_sweep_test');
    cache = ShotCache(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// A cached render of [bytes] bytes, filed under a key that is [seed]
  /// repeated — the store shards on the first four characters.
  void put(String seed, {int bytes = 16, Duration? ago}) {
    var key = seed * 10;
    cache.write(
      key,
      Uint8List(bytes),
      const ShotRecord(format: 'raw', width: 2, height: 2),
    );
    cache.writeTree(key, {'node': seed});
    if (ago == null) return;
    var when = DateTime.now().subtract(ago);
    for (var file in _filesUnder(root)) {
      if (p.basename(file.path).startsWith(key)) {
        file.setLastModifiedSync(when);
      }
    }
  }

  bool has(String seed) => cache.has(seed * 10);

  test('what nobody has read in the window goes', () {
    put('aa', ago: const Duration(days: 30));
    put('bb', ago: const Duration(days: 3));

    expect(cache.sweep(keepFor: const Duration(days: 14)), 1);
    expect(has('aa'), isFalse);
    expect(has('bb'), isTrue);
  });

  // The sidecars are the same render and go with it: `has` answers off the
  // bytes, so a half-swept entry would be re-rendered with a stale record
  // still sitting beside it.
  test('an entry is dropped whole', () {
    put('aa', ago: const Duration(days: 30));

    cache.sweep(keepFor: const Duration(days: 14));
    expect(cache.meta('aa' * 10), isNull);
    expect(cache.readTree('aa' * 10), isNull);
  });

  test('what is over the cap goes oldest first', () {
    put('aa', bytes: 400, ago: const Duration(days: 3));
    put('bb', bytes: 400, ago: const Duration(days: 2));
    put('cc', bytes: 400, ago: const Duration(days: 1));

    // Room for two of the three, tree and record included.
    cache.sweep(keepFor: const Duration(days: 14), maxBytes: 1000);
    expect(has('aa'), isFalse);
    expect(has('cc'), isTrue);
  });

  // The point of the store is that a base commit's shots are written once and
  // hit for weeks. Ordering by write would evict exactly those first.
  test('reading an entry keeps it', () {
    put('aa', bytes: 400, ago: const Duration(days: 10));
    put('bb', bytes: 400, ago: const Duration(days: 2));
    put('cc', bytes: 400, ago: const Duration(days: 1));

    expect(cache.read('aa' * 10), isNotNull);

    cache.sweep(keepFor: const Duration(days: 14), maxBytes: 1000);
    expect(has('aa'), isTrue, reason: 'read a moment ago');
    expect(has('bb'), isFalse, reason: 'now the oldest');
  });

  test('a killed write leaves nothing behind for long', () {
    var path = p.join(root.path, 'de', 'ad', 'dead' * 10);
    Directory(p.dirname(path)).createSync(recursive: true);
    var half = File('$path.part')..writeAsBytesSync(Uint8List(64));
    half.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));

    cache.sweep(keepFor: const Duration(days: 14));
    expect(half.existsSync(), isFalse);
  });

  test('an empty store is not an error', () {
    var empty = Directory.systemTemp.createTempSync('fw_shot_empty');
    try {
      expect(ShotCache(p.join(empty.path, 'never')).sweep(), 0);
    } finally {
      empty.deleteSync(recursive: true);
    }
  });
}

List<File> _filesUnder(Directory directory) =>
    directory.listSync(recursive: true).whereType<File>().toList();
