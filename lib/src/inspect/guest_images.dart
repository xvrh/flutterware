import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

/// Answers "has every image this build asked for actually arrived".
///
/// A capture is a race the images lose: `Image.asset` registers a load during
/// build, the decode completes asynchronously a few milliseconds later, and a
/// frame photographed between the two shows the layout without the pixels — no
/// error, no placeholder, just an absence that looks like a passing test. The
/// engine's decode pipeline is fine; what was missing is any way for the
/// capture side to know it has not finished yet.
///
/// The count is [ImageCache.pendingImageCount]: a completer sits in it from
/// the moment a provider starts loading until its first frame is delivered,
/// which is exactly the window a capture must not fire in. Images that bypass
/// the cache do not register — bounded heuristic, not a guarantee, and the
/// caller's timeout is what keeps that a slightly-early picture rather than a
/// hang.
class GuestImages {
  GuestImages._();

  static final instance = GuestImages._();

  /// Registers the extension. Call once, before `runApp`.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.imagesSettled', (_, _) async {
      // A frame first, then the count, in that order on purpose. The frame is
      // what *starts* the loads: a fresh guest has built nothing, and a count
      // taken before the first build reads zero for the wrong reason. It is
      // also what paints anything delivered since the last one, so a zero
      // describes pixels on screen rather than bytes in a cache.
      //
      // Bounded because this is an RPC the capture waits on — same reasoning
      // as `setParameters`: a guest that has stopped drawing should make the
      // caller late, not stuck.
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'pending': PaintingBinding.instance.imageCache.pendingImageCount,
        }),
      );
    });
  }
}
