import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'catalog_entry.dart';
import 'test_runner.dart';

/// Photographs one entry into `outDir` and answers with what the harness said.
///
/// `sync` brings the harness up to date with the disk first, which costs about
/// two seconds whether or not anything moved — see [PreviewTestRunner.capture].
typedef PreviewRender =
    Future<PreviewCaptureRow?> Function(
      String entryId,
      String outDir, {
      required bool sync,
    });

/// What the store has to say about one entry.
sealed class Thumbnail {
  const Thumbnail();
}

/// Asked for, not here yet.
///
/// [compiling] tells the two waits apart, and they are not the same wait: a
/// cold harness compiles the whole catalog and takes tens of seconds, where a
/// warm one is a message and a frame. A caption that said "rendering" for both
/// would be a lie for one of them.
class ThumbnailPending extends Thumbnail {
  const ThumbnailPending({required this.compiling});

  final bool compiling;
}

class ThumbnailReady extends Thumbnail {
  const ThumbnailReady(this.image);

  /// Already at the size it will be drawn near — see
  /// [PreviewThumbnails.longestSide].
  final ui.Image image;
}

/// The entry rendered and said something, or would not compile at all. Either
/// way there is no picture and the words are what there is to show.
class ThumbnailFailed extends Thumbnail {
  const ThumbnailFailed(this.reason);

  final String reason;
}

/// One package's previews, photographed under `flutter_tester` and kept.
///
/// **Why this lane and not the live guest.** There is one embedded engine and
/// one texture, so a guest asked for another entry shows it on the canvas —
/// there is no arrangement where a popover holds one picture while the canvas
/// holds another. A photograph has no such tie: it can be drawn anywhere, as
/// many times as there are places to draw it. It is also deterministic, which
/// is what makes it worth keeping — the same entry under FakeAsync renders
/// byte-identically, so a picture stays right until its source moves.
///
/// Rendering is serial and latest-wins. The harness is one process answering
/// one question at a time, and a pointer produces a stream of questions of
/// which only the last is still being asked.
class PreviewThumbnails extends ChangeNotifier {
  PreviewThumbnails({required this.packageRoot, required this.render});

  /// Over a warm [PreviewTestRunner], which is how the panel builds one.
  ///
  /// Taking the *rendering* rather than the runner is what lets this be tested
  /// without a `flutter_tester`: what is worth testing here is the caching and
  /// the staleness, and neither of those is about how a picture gets made.
  PreviewThumbnails.of(PreviewTestRunner runner)
    : packageRoot = runner.packageRoot,
      render = ((entryId, outDir, {required sync}) async {
        PreviewCaptureRow? row;
        await runner.capture(
          entryIds: [entryId],
          outDir: outDir,
          sync: sync,
          onRow: (found) async => row = found,
        );
        return row;
      });

  /// Where an entry's `path` is relative to — what a staleness stamp reads.
  final String packageRoot;

  final PreviewRender render;

  /// The longest side a stored picture is decoded to, in logical pixels.
  ///
  /// The popover draws at ~340, so this is roughly a 2× display's worth and
  /// nothing beyond it. Full size would be 2.5MB an entry decoded, which
  /// across a catalog is hundreds of megabytes for detail no one can see.
  static const longestSide = 700;

  /// How many pictures are kept. Least-recently-asked-for goes first.
  ///
  /// A bound rather than a sweep: what is worth keeping is what the pointer
  /// has been near, and that is exactly what an MRU list holds.
  static const keep = 24;

  final _cache = <String, _Entry>{};
  final _order = <String>[];

  /// Where raw frames land. Deleted as they are decoded — a frame is 2.5MB and
  /// the decoded picture is what anyone wants.
  late final _scratch = Directory.systemTemp.createTempSync('fw_previews');

  String? _wanted;
  var _rendering = false;
  var _disposed = false;

  /// Whether the harness has been brought up. The first render pays a compile
  /// of the whole catalog; everything after it is a message and a frame.
  bool get warm => _warm;
  var _warm = false;

  /// What the store knows about [entry], or null if nobody has asked.
  Thumbnail? of(CatalogEntry entry) {
    var found = _cache[entry.id];
    if (found == null) return null;
    // Stale by its own file: the cheapest honest test there is. It does not
    // catch an edit to something the entry *imports*, which is the known hole
    // — the sync below is what closes it, and it only runs when this fires.
    if (found.stamp != _stampOf(entry)) return null;
    return found.thumbnail;
  }

  /// Asks for [entry]'s picture, if it is not already the answer to [of].
  ///
  /// Idempotent and cheap to call on every hover.
  void want(CatalogEntry entry) {
    if (_disposed) return;
    if (of(entry) case ThumbnailReady() || ThumbnailFailed()) return;
    _wanted = entry.id;
    if (_cache[entry.id]?.thumbnail is! ThumbnailPending) {
      _store(entry, ThumbnailPending(compiling: !_warm));
    }
    unawaited(_render(entry));
  }

  /// Starts the harness without asking for anything.
  ///
  /// Called when the pointer enters the list rather than when it stops on a
  /// row: a cold catalog is tens of seconds of compile, and the difference
  /// between paying it from the moment the hand arrives and from the moment it
  /// settles is most of what the first picture feels like.
  void warmUp(CatalogEntry? any) {
    if (_disposed || _warm || _rendering || any == null) return;
    unawaited(_render(any, keepPicture: false));
  }

  /// Everything is stale — the catalog moved under us.
  void invalidate() {
    if (_cache.isEmpty) return;
    for (var entry in _cache.values) {
      entry.dispose();
    }
    _cache.clear();
    _order.clear();
    notifyListeners();
  }

  Future<void> _render(CatalogEntry entry, {bool keepPicture = true}) async {
    if (_rendering) return;
    _rendering = true;
    try {
      while (!_disposed) {
        // **Sync on the way up, never after.** A sync is a sweep of every
        // source and the asset bundle, 1.5s or so whether or not anything
        // moved, and a pointer cannot pay that per row. The cold bring-up is
        // already paying for a compile, so it is free there.
        var cold = !_warm;
        var out = p.join(_scratch.path, entry.id.hashCode.toString());
        PreviewCaptureRow? row;
        try {
          row = await render(entry.id, out, sync: cold);
          _warm = true;
        } catch (e) {
          _store(entry, ThumbnailFailed('$e'));
          return;
        }
        if (_disposed) return;
        if (keepPicture) await _land(entry, row);
        // Whatever the pointer landed on while that ran, which may be nothing.
        var next = _wanted;
        if (next == null || next == entry.id) return;
        var found = _cache[next]?.entry;
        if (found == null) return;
        entry = found;
        keepPicture = true;
      }
    } finally {
      _rendering = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _land(CatalogEntry entry, PreviewCaptureRow? row) async {
    if (row == null) {
      _store(entry, const ThumbnailFailed('the harness said nothing'));
      return;
    }
    if (row.compileError ?? row.failure case var problem?) {
      // A picture was still taken for a failure — an ErrorWidget is what is
      // there — but the words are the answer and the red box is not worth
      // 700 pixels of popover.
      _store(entry, ThumbnailFailed(problem));
      return;
    }
    var path = row.image;
    if (path == null || row.width == 0) {
      _store(entry, const ThumbnailFailed('nothing rendered'));
      return;
    }
    try {
      var file = File(path);
      var bytes = await file.readAsBytes();
      unawaited(
        file.parent.delete(recursive: true).catchError((_) => file.parent),
      );
      var image = await _decode(bytes, row.width, row.height);
      if (_disposed) {
        image.dispose();
        return;
      }
      _store(entry, ThumbnailReady(image));
    } catch (e) {
      _store(entry, ThumbnailFailed('$e'));
    }
  }

  /// Raw rgba straight to a picture, scaled on the way in.
  ///
  /// The capture writes 1× logical pixels — 900×700 for a panel — and the
  /// decoder can resample as it reads, so the full-size buffer never becomes a
  /// full-size image. Never upscaled: a 375-wide phone shot is already bigger
  /// than it is drawn.
  Future<ui.Image> _decode(Uint8List bytes, int width, int height) {
    var longest = width > height ? width : height;
    var scale = longest > longestSide ? longestSide / longest : 1.0;
    var done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
      targetWidth: (width * scale).round(),
      targetHeight: (height * scale).round(),
    );
    return done.future;
  }

  void _store(CatalogEntry entry, Thumbnail thumbnail) {
    _cache[entry.id]?.dispose();
    _cache[entry.id] = _Entry(entry, _stampOf(entry), thumbnail);
    _order
      ..remove(entry.id)
      ..add(entry.id);
    while (_order.length > keep) {
      _cache.remove(_order.removeAt(0))?.dispose();
    }
    if (!_disposed) notifyListeners();
  }

  /// The entry's own file, as the daemon last wrote it. Zero when it is gone,
  /// which reads as "changed" against any real stamp and re-renders.
  int _stampOf(CatalogEntry entry) {
    var file = File(p.join(packageRoot, entry.path));
    return file.existsSync()
        ? file.lastModifiedSync().microsecondsSinceEpoch
        : 0;
  }

  @override
  void dispose() {
    _disposed = true;
    for (var entry in _cache.values) {
      entry.dispose();
    }
    _cache.clear();
    try {
      _scratch.deleteSync(recursive: true);
    } on FileSystemException {
      // A frame still being written, or a directory already gone. Neither is
      // worth failing a worktree close over.
    }
    super.dispose();
  }
}

class _Entry {
  _Entry(this.entry, this.stamp, this.thumbnail);

  final CatalogEntry entry;
  final int stamp;
  final Thumbnail thumbnail;

  void dispose() {
    if (thumbnail case ThumbnailReady(:var image)) image.dispose();
  }
}
