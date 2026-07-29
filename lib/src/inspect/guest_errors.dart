import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'error.dart';

/// Catches what the framework reports while an entry builds and paints, so
/// that "it rendered" and "it rendered without exploding" stop being the same
/// answer.
///
/// A demo that throws paints Flutter's red `ErrorWidget` and **nothing else
/// changes**: the compile succeeded, the reload succeeded, the capture
/// succeeded, and every check that asserts on those passes while the picture is
/// an error. The generated entrypoint has printed `FW-ERROR:` to stdout for a
/// while, which makes it visible to a human watching a terminal and to nothing
/// else — the headless session reads stdout only to find the VM service URI.
///
/// This is the same information kept where it can be asked for.
class GuestErrors {
  GuestErrors._();

  static final instance = GuestErrors._();

  /// Bounded, because a demo that throws in `build` throws on every frame and
  /// an unbounded buffer in a live app is a leak. Distinct errors, not
  /// occurrences — repeats are counted rather than stored.
  static const _limit = 50;

  final _errors = <String, InspectError>{};

  String? _entryId;

  /// Installs the handler. Call once, before `runApp`.
  ///
  /// Chains rather than replaces: `FlutterError.presentError` is what puts the
  /// error on the console and in the red box, and swallowing that to collect
  /// it would trade a visible failure for a queryable one.
  void install() {
    var previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _record(details);
      // Kept, and kept first: `headless_check` greps for this line, and a
      // human watching the terminal is still the fastest reader there is.
      // ignore: avoid_print
      print('FW-ERROR: ${details.exceptionAsString()}');
      (previous ?? FlutterError.presentError)(details);
    };
  }

  void _record(FlutterErrorDetails details) {
    var error = InspectError(
      exception: details.exceptionAsString(),
      library: details.library,
      context: details.context?.toDescription(),
    );
    var existing = _errors[error.key];
    if (existing != null) {
      _errors[error.key] = InspectError(
        exception: existing.exception,
        library: existing.library,
        context: existing.context,
        count: existing.count + 1,
      );
      return;
    }
    if (_errors.length >= _limit) return;
    _errors[error.key] = error;
  }

  /// Forgets the previous entry's errors.
  ///
  /// Called from the same place the knobs and axes reset, and for the same
  /// reason: carrying one entry's failures into the next reports a demo as
  /// broken because the one before it was.
  void resetFor(String entryId) {
    if (_entryId == entryId) return;
    _entryId = entryId;
    _errors.clear();
  }

  InspectErrors describe() =>
      InspectErrors(entryId: _entryId, errors: [..._errors.values]);

  /// Registers the extension. Call once, before `runApp`.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.errors', (_, _) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(describe().toJson()),
      );
    });
  }
}
