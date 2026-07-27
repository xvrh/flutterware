import 'dart:async';

/// A broadcast stream that always has a current value.
///
/// This is the one notification primitive in the codebase. It replaces
/// `ChangeNotifier` / `ValueListenable` because every interesting boundary here
/// is a stream — the daemon streams job events, the GUI, `fw` and MCP consume
/// the same feeds — and a callback listenable crosses neither an isolate nor a
/// socket. Choosing callbacks would mean writing a stream adapter at every
/// boundary and adapting back.
///
/// It is also how laziness stops being hand-rolled. `2026-07-26-packages-and-
/// laziness.md` states the rule as *work starts when something subscribes and
/// stops when the last subscriber leaves*, and implements the first half by
/// overriding `addListener`. [onListen] and [onCancel] below are that rule,
/// both halves, from `dart:async`:
///
/// ```dart
/// var entries = ValueStream<List<Entry>>(
///   const [],
///   onListen: () => _watcher.start(),
///   onCancel: () => _watcher.stop(),
/// );
/// ```
///
/// Deliberately small: [stream] is an ordinary broadcast [Stream], so `map`,
/// `where`, `distinct` and anything from `package:async` already compose over
/// it. Nothing is re-exposed here that `Stream` already does well.
class ValueStream<T> {
  ValueStream(
    T initial, {
    void Function()? onListen,
    void Function()? onCancel,
    this.debugName,
  }) : _value = initial {
    _controller = StreamController<T>.broadcast(
      onListen: onListen,
      onCancel: onCancel,
      sync: true,
    );
  }

  late final StreamController<T> _controller;

  /// Only ever used in error messages and logs.
  final String? debugName;

  T _value;

  /// The current value, readable synchronously and without subscribing.
  ///
  /// Reading never starts work — that is what makes it safe for a
  /// `PluginReport` to be a pure read of cached state.
  T get value => _value;

  /// Publishes [next], unless it is `==` to the current value.
  ///
  /// The equality skip matches `ValueNotifier`, which is what the call sites
  /// being migrated expect. For a `T` that is mutated in place rather than
  /// replaced, use [emit].
  set value(T next) {
    if (_value == next) return;
    emit(next);
  }

  /// Publishes [next] unconditionally.
  void emit(T next) {
    if (_controller.isClosed) {
      throw StateError('Cannot emit on a closed ValueStream ($debugName).');
    }
    _value = next;
    _controller.add(next);
  }

  /// Reports [error] to subscribers. The current [value] is left alone: an
  /// error is news about the source, not a new value for it.
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_controller.isClosed) return;
    _controller.addError(error, stackTrace);
  }

  /// The current value, followed by every subsequent one.
  ///
  /// Each subscriber is replayed the value that was current when it subscribed,
  /// so a late listener is never left with nothing to render — the failure mode
  /// a raw broadcast stream has and the reason this type exists.
  Stream<T> get stream => Stream.multi((controller) {
    controller.add(_value);
    if (_controller.isClosed) {
      controller.close();
      return;
    }
    var subscription = _controller.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  /// Sugar for `stream.listen`.
  StreamSubscription<T> listen(
    void Function(T value) onData, {
    Function? onError,
    void Function()? onDone,
  }) => stream.listen(onData, onError: onError, onDone: onDone);

  bool get hasListeners => _controller.hasListener;

  bool get isClosed => _controller.isClosed;

  /// Ends the stream. Subscribers get `onDone`; [value] stays readable, because
  /// callers holding the object should not start seeing nulls at teardown.
  Future<void> close() => _controller.close();
}
