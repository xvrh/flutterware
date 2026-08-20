import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutterware/flutter_test.dart';

/// The previews harness is not the only lane with this shape: the image cache
/// is `PaintingBinding`'s and process-wide, `flutter_test` never empties it,
/// and a scenario that ends with a decode still in flight would hand
/// `pendingImageCount > 0` to every scenario after it — each of which would
/// then wait out the whole real-work allowance on somebody else's work.
///
/// `MemoryImage` is all it takes: it does not evict its key when a decode
/// **fails**, the way `NetworkImage`, `FileImage` and `ResizeImage` all do.
/// `test/previews/image_cache_reset_test.dart` is the same clause on the other
/// lane, with the catalog-wide measurement that found it.
void main() {
  int? pendingAtStart;
  var elapsed = Duration.zero;

  scenario('a scenario that leaves a decode in flight', (s) async {
    await s.pumpWidget(
      Image.memory(
        _notAnImage,
        errorBuilder: (context, error, stack) =>
            const Text('unreadable', textDirection: TextDirection.ltr),
      ),
    );
    await s.screen('unreadable');
  });

  scenario('does not hand it to the next one', (s) async {
    var watch = Stopwatch()..start();
    pendingAtStart = PaintingBinding.instance.imageCache.pendingImageCount;
    await s.pumpWidget(const Text('plain', textDirection: TextDirection.ltr));
    await s.screen('plain');
    elapsed = watch.elapsed;
  });

  test('the cache the second scenario started with was empty', () {
    expect(
      pendingAtStart,
      0,
      reason: 'the scenario before this one left a decode pending for ever',
    );
    // The symptom rather than its cause: poisoned, both the settle and the
    // landing after it spend the allowance on the leak.
    expect(elapsed.inMilliseconds, lessThan(500));
  });
}

/// Bytes no decoder will take.
final _notAnImage = Uint8List.fromList(
  utf8.encode('{"flavour": "staging", "retries": 3}'),
);
