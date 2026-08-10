import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'log.dart';

/// Keeps what the preview printed, where it can be asked for.
///
/// **The gap this closes.** The guest's `print` reached the *host's* console and
/// nowhere else — the GUI could not show it, `fw` could not return it, and an
/// agent driving a demo could not read the one thing a developer reaches for
/// first. The host does hold the guest's stdout, but only because the host
/// spawned it: a reader attached to a session somebody else is driving has a VM
/// service URI and nothing more. So the buffer has to be in the guest, exactly
/// as [GuestErrors]' is, and for the same reason.
///
/// **Both pulled and pushed.** The buffer answers "what has been printed"; the
/// events say "and here is another one" without waiting for a poll. A console
/// that lagged three seconds behind the demo would be a console nobody trusts,
/// and the measurement behind `GuestWatch` already established that the event
/// channel carries 60Hz without batching. A reader takes the buffer and
/// subscribes at the same moment, and drops the overlap by
/// [InspectLogLine.sequence].
class GuestLogs {
  GuestLogs._();

  static final instance = GuestLogs._();

  /// Bounded, because a demo printing from `build` prints on every frame and an
  /// unbounded buffer in a live app is a leak.
  ///
  /// Far larger than [GuestErrors]' fifty, and the difference is the point:
  /// errors are *distinct* failures with repeats counted, so fifty is a great
  /// many. Log lines are occurrences, and a demo that prints one line per frame
  /// fills five hundred in eight seconds. This is a scrollback, not a summary.
  static const _limit = 500;

  final _lines = <InspectLogLine>[];
  var _sequence = 0;
  var _dropped = 0;
  String? _entryId;

  /// Marks our own zone, so [install] can refuse to nest.
  ///
  /// A flag saying "install has run" was the first version and was subtly
  /// wrong in both directions: nesting is the real hazard — the inner zone
  /// forwards to the outer one's handler, so every line would be recorded twice
  /// — and that hazard is about being *inside* the zone, not about having once
  /// entered it. A flag also made a second, independent install after the first
  /// had returned silently do nothing, which is exactly what a test does.
  static final _marker = Object();

  /// Runs [body] in a zone whose `print` is recorded as well as printed.
  ///
  /// **A zone rather than a `debugPrint` override**, because `debugPrint` is
  /// only what the framework uses; a demo calls `print`, and so does anything it
  /// depends on. `debugPrint` ends in `print` too, so one seam catches both.
  ///
  /// **And it forwards, always.** Swallowing the line to collect it would trade
  /// a thing you can see for a thing you can query — and worse, the host reads
  /// the VM service URI and the `FW-PROBE:` lines off this very stream, so a
  /// zone that kept them would stop the session starting at all.
  R install<R>(R Function() body) {
    if (Zone.current[_marker] == true) return body();
    return runZoned(
      body,
      zoneValues: {_marker: true},
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          // `FW-PROBE:` is the harness talking to itself — the generated
          // entrypoint prints the rendered text every 200ms so a headless check
          // can assert on it. It is not the demo's output, and a console that
          // showed it would show five lines a second of it and nothing else.
          if (!line.startsWith('FW-PROBE:')) _record(line);
          parent.print(zone, line);
        },
      ),
    );
  }

  void _record(String text) {
    var line = InspectLogLine(
      sequence: ++_sequence,
      text: text,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    _lines.add(line);
    while (_lines.length > _limit) {
      _lines.removeAt(0);
      _dropped++;
    }
    // Posted from inside the zone's print handler, which is safe only because
    // `postEvent` does not print. If it ever did, this would be a demo that
    // printed once and hung.
    developer.postEvent(eventKind, line.toJson());
  }

  /// The event a console subscribes to.
  static const eventKind = 'flutterware.log';

  /// Forgets the previous entry's output.
  ///
  /// The same boundary [GuestErrors.resetFor] draws, and the same argument: the
  /// panel scopes every other pane to the selected entry, and a console that
  /// did not would be the one place showing another demo's words under this
  /// demo's name.
  ///
  /// **Only on a change of entry**, because this runs from `didUpdateWidget`
  /// and therefore on every rebuild — turning a knob would otherwise wipe what
  /// the previous knob printed, which is the one thing you turned it to see.
  void resetFor(String entryId) {
    if (_entryId == entryId) return;
    _entryId = entryId;
    _lines.clear();
    _dropped = 0;
  }

  /// Forgets everything, keeping the entry — the console's own clear button.
  void clear() {
    _lines.clear();
    _dropped = 0;
  }

  InspectLogs describe() =>
      InspectLogs(entryId: _entryId, lines: [..._lines], dropped: _dropped);

  /// Registers the extensions. Call once, before `runApp`.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.logs', (_, _) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(describe().toJson()),
      );
    });
    developer.registerExtension('ext.flutterware.clearLogs', (_, _) async {
      clear();
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'cleared': true}),
      );
    });
  }
}
