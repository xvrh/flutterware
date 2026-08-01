import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/catalog/compiler_daemon_client.dart';
import 'package:flutterware_app/src/catalog/protocol.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart' as wire;
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// Drives a real catalog guest and checks that input *arrives* — that typing
/// reaches a field and a wheel scrolls a list.
///
/// The one check that covers the whole chain: the panel's wire messages, the
/// C host, the engine, and the guest's replacements for the platform plumbing
/// it does not have ([GuestKeyboard], [GuestTextInput]). `input_smoke.dart`
/// only proves the guest survives the messages, which is what let keyboard
/// input look fine while every key sat undelivered in a framework queue.
///
/// Needs the previews in `examples/example/demo/input.dart`, which report their
/// state as `Text` so a tree read can see it.
///
/// Usage: `dart run tool/embedder/input_probe.dart [projectRoot]`
Future<void> main(List<String> args) async {
  var packageRoot = Directory.current.path;
  var projectRoot = args.isNotEmpty
      ? args[0]
      : p.normalize(p.join(packageRoot, '..', 'examples', 'example'));
  // <sdk>/bin/cache/dart-sdk/bin/dartvm — four levels up from the bin holding
  // the running dart.
  var flutterSdkRoot = p.normalize(
    p.join(p.dirname(Platform.resolvedExecutable), '..', '..', '..', '..'),
  );

  var (daemon, ready) = await CompilerDaemonClient.connect(
    dartExecutable: Platform.resolvedExecutable,
    config: DaemonConfig.forPackage(
      appToolDirectory: packageRoot,
      packageRoot: projectRoot,
      flutterSdkRoot: flutterSdkRoot,
      roots: ['demo'],
    ),
  );

  var failures = <String>[];
  try {
    await _withGuest(daemon, ready, 'textFields', (guest) async {
      var before = await guest.tree();
      // "zq" — two letters in none of the demo's chrome, so finding them in
      // the echo cannot be a false positive.
      guest.type('z', logical: 0x0000007A, physical: 0x0007001D);
      guest.type('q', logical: 0x00000071, physical: 0x00070014);
      await guest.settle();
      var after = await guest.tree();

      String? echo(String tree) =>
          RegExp(r'echo: ?([^"\\]*)').firstMatch(tree)?.group(1);
      stdout.writeln(
        '[probe] echo before: "${echo(before)}" after: '
        '"${echo(after)}"',
      );
      if (echo(after) != 'zq') {
        failures.add('typing did not reach the field (echo "${echo(after)}")');
      }

      // Backspace and the arrows, which reach a field only as named IME
      // commands on macOS — the whole reason GuestTextInput maps selectors.
      guest.press(logical: _backspace.$1, physical: _backspace.$2);
      await guest.settle();
      var deleted = echo(await guest.tree());
      stdout.writeln('[probe] echo after backspace: "$deleted"');
      if (deleted != 'z') {
        failures.add('backspace did not delete (echo "$deleted")');
      }

      guest.press(logical: _arrowLeft.$1, physical: _arrowLeft.$2);
      await guest.settle();
      var tree = await guest.tree();
      var caret = RegExp(r'sel: ?(\d+),').firstMatch(tree)?.group(1);
      stdout.writeln('[probe] caret after arrow-left: $caret');
      if (caret != '0') {
        failures.add('the arrow did not move the caret (at $caret)');
      }
    });

    await _withGuest(daemon, ready, 'scrolling', (guest) async {
      var before = await guest.tree();
      // Three wheel notches at the middle of the list.
      for (var i = 0; i < 3; i++) {
        guest.scroll(x: 450, y: 350, deltaY: 120);
      }
      await guest.settle();
      var after = await guest.tree();

      int? topRow(String tree) {
        var rows = RegExp(
          r'Row (\d+)',
        ).allMatches(tree).map((m) => int.parse(m.group(1)!)).toList();
        return rows.isEmpty ? null : rows.reduce((a, b) => a < b ? a : b);
      }

      stdout.writeln(
        '[probe] top row before: ${topRow(before)} after: ${topRow(after)}',
      );
      var from = topRow(before);
      var to = topRow(after);
      if (from == null || to == null || to <= from) {
        failures.add('the wheel did not scroll the list ($from -> $to)');
      }
    });
  } finally {
    await daemon.close();
  }

  if (failures.isEmpty) {
    stdout.writeln('[probe] PASS: typing and scrolling both reach the guest');
    exit(0);
  }
  for (var failure in failures) {
    stdout.writeln('[probe] FAIL: $failure');
  }
  exit(1);
}

/// (logical, physical) for the editing keys this probe presses. Spelled out
/// because a pure-Dart tool cannot import `LogicalKeyboardKey`, and a wrong id
/// looks exactly like a broken feature — it did, once, during this
/// investigation.
const _backspace = (0x00100000008, 0x0007002A);
const _arrowLeft = (0x00100000302, 0x00070050);

Future<void> _withGuest(
  CompilerDaemonClient daemon,
  DaemonReady ready,
  String entrySuffix,
  Future<void> Function(_Guest guest) body,
) async {
  var entry = ready.entries
      .firstWhere(
        (e) => e.id.endsWith('#$entrySuffix'),
        orElse: () => throw StateError(
          'no entry #$entrySuffix. Known: ${ready.entries.map((e) => e.id)}',
        ),
      )
      .id;
  stdout.writeln('[probe] entry: $entry');
  var compiled = await daemon.select(entry, full: true);
  if (!compiled.ok) {
    throw StateError('$entry did not compile: ${compiled.error}');
  }

  var guest = await _Guest.start(ready);
  try {
    await body(guest);
  } finally {
    await guest.close();
  }
}

/// One running guest, with just enough of a driver to send input and read back
/// what the demo shows.
class _Guest {
  _Guest._(this._process, this._connection, this._server, this._vm);

  final Process _process;
  final Socket _connection;
  final ServerSocket _server;
  final GuestVmService _vm;

  static Future<_Guest> start(DaemonReady ready) async {
    var socketPath = checkSocketPath(
      p.join(flutterwareRunDir(), 'probe-${ready.sessionId}.sock'),
    );
    var socketFile = File(socketPath);
    if (socketFile.existsSync()) socketFile.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    var process = await Process.start(ready.hostPath, [
      ready.assetsDir,
      ready.icuData,
      socketPath,
      '900',
      '700',
    ]);
    var vmUri = Completer<String>();
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
          if (match != null && !vmUri.isCompleted) {
            vmUri.complete(match.group(1));
          }
        });
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((line) => stdout.write('[guest:err] $line'));

    // Closed by [close], which the caller's `finally` reaches.
    // ignore: close_sinks
    var connection = await server.first;
    var reader = wire.FrameReader();
    connection.listen((chunk) {
      for (var message in reader.addBytes(chunk)) {
        if (message is wire.ErrorMessage) {
          stdout.writeln('[guest:proto] ${message.message}');
        }
      }
    });

    var guest = _Guest._(
      process,
      connection,
      server,
      await GuestVmService.connect(await vmUri.future),
    );
    await guest.settle();
    return guest;
  }

  /// Long enough for the guest to build and answer — this is a diagnostic
  /// run by hand, so it buys certainty with a second rather than polling.
  Future<void> settle() => Future.delayed(const Duration(seconds: 2));

  Future<String> tree() async =>
      jsonEncode(await _vm.callExtension('ext.flutterware.tree'));

  void type(String character, {required int logical, required int physical}) {
    var now = DateTime.now().microsecondsSinceEpoch;
    _send(
      wire.KeyEventMessage(
        kind: wire.KeyEventKind.down,
        physicalKey: physical,
        logicalKey: logical,
        modifiers: 0,
        timestampMicros: now,
        character: character,
      ),
    );
    _send(
      wire.KeyEventMessage(
        kind: wire.KeyEventKind.up,
        physicalKey: physical,
        logicalKey: logical,
        modifiers: 0,
        timestampMicros: now,
      ),
    );
  }

  /// A key with no character — an editing key, not text.
  void press({required int logical, required int physical}) {
    var now = DateTime.now().microsecondsSinceEpoch;
    for (var kind in [wire.KeyEventKind.down, wire.KeyEventKind.up]) {
      _send(
        wire.KeyEventMessage(
          kind: kind,
          physicalKey: physical,
          logicalKey: logical,
          modifiers: 0,
          timestampMicros: now,
        ),
      );
    }
  }

  void scroll({required double x, required double y, required double deltaY}) {
    _send(
      wire.PointerEventMessage(
        phase: wire.PointerPhase.hover,
        x: x,
        y: y,
        buttons: 0,
        scrollDeltaX: 0,
        scrollDeltaY: deltaY,
        timestampMicros: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  void _send(wire.EmbedderMessage message) =>
      _connection.add(wire.encodeMessage(message));

  Future<void> close() async {
    _send(const wire.ShutdownMessage());
    await _connection.flush();
    _process.kill();
    await _vm.close();
    await _server.close();
  }
}
