import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutterware/flutter_test.dart';

/// One entry may not make the next one slow.
///
/// The image cache is `PaintingBinding`'s, process-wide, and nothing in
/// `flutter_test` empties it between bodies — so an entry that ends with a
/// decode still in flight leaves `pendingImageCount > 0` behind it for the life
/// of the tester, and every entry after it waits out the whole real-work
/// allowance on work that is not its own and will never land.
///
/// The leak needs no exotic widget: `MemoryImage` does not evict its key when a
/// decode **fails**, the way `NetworkImage`, `FileImage` and `ResizeImage` all
/// do, so a preview of an unreadable image is enough. Measured on this repo's
/// own catalog with exactly that entry sixth of 123 — every one of the 117
/// after it went from ~50ms to a flat ~2.4s, and the catalog took 287s.
void main() {
  var ids = ['demo/broken.dart#broken', 'demo/plain.dart#plain'];
  var pendingAtBuild = <String, int>{};
  var elapsed = <String, Duration>{};
  var watch = Stopwatch();
  var done = 0;

  setUp(() {
    watch
      ..reset()
      ..start();
  });
  // Registered for every test in the file, the closing assertions included —
  // and those are not entries and have no elapsed worth keeping.
  tearDown(() {
    if (done < ids.length) elapsed[ids[done++]] = watch.elapsed;
  });

  Widget record(String id, Widget child) {
    pendingAtBuild[id] = PaintingBinding.instance.imageCache.pendingImageCount;
    return child;
  }

  runPreviewHarness([
    PreviewEntry(
      id: ids[0],
      path: 'demo/broken.dart',
      name: 'Broken',
      build: () => record(
        ids[0],
        Image.memory(
          _notAnImage,
          errorBuilder: (context, error, stack) =>
              const Text('unreadable', textDirection: TextDirection.ltr),
        ),
      ),
    ),
    PreviewEntry(
      id: ids[1],
      path: 'demo/plain.dart',
      name: 'Plain',
      build: () =>
          record(ids[1], const Text('plain', textDirection: TextDirection.ltr)),
    ),
  ]);

  // Declared after the entries, so it runs after them.
  test('an entry starts with the cache the one before it did', () {
    expect(pendingAtBuild[ids[0]], 0);
    expect(
      pendingAtBuild[ids[1]],
      0,
      reason: 'the entry before this one left a decode pending for ever',
    );
  });

  test('and the entry after a leak is not made to wait for it', () {
    // The symptom rather than its cause. Poisoned, this was the whole
    // allowance; clean, it is the tens of milliseconds an entry costs.
    expect(elapsed[ids[1]]!.inMilliseconds, lessThan(500));
  });

  test('the entry that does leak waits its allowance in real time', () {
    // What the allowance is spent in. Counting waiting turns charged each one
    // the millisecond it asked to sleep against the ~2.4ms it actually cost,
    // so a one-second ceiling took two and a half seconds of clock — and, being
    // a count of turns, took longer still on a slower machine. Measured against
    // the wall clock it is a second wherever it runs, which is what its own doc
    // comment always claimed.
    expect(elapsed[ids[0]]!.inMilliseconds, lessThan(2000));
  });
}

/// Bytes no decoder will take — the demo variant every asset viewer has, and
/// the one that poisoned the catalog.
final _notAnImage = Uint8List.fromList(
  utf8.encode('{"flavour": "staging", "retries": 3}'),
);
