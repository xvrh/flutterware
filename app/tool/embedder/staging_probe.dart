import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart' as wire;
import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:flutterware_app/src/previews/debug_flags.dart';
import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// Drives a real catalog guest and checks that **staging changes behaviour**,
/// not just pixels.
///
/// The one assertion that covers the whole chain — the panel's wire, the C
/// host, the engine's pointer bookkeeping, `ext.flutter.platformOverride` and
/// `debugDefaultTargetPlatformOverride` — is what tapping outside a focused
/// field does, because the framework decides it from the platform *and* the
/// pointer kind:
///
/// - staged as a phone, touched: the field keeps focus, so typing carries on
///   landing in it — which is the phone convention, and what a fake keyboard
///   has to sit on;
/// - staged as nothing, clicked: the field loses focus, and typing goes
///   nowhere.
///
/// A screenshot cannot see this, and neither can a smoke test that only proves
/// the guest survived the message.
///
/// Needs the previews in `examples/example/demo/input.dart`, whose field
/// echoes its content as a `Text` — see `input_probe.dart`.
///
/// Usage: `dart run tool/embedder/staging_probe.dart [projectRoot]`
Future<void> main(List<String> args) async {
  var packageRoot = Directory.current.path;
  var projectRoot = args.isNotEmpty
      ? args[0]
      : p.normalize(p.join(packageRoot, '..', 'examples', 'example'));
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
  _Guest? guest;
  try {
    var entry = ready.entries
        .firstWhere((e) => e.id.endsWith('#textFields'))
        .id;
    var compiled = await daemon.select(entry, full: true);
    if (!compiled.ok) {
      throw StateError('$entry did not compile: ${compiled.error}');
    }
    guest = await _Guest.start(await daemon.hostPath(), ready);

    // **Each half is a delta, not a literal.** Staging the guest does *not*
    // remount the demo — `platformOverride` reassembles, which rebuilds while
    // keeping every `State` — so the field carries whatever the previous half
    // typed into it, and an expectation spelled as a whole string is wrong
    // from the second half onwards. This probe said `'z'` there for a while
    // and passed anyway: it was calling an extension deleted the day the
    // framework's own switch replaced it, and `callExtension` swallows an
    // unknown method rather than raising.

    // Staged as a phone, driven by a finger: the field keeps focus, so the
    // letter after the tap lands in it.
    await guest.stage(DevicePlatform.ios);
    await guest.report('staged ios');
    var held = await guest.echo();
    guest.type('z');
    await guest.settle();
    await guest.report('typed z');
    guest.tap(450, 650, touch: true);
    await guest.settle();
    await guest.report('touched outside');
    guest.type('q');
    await guest.settle();
    var phone = await guest.echo();
    stdout.writeln('[probe] staged ios, touched outside: echo "$phone"');
    if (phone != '${held}zq') {
      failures.add(
        'a touch outside took the focus on a phone (echo "$phone", wanted '
        '"${held}zq")',
      );
    }

    // Staged as nothing, driven by a mouse — the desktop rule, which is what
    // the guest did on every device before staging existed. The letter after
    // the click goes nowhere.
    await guest.stage(null);
    await guest.report('staged fit');
    held = await guest.echo();
    guest.type('z');
    await guest.settle();
    await guest.report('typed z');
    guest.tap(450, 650, touch: false);
    await guest.settle();
    await guest.report('clicked outside');
    guest.type('q');
    await guest.settle();
    var desktop = await guest.echo();
    stdout.writeln('[probe] staged fit, clicked outside: echo "$desktop"');
    if (desktop != '${held}z') {
      failures.add(
        'a click outside left the focus on the desktop (echo "$desktop", '
        'wanted "${held}z")',
      );
    }
  } finally {
    await guest?.close();
    await daemon.close();
  }

  if (failures.isEmpty) {
    stdout.writeln('[probe] PASS: staging decides what tapping outside means');
    exit(0);
  }
  for (var failure in failures) {
    stdout.writeln('[probe] FAIL: $failure');
  }
  exit(1);
}

/// The two letters this probe types, spelled out because a pure-Dart tool
/// cannot import `LogicalKeyboardKey`.
const _keys = {'z': (0x0000007A, 0x0007001D), 'q': (0x00000071, 0x00070014)};

class _Guest {
  _Guest._(this._process, this._connection, this._server, this._vm);

  final Process _process;
  final Socket _connection;
  final ServerSocket _server;
  final GuestVmService _vm;

  static Future<_Guest> start(String hostPath, DaemonReady ready) async {
    var socketPath = checkSocketPath(
      p.join(flutterwareRunDir(), 'staging-${ready.sessionId}.sock'),
    );
    var socketFile = File(socketPath);
    if (socketFile.existsSync()) socketFile.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    var process = await Process.start(hostPath, [
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
          if (!line.startsWith('FW-PROBE')) stdout.writeln('[guest] $line');
          var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
          if (match != null && !vmUri.isCompleted) {
            vmUri.complete(match.group(1));
          }
        });
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((line) => stdout.write('[guest:err] $line'));

    // ignore: close_sinks
    var connection = await server.first;
    // **Drained, even though this probe reads nothing.** The host writes a
    // frame-ready message per rendered frame; an unread socket fills, its
    // `send` blocks the raster thread, and the guest simply stops producing
    // frames — which looks exactly like a demo that will not rebuild.
    connection.listen((_) {});
    var guest = _Guest._(
      process,
      connection,
      server,
      await GuestVmService.connect(await vmUri.future),
    );
    await guest.settle();
    return guest;
  }

  Future<void> settle() => Future.delayed(const Duration(seconds: 2));

  /// Through [stageGuestPlatform], which is the *panel's own* call — a probe
  /// that spelled the extension itself would go on passing after the panel
  /// stopped using it, which is exactly what happened: this said
  /// `ext.flutterware.setStaging` for a while, an extension deleted the day
  /// the framework's own switch replaced it, and `callExtension` swallows an
  /// unknown method rather than raising.
  Future<void> stage(DevicePlatform? platform) async {
    await stageGuestPlatform(_vm, platform);
    await settle();
  }

  /// Where the demo is, at a step — its echo and its caret, which is what says
  /// whether anything is focused at all.
  Future<void> report(String what) async {
    var tree = jsonEncode(await _vm.callExtension('ext.flutterware.tree'));
    var echo = RegExp(r'echo: ?([^"\\]*)').firstMatch(tree)?.group(1);
    var sel = RegExp(r'sel: ?([^"\\]*)').firstMatch(tree)?.group(1);
    stdout.writeln('[probe] $what: echo "$echo" sel "$sel"');
  }

  /// What the demo's field currently holds, read off its own `Text`.
  Future<String?> echo() async {
    var tree = jsonEncode(await _vm.callExtension('ext.flutterware.tree'));
    return RegExp(r'echo: ?([^"\\]*)').firstMatch(tree)?.group(1);
  }

  void type(String character) {
    var (logical, physical) = _keys[character]!;
    var now = DateTime.now().microsecondsSinceEpoch;
    for (var kind in [wire.KeyEventKind.down, wire.KeyEventKind.up]) {
      _send(
        wire.KeyEventMessage(
          kind: kind,
          physicalKey: physical,
          logicalKey: logical,
          modifiers: 0,
          timestampMicros: now,
          character: kind == wire.KeyEventKind.down ? character : null,
        ),
      );
    }
  }

  void tap(double x, double y, {required bool touch, bool addRemove = true}) {
    var now = DateTime.now().microsecondsSinceEpoch;
    var phases = [
      if (addRemove) wire.PointerPhase.add,
      wire.PointerPhase.down,
      wire.PointerPhase.up,
      if (touch && addRemove) wire.PointerPhase.remove,
    ];
    for (var phase in phases) {
      _send(
        wire.PointerEventMessage(
          phase: phase,
          x: x,
          y: y,
          buttons: phase == wire.PointerPhase.down ? 1 : 0,
          scrollDeltaX: 0,
          scrollDeltaY: 0,
          timestampMicros: now,
          touch: touch,
        ),
      );
    }
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
