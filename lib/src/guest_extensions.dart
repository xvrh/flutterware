import 'dart:async';
import 'dart:developer' as developer;

/// The guest's service extensions and events, kept where an in-process host
/// can reach them.
///
/// A guest — the previews catalog, drawn in an embedder process — answers
/// its host through `dart:developer` service extensions over the VM service,
/// and posts what changes as VM service events. That is the one channel a
/// plain embedder guest has. But the same guest can also run *inside* the
/// host, as a widget rather than a process: the studio's web demo, and a
/// widget test of the panel over a real entry. There is no VM service between
/// a widget and the tree it sits in, and there does not need to be: every
/// handler is a Dart function, so a host in the same process calls it.
///
/// So this is where the handlers are kept. [register] stores the handler and
/// registers it with the VM service too; [post] hands an event to both. A
/// host in another process notices nothing; a host in this one calls [call]
/// and listens to [events].
///
/// Registering twice under one name replaces the handler here and skips the
/// VM service, which refuses a second registration — the case is an
/// in-process host set up more than once in one process, a test suite.
abstract final class GuestExtensions {
  static final _handlers = <String, GuestExtensionHandler>{};
  static final _registered = <String>{};
  static final _events =
      StreamController<(String, Map<String, Object?>)>.broadcast();

  static void register(String method, GuestExtensionHandler handler) {
    _handlers[method] = handler;
    if (_registered.add(method)) {
      developer.registerExtension(method, handler);
    }
  }

  static void post(String kind, Map<String, Object?> data) {
    developer.postEvent(kind, data);
    _events.add((kind, data));
  }

  /// Whether a handler is registered under [method] in this process.
  static bool has(String method) => _handlers.containsKey(method);

  /// Calls the handler registered under [method], or null when there is none
  /// — the same answer the VM service gives for an extension a guest does not
  /// declare.
  static Future<developer.ServiceExtensionResponse?> call(
    String method,
    Map<String, String> args,
  ) async => _handlers[method]?.call(method, args);

  /// Every event posted under [kind], from now on.
  static Stream<Map<String, Object?>> events(String kind) =>
      _events.stream.where((e) => e.$1 == kind).map((e) => e.$2);
}

typedef GuestExtensionHandler =
    Future<developer.ServiceExtensionResponse> Function(
      String method,
      Map<String, String> parameters,
    );
