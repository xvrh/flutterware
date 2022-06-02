import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';

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

  R when<R>(
      {required R Function(T) data,
      required R Function(T?) loading,
      required R Function(Object) error}) {
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

class DataLoader<T extends Object>
    implements ChangeNotifier, ValueListenable<Snapshot<T>> {
  final Future<T> Function() _loader;
  final String debugName;
  final bool lazy;
  final LoadingMode? loadingMode;
  final _value = ValueNotifier<Snapshot<T>>(const Snapshot());
  final _pool = Pool(1);
  bool _isInitialized = false;
  bool _isDisposed = false;

  DataLoader({
    required Future<T> Function() loader,
    bool? lazy,
    this.loadingMode,
    T? seed,
    required this.debugName,
  })  : _loader = loader,
        lazy = lazy ?? true {
    if (seed != null) {
      _isInitialized = true;
      _setValue(Snapshot(data: seed));
    } else if (!this.lazy) {
      refresh();
    }
  }

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

  @override
  Snapshot<T> get value => _value.value;

  void _setValue(Snapshot<T> snapshot) {
    if (_isDisposed) return;

    var previousValue = _value.value.data;
    _value.value = snapshot;
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

  @override
  void addListener(VoidCallback listener) {
    _value.addListener(listener);

    if (!_isInitialized) {
      refresh();
    }
  }

  @override
  bool get hasListeners => _value.hasListeners;

  @override
  void notifyListeners() {
    _value.notifyListeners();
  }

  @override
  void removeListener(VoidCallback listener) {
    _value.removeListener(listener);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _value.dispose();
  }
}
