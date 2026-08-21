import 'dart:async';

/// A scan failure whose message is already a sentence for the reader.
///
/// [ScanCache] stores failures as `'$error'`. An uncurated exception arrives
/// prefixed — `Exception: …`, `Bad state: …` — which is right for a surprise
/// and wrong for a diagnosis the scan wrote on purpose, like "Run `flutter pub
/// get` in that project first." Throwing this keeps the sentence as written.
class ScanFailure implements Exception {
  ScanFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One answer per key, computed by [scan], kept until [invalidate].
///
/// Four cores grew this same organ independently — a value map, a failure map,
/// an in-flight set, a pending map — and they diverged exactly where it is
/// subtle. Two of them were bitten by the same trap (see [load]) and carried
/// twin warnings pointing at each other; a third still had the trapped
/// spelling. This is the organ written once, with the discipline in one place.
///
/// It holds **state only**: no timers, no watchers, no isolates. What a scan
/// *is* and when to invalidate stay with the core — a poller like splash's
/// fingerprint loop composes on top through [settledKeys] and [isScanning].
///
/// Failures are **sticky for [track]**: a panel remounting must not hammer a
/// scan that is known to fail. They clear on [invalidate]/[reload] — the
/// refresh button — or when a later scan succeeds. A core whose failures
/// should instead retry on the next look passes [retryAfterFailure]; the
/// translations panel relies on that, having no refresh button of its own.
class ScanCache<K, T> {
  ScanCache({
    required this._scan,
    required this._onChanged,
    this._onSettled,
    this._retryAfterFailure = false,
  });

  final Future<T> Function(K key) _scan;

  /// Reports every observable transition — a scan starting, an answer landing,
  /// an invalidation. Cores pass `notifyChanged`.
  final void Function() _onChanged;

  /// Runs after [key]'s answer — value or failure — lands, before the change
  /// notification. Never for a scan that lost to an [invalidate]: what it
  /// derives (splash derives a fingerprint) must describe the answer that is
  /// actually in the cache.
  final void Function(K key)? _onSettled;

  final bool _retryAfterFailure;

  final _values = <K, T>{};
  final _failures = <K, String>{};
  final _scanning = <K, int>{};
  final _pending = <K, Future<void>>{};

  /// Bumped by [invalidate]. A scan compares the epoch it started under, so an
  /// answer read from *before* the invalidation cannot land *after* it and
  /// shadow the fresh read that the invalidation was for.
  final _epochs = <K, int>{};

  /// The value for [key], or null when nothing has looked or the look failed.
  T? operator [](K key) => _values[key];

  String? failureFor(K key) => _failures[key];

  bool isScanning(K key) => _scanning.containsKey(key);

  bool get anyScanning => _scanning.isNotEmpty;

  bool get anyFailed => _failures.isNotEmpty;

  Iterable<T> get values => _values.values;

  /// Keys holding an answer — a value or a failure. What a poller walks; a
  /// fresh set each call, so invalidating while iterating is safe.
  Set<K> get settledKeys => {..._values.keys, ..._failures.keys};

  /// Scans [key], unless it already has been. Idempotent — what a panel calls
  /// on mount, where nothing is waiting on the result.
  void track(K key) => unawaited(load(key));

  /// [track], for a caller that waits — `computeAll`, and everything reaching
  /// an answer through an action.
  Future<void> load(K key) {
    if (_values.containsKey(key) ||
        (!_retryAfterFailure && _failures.containsKey(key))) {
      return Future.value();
    }
    var pending = _pending[key];
    if (pending != null) return pending;

    // Registered before any clean-up can possibly run, never via
    // `putIfAbsent(key, () => …)`: a scan that completes without suspending
    // runs its clean-up *inside* the callback, before the entry exists — the
    // completed future then stays registered forever, and every load after an
    // [invalidate] returns it instead of reading the disk. Splash was bitten,
    // icon documented it, assets still had the trapped spelling.
    //
    // The clean-up is guarded because [invalidate] may already have handed the
    // key to a newer scan, whose entry this older one must not sweep. And it is
    // a block, not an arrow: `Map.remove` returns the removed value — the very
    // future `whenComplete` is completing — and `whenComplete` awaits whatever
    // its callback returns, so an arrow body makes the future wait for itself.
    late Future<void> future;
    future = _run(key).whenComplete(() {
      if (identical(_pending[key], future)) _pending.remove(key);
    });
    _pending[key] = future;
    return future;
  }

  /// Drops [key]'s answer so the next [track] re-reads, and disowns any scan
  /// already in flight — its answer predates this call by definition.
  void invalidate(K key) {
    _epochs[key] = (_epochs[key] ?? 0) + 1;
    _values.remove(key);
    _failures.remove(key);
    _pending.remove(key);
    _onChanged();
  }

  /// Reads [key] again, and **completes when the new answer is in** — what a
  /// refresh button awaits, where [track]'s fire-and-forget would leave it
  /// reporting done before anything was.
  Future<void> reload(K key) {
    invalidate(key);
    return load(key);
  }

  Future<void> _run(K key) async {
    var epoch = _epochs[key] ?? 0;
    _scanning[key] = (_scanning[key] ?? 0) + 1;
    _onChanged();
    try {
      var value = await _scan(key);
      if (epoch == (_epochs[key] ?? 0)) {
        _values[key] = value;
        _failures.remove(key);
        _onSettled?.call(key);
      }
    } catch (error) {
      if (epoch == (_epochs[key] ?? 0)) {
        _failures[key] = '$error';
        _onSettled?.call(key);
      }
    } finally {
      // A count, not a set: a reload during an in-flight scan runs two at
      // once, and the first to settle must not report the other one done.
      var left = _scanning[key]! - 1;
      if (left == 0) {
        _scanning.remove(key);
      } else {
        _scanning[key] = left;
      }
      _onChanged();
    }
  }
}
