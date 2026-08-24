import 'dart:async';

import 'package:logging/logging.dart';
import 'package:pool/pool.dart';

import 'value_stream.dart';

final _logger = Logger('data_loader');

enum LoadingMode { none, full, overlay }

abstract class Disposable {
  void dispose();
}

class Snapshot<T extends Object> {
  final T? data;
  final Exception? error;
  final bool isLoading;

  const Snapshot({this.data, this.error, bool? isLoading})
    : isLoading = isLoading ?? (data == null && error == null);

  bool get hasError => error != null;
  bool get hasData => data != null;

  T get requireData => data!;

  R when<R>({
    required R Function(T) data,
    required R Function(T?) loading,
    required R Function(Object) error,
  }) {
    var d = this.data;
    var e = this.error;
    if (d != null) {
      return data(d);
    } else if (e != null) {
      return error(e);
    } else {
      return loading(d);
    }
  }
}

/// A value loaded asynchronously, published as a [ValueStream] of [Snapshot]s.
///
/// This is a *loader*, not a notifier — the loading modes, the [Pool] that
/// serialises refreshes and the [Disposable] chaining are what it is for.
/// Notification is delegated to [snapshots], which is why nothing here imports
/// `package:flutter`.
///
/// Laziness is [ValueStream]'s `onListen`: the first subscriber starts the
/// load, and reading [value] never does. That is what makes a `PluginReport` a
/// safe pure read of whatever some widget already caused to load.
class AsyncValue<T extends Object> {
  final Future<T> Function() _loader;
  final String? debugName;
  final bool lazy;
  final LoadingMode? loadingMode;
  late final ValueStream<Snapshot<T>> _snapshots;
  final _pool = Pool(1);
  bool _isInitialized = false;
  bool _isDisposed = false;

  AsyncValue({
    required this._loader,
    bool? lazy,
    this.loadingMode,
    T? seed,
    this.debugName,
  }) : lazy = lazy ?? true {
    _snapshots = ValueStream<Snapshot<T>>(
      const Snapshot(),
      debugName: debugName,
      onListen: () {
        if (!_isInitialized) refresh();
      },
    );
    if (seed != null) {
      _isInitialized = true;
      _setValue(Snapshot(data: seed));
    } else if (!this.lazy) {
      refresh();
    }
  }

  /// The snapshots, for a widget or anything else that wants to follow along.
  /// Subscribing is what starts the load.
  ValueStream<Snapshot<T>> get snapshots => _snapshots;

  /// The current snapshot. Reading it never starts work — a caller that has
  /// not subscribed sees `isLoading` until somebody does.
  Snapshot<T> get value => _snapshots.value;

  Stream<Snapshot<T>> get stream => _snapshots.stream;

  StreamSubscription<Snapshot<T>> listen(
    void Function(Snapshot<T> snapshot) onData,
  ) => _snapshots.listen(onData);

  Future<Snapshot<T>> _load() async {
    try {
      var data = await _loader();
      return Snapshot(data: data);
    } on Exception catch (e, s) {
      _logger.info('Failed to load $debugName: $e', e, s);
      return Snapshot(error: e);
    } catch (e, s) {
      _logger.warning('Error in loader $debugName: $e', e, s);
      rethrow;
    }
  }

  void _setValue(Snapshot<T> snapshot) {
    if (_isDisposed) return;

    var previousValue = _snapshots.value.data;
    // `value =`, not `emit`: skipping an identical snapshot is what
    // `ValueNotifier` did, and the UI is tuned against that.
    _snapshots.value = snapshot;
    if (previousValue is Disposable) {
      previousValue.dispose();
    }
  }

  void update(T data) {
    _setValue(Snapshot(data: data));
  }

  Future<Snapshot<T>> refresh({LoadingMode? mode}) async {
    _isInitialized = true;
    mode ??= loadingMode ?? LoadingMode.full;

    var result = await _pool.withResource(() async {
      if (mode == LoadingMode.full) {
        _setValue(const Snapshot(isLoading: true));
      } else if (mode == LoadingMode.overlay) {
        _setValue(Snapshot(isLoading: true, data: value.data));
      } else if (value.hasError) {
        _setValue(const Snapshot(isLoading: true));
      }

      var newValue = await _load();
      _setValue(newValue);
      return newValue;
    });
    return result;
  }

  /// Refresh the data without notification of the loading. If there is an error,
  /// it is thrown to the caller of this method and the result is not added in the
  /// stream by default.
  Future<T> refreshOrThrow({bool? addError}) async {
    _isInitialized = true;
    final addErrorNullSafe = addError ?? false;

    var result = await _pool.withResource(() async {
      var data = await _load();
      if (!data.hasError || addErrorNullSafe) {
        _setValue(data);
      }
      return data;
    });

    var error = result.error;
    if (error != null) {
      throw error;
    }

    return result.data!;
  }

  // Refresh the data without any loader and without errors (errors are absorbed).
  // This is generally called when we want to refresh the data after a Push-Notification.
  // Since this is not a user action, we don't want to disturb the current UI.
  void refreshSilently() async {
    _isInitialized = true;
    await _pool.withResource(() async {
      var data = await _load();
      if (data.hasData) {
        _setValue(data);
      }

      return data;
    });
  }

  void invalidate() {
    if (_isInitialized) {
      refresh();
    }
  }

  bool get hasListeners => _snapshots.hasListeners;

  void dispose() {
    _isDisposed = true;
    var previousValue = _snapshots.value.data;
    if (previousValue is Disposable) {
      previousValue.dispose();
    }
    unawaited(_snapshots.close());
  }
}
