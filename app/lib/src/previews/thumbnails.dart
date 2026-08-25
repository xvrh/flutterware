import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../comparison/shot_cache.dart';
import 'catalog_entry.dart';
import 'test_runner.dart';
import 'thumbnail_keys.dart';

/// Photographs one entry into `outDir` and answers with what the harness said.
///
/// `sync` brings the harness up to date with the disk first, which costs about
/// two seconds whether or not anything moved — see [PreviewTestRunner.capture].
typedef PreviewRender = Future<PreviewCaptureRow?> Function(
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
/// Why this lane and not the live guest. There is one embedded engine and
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
  PreviewThumbnails({
    required this.packageRoot,
    required this.render,
    this.cache,
    this.keys,
  });

  /// Over a warm [PreviewTestRunner], which is how the panel builds one.
  ///
  /// Taking the *rendering* rather than the runner is what lets this be tested
  /// without a `flutter_tester`: what is worth testing here is the caching and
  /// the staleness, and neither of those is about how a picture gets made.
  ///
  /// **PNG and no tree**, which is what a picture wants and an audit does not.
  /// Measured on this repo's 154 previews: the tree beside a frame costs 9ms an
  /// entry and nobody looking at a thumbnail reads it, and encoding costs 12ms
  /// and takes the frame from 2444kb to 36kb. Roughly a wash on the clock, and
  /// the difference between a store of hundreds of megabytes and one of single
  /// digits — which is what makes [cache] worth having at all.
  PreviewThumbnails.of(PreviewTestRunner runner, {this.cache, this.keys})
    : packageRoot = runner.packageRoot,
      render = ((entryId, outDir, {required sync}) async {
        PreviewCaptureRow? row;
        await runner.capture(
          entryIds: [entryId],
          outDir: outDir,
          sync: sync,
          tree: false,
          format: 'png',
          onRow: (found) async => row = found,
        );
        return row;
      });

  /// Where a rendered picture is kept between sessions, or null to hold them
  /// only in memory — which is what a test that is about the staleness rules
  /// wants, and what a package with no [keys] gets.
  ///
  /// Shared with the comparison's own store on purpose. It is content
  /// addressed, so nothing collides and nothing is per-worktree, and it already
  /// sweeps itself.
  final ShotCache? cache;

  /// What names a picture in [cache]. Null disables persistence entirely —
  /// both halves are needed, and a store with one is a bug rather than a mode.
  final ThumbnailKeys? keys;

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

  /// The encoded picture per entry, which is what a *page* of them draws from.
  ///
  /// **Unbounded, and deliberately not the same store as [_cache].** A PNG is
  /// 36kb, so this repo's whole 154-entry catalog is under six megabytes held
  /// here; a decoded picture is 1.5MB, which is why those are bounded. Keeping
  /// the cheap half separate is what lets the expensive half be evicted without
  /// the page losing anything.
  ///
  /// It was one store, briefly, and the result was a page that never filled:
  /// two dozen pictures is the right bound for a pointer and hopeless for a
  /// hundred and fifty tiles, so each arriving picture evicted an earlier one,
  /// which the renderer then saw as missing and rendered again. It rendered for
  /// a minute and had one tile to show for it.
  ///
  /// Handing *bytes* to the page rather than a `ui.Image` also puts the
  /// decoding in Flutter's own image cache, which bounds it, reference-counts
  /// it, and cannot hand a painting widget a picture something else disposed.
  final _bytes = <String, _Kept>{};

  /// Where raw frames land. Deleted as they are decoded — a frame is 2.5MB and
  /// the decoded picture is what anyone wants.
  late final _scratch = Directory.systemTemp.createTempSync('fw_previews');

  /// The one row a pointer is resting on, which outranks the page.
  String? _wanted;

  /// The page's ask, in the order it draws. See [wantAll].
  final _queue = <CatalogEntry>[];

  var _rendering = false;
  var _disposed = false;

  /// Whether the disk is known to have moved since the harness was last
  /// brought up to date.
  ///
  /// The harness renders what it compiled, never what is on disk, so a
  /// re-render on its own photographs the same stale code again — and then
  /// stores it under the *new* stamp, which is how a picture stops being
  /// merely old and becomes permanently wrong. Only a `sync` pushes the edits
  /// in, and it costs ~1.5s, so this is what makes one happen once per edit
  /// rather than once per hover or, as it did, never.
  var _moved = false;

  /// Whether the harness has been brought up. The first render pays a compile
  /// of the whole catalog; everything after it is a message and a frame.
  bool get warm => _warm;
  var _warm = false;

  /// What the store knows about [entry], or null if it has not been asked
  /// for.
  Thumbnail? of(CatalogEntry entry) {
    var found = _cache[entry.id];
    if (found == null) return null;
    // Stale by its own file: the cheapest honest test there is. It does not
    // catch an edit to something the entry *imports* — that is what [_moved]
    // and the sync it buys are for, since a sync moves the harness past every
    // picture at once.
    if (found.stamp != _stampOf(entry)) return null;
    return found.thumbnail;
  }

  /// [entry]'s picture as it was encoded, for a caller that would rather let
  /// Flutter decode and cache it — see [_bytes].
  ///
  /// Stale by the same rule [of] uses, so the two never disagree about whether
  /// there is a picture.
  Uint8List? bytesOf(CatalogEntry entry) {
    var found = _bytes[entry.id];
    if (found == null || found.stamp != _stampOf(entry)) return null;
    return found.bytes;
  }

  /// A widget could not draw [entry]'s bytes.
  ///
  /// **The only place that finds out.** A page draws from the encoded form, so
  /// nothing decodes a tile's picture before it is painted — which means a
  /// truncated file under a live key, the thing a killed process leaves behind,
  /// is never caught by the guard in [_recall] and simply throws in the tile
  /// for ever. The widget that failed is the one witness there is.
  ///
  /// Once is a bad store: the key is skipped so the entry renders again, and
  /// the render overwrites what is under it. Twice is a picture this cannot
  /// draw at all, and it is recorded as a failure rather than retried — or the
  /// tile and the harness would take turns for ever.
  void discard(CatalogEntry entry) {
    if (_disposed) return;
    _bytes.remove(entry.id);
    if (_filingFor(entry) case var filing?) _rejected.add(filing.key);
    if (!_undecodable.add(entry.id)) {
      _store(entry, const ThumbnailFailed('the picture would not decode'));
      return;
    }
    _store(entry, ThumbnailPending(compiling: !_warm));
    _pump();
  }

  /// Store keys whose contents something failed to draw — see [discard].
  final _rejected = <String>{};

  /// And the entries that has happened to, so a second failure is a failure
  /// rather than another round.
  final _undecodable = <String>{};

  /// Asks for [entry]'s picture, if it is not already the answer to [of].
  ///
  /// Idempotent and cheap to call on every hover.
  void want(CatalogEntry entry) {
    if (_disposed) return;
    _dropMoved();
    if (of(entry) case ThumbnailReady() || ThumbnailFailed()) return;
    _wanted = entry.id;
    if (_cache[entry.id]?.thumbnail is! ThumbnailPending) {
      _store(entry, ThumbnailPending(compiling: !_warm));
    }
    _pump();
  }

  /// What a page of tiles wants: everything it is showing, in the order it
  /// draws them.
  ///
  /// **Replaces the previous ask rather than adding to it**, because a page is
  /// a viewport and what scrolled off it is no longer worth a render. Nothing
  /// already answered is asked for twice, so calling this on every scroll frame
  /// costs a walk of the visible list.
  ///
  /// A hover still wins. A pointer resting on a row is a person waiting for
  /// that one picture, where a tile is a person waiting for the page; serving
  /// the page first would make the popover feel broken for as long as the sheet
  /// took, which on a cold catalog is thirteen seconds.
  void wantAll(Iterable<CatalogEntry> entries) {
    if (_disposed) return;
    _dropMoved();
    _queue
      ..clear()
      ..addAll(entries);
    for (var entry in _queue) {
      if (_cache[entry.id] == null) {
        _store(entry, ThumbnailPending(compiling: !_warm));
      }
    }
    _pump();
  }

  /// The picture [entry] is already filed under, if there is one.
  ///
  /// Answers false for anything it cannot serve — no store, no key, nothing
  /// under it, or bytes that will not decode — and a false answer is always
  /// "render it", never "fail it": a cache is an optimisation and a broken one
  /// may only cost time.
  Future<bool> _recall(CatalogEntry entry, {required bool decode}) async {
    // Held already, encoded — which is a hit even when nothing is on disk.
    if (bytesOf(entry) case var kept?) {
      if (decode) await _landDecoded(entry, kept, 'png', 0, 0);
      return true;
    }
    var cache = this.cache;
    var keys = this.keys;
    if (cache == null || keys == null) return false;
    try {
      var key = keys.keyFor(entry);
      // Something already tried to draw what is under this key and could not.
      // Skipped rather than deleted, so the next render simply overwrites it.
      if (_rejected.contains(key)) return false;
      var bytes = cache.read(key);
      if (bytes == null) return false;
      var record = cache.meta(key);
      var format = record?.format ?? 'png';
      if (format == 'png') _bytes[entry.id] = _Kept(_stampOf(entry), bytes);
      // Decoded for whoever is waiting on a picture — and also whenever the
      // stored form is one a page cannot draw. A raw record leaves [_bytes]
      // empty, so returning "served" without decoding would answer nothing at
      // all, and [_next] would pick this entry again every round for ever.
      if (decode || format != 'png') {
        await _landDecoded(
          entry,
          bytes,
          format,
          record?.width ?? 0,
          record?.height ?? 0,
        );
      } else if (!_disposed) {
        notifyListeners();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Decodes [bytes] into the picture [of] answers with.
  ///
  /// **Only for the one entry somebody is waiting on.** A page draws from the
  /// encoded bytes, so decoding for it is work whose result is thrown away: on
  /// this repo's catalog that is 154 decodes of a 900x700 frame nothing asks
  /// for. The popover is the caller that needs a `ui.Image`, and it wants
  /// exactly one at a time.
  Future<void> _landDecoded(
    CatalogEntry entry,
    Uint8List bytes,
    String format,
    int width,
    int height,
  ) async {
    var image = await _decode(bytes, width, height, format);
    if (_disposed) {
      image.dispose();
      return;
    }
    _store(entry, ThumbnailReady(image), stamp: _stampOf(entry));
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

  /// The next thing worth doing, or null when there is nothing.
  ///
  /// The hover first and the page in its own order after it — see [wantAll].
  CatalogEntry? _next() {
    if (_wanted case var id?) {
      var found = _cache[id];
      if (found != null && found.thumbnail is ThumbnailPending) {
        return found.entry;
      }
    }
    for (var entry in _queue) {
      // The bytes first, because they outlive an eviction and a decoded picture
      // does not: an entry whose image was dropped to make room is still not
      // one that needs rendering again.
      if (bytesOf(entry) != null) continue;
      var found = _cache[entry.id];
      if (found == null || found.thumbnail is ThumbnailPending) return entry;
    }
    return null;
  }

  /// Serves whatever [_next] names until nothing is left, one at a time.
  ///
  /// Serial because the harness is: it is one process answering one question,
  /// and asking it two would only queue them somewhere less visible. Every
  /// round tries the store before the harness, so a page whose pictures were
  /// all taken before drains at the speed of a decode rather than a render.
  void _pump() {
    if (_rendering || _disposed) return;
    _rendering = true;
    unawaited(() async {
      try {
        while (!_disposed) {
          // **The keys first, and off this isolate.** Deciding what the store
          // already holds is six-tenths of a second of hashing for a whole
          // catalog, and doing it here would stall the frames the page is
          // being laid out in. Idempotent, so this costs nothing once warm.
          if (keys case var k? when _queue.isNotEmpty) {
            try {
              await k.warm(_queue.toList());
            } catch (e) {
              // A package nobody has resolved has no `package_config.json` and
              // no keys can be derived from it. Caught here like everywhere
              // else that touches the store: a cache is an optimisation, and
              // the pictures are still renderable without one. Uncaught it
              // escaped this closure as an unhandled async error, and every
              // scroll frame raised it again.
            }
            if (_disposed) return;
          }
          var entry = _next();
          if (entry == null) return;
          // Whether anybody needs a decoded picture of it, as opposed to
          // bytes: the popover does and a tile does not. See [_landDecoded].
          var decode = entry.id == _wanted;
          if (await _recall(entry, decode: decode)) continue;
          if (_disposed) return;
          await _renderOne(entry, decode: decode);
        }
      } finally {
        _rendering = false;
        if (!_disposed) notifyListeners();
      }
    }());
  }

  /// Everything is stale — the catalog moved under us.
  void invalidate() {
    // Recorded whether or not there is a picture to throw away. An empty cache
    // over a warm harness is exactly the state where the next render would
    // otherwise photograph the code the harness compiled before the rescan.
    _moved = true;
    // And the keys, which are digests of files that have just been declared
    // out of date. Holding them would serve the previous source's picture for
    // the new source, which is worse than holding no picture at all.
    keys?.invalidate();
    _rejected.clear();
    _undecodable.clear();
    if (_cache.isEmpty) return;
    for (var entry in _cache.values) {
      entry.dispose();
    }
    _cache.clear();
    _order.clear();
    _bytes.clear();
    notifyListeners();
  }

  /// Brings the harness up on [entry] without keeping the picture. Only
  /// [warmUp] uses this; everything else goes through [_pump].
  Future<void> _render(CatalogEntry entry, {bool keepPicture = true}) async {
    if (_rendering) return;
    _rendering = true;
    try {
      await _renderOne(entry, keepPicture: keepPicture, decode: true);
      while (!_disposed) {
        var next = _next();
        if (next == null) return;
        var decode = next.id == _wanted;
        if (await _recall(next, decode: decode)) continue;
        if (_disposed) return;
        await _renderOne(next, decode: decode);
      }
    } finally {
      _rendering = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// One entry, photographed and landed. Called only from a pump that has
  /// already claimed [_rendering].
  Future<void> _renderOne(
    CatalogEntry entry, {
    bool keepPicture = true,
    bool decode = true,
  }) async {
    // **The key, before the picture exists.** It names the source the harness
    // is about to render, and taking it again afterwards would name whatever is
    // on disk by then — see [_Filing].
    var filing = _filingFor(entry);
    // **Sync on the way up, and whenever the disk has moved since.** A sync is
    // a sweep of every source and the asset bundle, 1.5s or so whether or not
    // anything moved, and a pointer cannot pay that per row — the cold bring-up
    // is already paying for a compile, so it is free there. But skipping it
    // *always* was the picture that could never come back: a stale stamp
    // re-renders, the harness answers out of the code it compiled, and the same
    // old frame is stored under the new stamp. Once per edit is the bargain
    // that works.
    var syncing = !_warm || _moved;
    _moved = false;
    // Read before the render rather than after. An edit that lands while this
    // one is running has to leave the picture stale, and a stamp taken on the
    // way out would record that edit as already photographed.
    var stamp = _stampOf(entry);
    var out = p.join(_scratch.path, entry.id.hashCode.toString());
    PreviewCaptureRow? row;
    try {
      row = await render(entry.id, out, sync: syncing);
      _warm = true;
    } catch (e) {
      _store(entry, ThumbnailFailed('$e'), stamp: stamp);
      return;
    }
    if (_disposed) return;
    if (keepPicture) {
      await _land(entry, row, stamp, decode: decode, filing: filing);
    }
  }

  /// What [entry]'s picture will be filed under, and which disk that answer is
  /// about. Null when there is no store, or when the key cannot be worked out
  /// — a cache is an optimisation and a broken one may only cost time.
  _Filing? _filingFor(CatalogEntry entry) {
    var keys = this.keys;
    if (cache == null || keys == null) return null;
    try {
      return _Filing(keys.keyFor(entry), keys.epoch);
    } catch (e) {
      return null;
    }
  }

  Future<void> _land(
    CatalogEntry entry,
    PreviewCaptureRow? row,
    int stamp, {
    required bool decode,
    _Filing? filing,
  }) async {
    if (row == null) {
      _store(
        entry,
        const ThumbnailFailed('the harness said nothing'),
        stamp: stamp,
      );
      return;
    }
    if (row.compileError ?? row.failure case var problem?) {
      // A picture was still taken for a failure — an ErrorWidget is what is
      // there — but the words are the answer and the red box is not worth
      // 700 pixels of popover.
      _store(entry, ThumbnailFailed(problem), stamp: stamp);
      return;
    }
    var path = row.image;
    if (path == null || row.width == 0) {
      _store(entry, const ThumbnailFailed('nothing rendered'), stamp: stamp);
      return;
    }
    try {
      var file = File(path);
      var bytes = await file.readAsBytes();
      unawaited(
        file.parent.delete(recursive: true).catchError((_) => file.parent),
      );
      _keep(filing, entry, bytes, row);
      // Only a PNG: raw rgba has no header, so nothing downstream could decode
      // it without being told the dimensions separately — and the one caller
      // that wants bytes wants them for `Image.memory`.
      if (row.format == 'png') _bytes[entry.id] = _Kept(stamp, bytes);
      // **And only then may the decode be skipped.** A round has to end with
      // this entry answered one way or the other, because [_next] picks by
      // "no bytes and still pending" — so a raw frame handed back here with
      // the decode skipped would leave the entry in exactly the state it was
      // picked in, and the pump would render it again, for ever. Decoding it
      // costs one picture nobody draws; not decoding it costs every render
      // after this one.
      if (!decode && row.format == 'png') {
        if (!_disposed) notifyListeners();
        return;
      }
      var image = await _decode(bytes, row.width, row.height, row.format);
      if (_disposed) {
        image.dispose();
        return;
      }
      _store(entry, ThumbnailReady(image), stamp: stamp);
    } catch (e) {
      _store(entry, ThumbnailFailed('$e'), stamp: stamp);
    }
  }

  /// Files a fresh render so the next session does not pay for it.
  ///
  /// Keyed off the source rather than off this run, so it is also the next
  /// *worktree*'s picture: several checkouts of one commit render the catalog
  /// once between them.
  ///
  /// **Only what the key was computed for.** The key is read before the render
  /// and the picture written under it after, and in between a `sync` has put
  /// exactly that source into the harness — which is the whole reason [want]
  /// may not skip the sync. Writing under a key the harness had not compiled
  /// is not a stale picture, it is a permanently wrong one: every later
  /// session finds the key present and serves it.
  void _keep(
    _Filing? filing,
    CatalogEntry entry,
    Uint8List bytes,
    PreviewCaptureRow row,
  ) {
    var cache = this.cache;
    if (cache == null || filing == null) return;
    // **The disk moved while this was being rendered.** The key describes
    // source the harness no longer holds, so what is in hand is not this key's
    // picture. Dropped rather than written: the next pass renders it again,
    // where a wrong entry in a content-addressed store is forever.
    if (keys?.epoch != filing.epoch) return;
    try {
      cache.write(
        filing.key,
        bytes,
        ShotRecord(
          format: row.format,
          width: row.width,
          height: row.height,
          entryId: entry.id,
        ),
      );
    } on FileSystemException {
      // A full disk, or a store somebody is sweeping. Neither is worth losing
      // the picture already in hand over — it simply is not kept.
    }
  }

  /// Bytes to a picture, scaled on the way in.
  ///
  /// The capture writes 1× logical pixels — 900×700 for a panel — and both
  /// decoders resample as they read, so the full-size buffer never becomes a
  /// full-size image. Never upscaled: a 375-wide phone shot is already bigger
  /// than it is drawn.
  ///
  /// Two formats because there are two sources. A `png` is what the store
  /// holds and carries its own dimensions; `raw` is rgba8888 rows, which do
  /// not, so the caller has to have been told them. Resampling at *decode* is
  /// the point of both: it is what lets one stored picture serve a 340-wide
  /// popover and a 180-wide tile without keeping either at full size.
  Future<ui.Image> _decode(
    Uint8List bytes,
    int width,
    int height,
    String format,
  ) async {
    if (format == 'png') {
      var codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: longestSide,
        allowUpscaling: false,
      );
      return (await codec.getNextFrame()).image;
    }
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

  /// Drops every picture if any entry's own file has moved since its picture
  /// was taken, and records that the harness is behind the disk.
  ///
  /// All of them rather than the one that moved: the harness renders one
  /// compiled program, so a single edited file leaves every picture in
  /// question — a demo drawn by the helper that changed has no stamp of its
  /// own that could ever record it. [keep] bounds this at two dozen stats on a
  /// pointer stopping, not a sweep of the catalog. A pending is left alone: it
  /// has no picture to be stale, and dropping the row a render is on its way to
  /// answering would leave the popover waiting on abandoned work.
  void _dropMoved() {
    var moved = _cache.values.any(_isStale);
    if (!moved) return;
    _moved = true;
    keys?.invalidate();
    _rejected.clear();
    _undecodable.clear();
    // Every one of them, including the ones whose rows are still marked
    // pending: a page's tiles never become anything else, so leaving their
    // bytes here is leaving the page showing the source that changed.
    _bytes.clear();
    for (var id in [..._order]) {
      if (_cache[id]?.thumbnail is ThumbnailPending) continue;
      _cache.remove(id)?.dispose();
      _order.remove(id);
    }
  }

  /// Whether the picture held for [found] was taken from a file that has since
  /// moved.
  ///
  /// **A tile's picture counts, and it does not live in the thumbnail.** A row
  /// answered as bytes is left marked `ThumbnailPending` for ever — that is
  /// what [_next] uses to tell "already answered" from "still to do" — so a
  /// check that read only the thumbnail called every rendered tile pending and
  /// found nothing stale. The result was the worst version of this: editing a
  /// demo left [_moved] false and the keys valid, so the tile re-read the
  /// *pre-edit* key out of the store and re-filed that picture under the new
  /// mtime, and the sheet showed the old render until the next rescan.
  ///
  /// Measured on this repo: statting all 154 entries is **0.42ms**, which a
  /// page may spend on the frames it is being scrolled through.
  bool _isStale(_Entry found) {
    var now = _stampOf(found.entry);
    if (found.thumbnail is! ThumbnailPending) return found.stamp != now;
    var kept = _bytes[found.entry.id];
    return kept != null && kept.stamp != now;
  }

  void _store(CatalogEntry entry, Thumbnail thumbnail, {int? stamp}) {
    _cache[entry.id]?.dispose();
    _cache[entry.id] = _Entry(entry, stamp ?? _stampOf(entry), thumbnail);
    _order
      ..remove(entry.id)
      ..add(entry.id);
    // **Only the decoded pictures are counted.** A pending or a failure is a
    // word and a stamp, and bounding those would throw away the record that
    // something has already been tried — which on a page of a hundred and fifty
    // is the difference between rendering each entry once and rendering for
    // ever. The bytes are not counted either; see [_bytes].
    var decoded = [
      for (var id in _order)
        if (_cache[id]?.thumbnail is ThumbnailReady) id,
    ];
    for (var evicted in decoded.take(
      decoded.length > keep ? decoded.length - keep : 0,
    )) {
      _cache.remove(evicted)?.dispose();
      _order.remove(evicted);
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

/// Where a picture is to be filed, and which disk that answer was about.
///
/// Taken before the render and carried across it — see [ThumbnailKeys.epoch].
class _Filing {
  const _Filing(this.key, this.epoch);

  final String key;
  final int epoch;
}

/// An encoded picture and the state of the file it was taken from.
class _Kept {
  const _Kept(this.stamp, this.bytes);

  final int stamp;
  final Uint8List bytes;
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
