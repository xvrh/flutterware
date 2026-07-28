import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// The knob types, not the umbrella `ui_catalog.dart`: that one exports the
// demo annotations, which reach `package:flutter/widgets.dart` and would make
// `fw` unlinkable. `knob.dart` is plain Dart by design and says so.
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';

import '../embedder/protocol.dart';
import '../embedder/raw_frame.dart';
import 'devices.dart';
import 'catalog_entry.dart';
import '../embedder/guest_vm_service.dart';
import '../utils/run_dir.dart';
import 'compiler_daemon_client.dart';
import 'protocol.dart';

/// The catalog pipeline with no GUI involved: render an entry, ask what builds,
/// ask what knobs an entry declares.
///
/// The same pipeline the GUI drives, invoked by whoever asks — a button, `fw`,
/// or an agent. Nothing here touches Flutter, so it runs anywhere the daemon
/// does.
///
/// The guest is spawned with `--capture-raw`, which writes the composited frame
/// the user would have seen rather than re-rasterising it.
class HeadlessCatalog {
  HeadlessCatalog({required this.dartExecutable, required this.config});

  /// A real Dart VM — the Flutter SDK's `dart`, never the running executable
  /// when that is a Flutter app.
  final String dartExecutable;

  final DaemonConfig config;

  /// Screenshots [entryId] into [output], optionally with its knobs turned.
  ///
  /// Starts a daemon, compiles the entry, renders one frame, and shuts
  /// everything down. Fine for one entry; a batch wants a session that stays
  /// warm, which is why [captureAll] exists.
  ///
  /// [knobs] are raw strings — a flag and a JSON object both arrive as text —
  /// and are coerced to whatever kind the demo declared. A name the entry does
  /// not declare is an error naming the ones it does: a silently ignored knob
  /// produces a picture that looks right and is not.
  Future<CatalogCapture> capture({
    required String entryId,
    required String output,
    CaptureViewport viewport = CaptureViewport.panel,
    Map<String, String> knobs = const {},
  }) async {
    if (knobs.isEmpty) {
      var results = await captureAll(
        entryIds: [entryId],
        outputFor: (_) => output,
        viewport: viewport,
      );
      return CatalogCapture(file: results.values.single, knobs: const []);
    }
    return _withGuest(entryId: entryId, viewport: viewport, (guest) async {
      var applied = await guest.applyKnobs(entryId, knobs);
      return CatalogCapture(
        file: await guest.capture(output),
        knobs: applied.knobs,
      );
    });
  }

  /// Connects, compiles [entryId], launches one guest and hands it to [body].
  ///
  /// Everything that needs a *running* entry goes through here — a capture with
  /// knobs turned, and reading what knobs there are — so the daemon handshake,
  /// the entry check and the teardown exist once.
  Future<T> _withGuest<T>(
    Future<T> Function(_GuestSession guest) body, {
    required String entryId,
    required CaptureViewport viewport,
  }) async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    _GuestSession? guest;
    try {
      var known = {for (var entry in ready.entries) entry.id};
      if (!known.contains(entryId)) {
        throw ArgumentError.value(
          entryId,
          'entryId',
          'no such entry. Known ids: ${known.join(', ')}',
        );
      }
      // A whole kernel, not a delta: the guest loads it from disk at launch.
      var compiled = await daemon.select(entryId, full: true);
      if (!compiled.ok) {
        throw StateError('$entryId did not compile:\n${compiled.error}');
      }
      guest = await _GuestSession.start(
        hostPath: ready.hostPath,
        assetsDir: ready.assetsDir,
        icuData: ready.icuData,
        workDir: p.join(config.appPackageRoot, 'build', 'catalog'),
        viewport: viewport,
      );
      return await body(guest);
    } finally {
      await guest?.close();
      await daemon.close();
    }
  }

  /// Screenshots several entries against **one** daemon and **one** guest.
  ///
  /// The first entry pays a cold compile and a guest launch. Every entry after
  /// it is a hot reload and a capture request — the same economics as browsing,
  /// because it is the same mechanism.
  Future<Map<String, File>> captureAll({
    required List<String> entryIds,
    required String Function(String entryId) outputFor,
    CaptureViewport viewport = CaptureViewport.panel,
  }) async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    _GuestSession? guest;
    try {
      var known = {for (var entry in ready.entries) entry.id};
      for (var id in entryIds) {
        if (!known.contains(id)) {
          throw ArgumentError.value(
            id,
            'entryId',
            'no such entry. Known ids: ${known.join(', ')}',
          );
        }
      }

      var captured = <String, File>{};
      for (var id in entryIds) {
        if (guest == null) {
          // The guest loads the kernel from disk at launch, so the first entry
          // needs a whole one; afterwards a delta is all a live isolate wants.
          var compiled = await daemon.select(id, full: true);
          if (!compiled.ok) {
            throw StateError('$id did not compile:\n${compiled.error}');
          }
          guest = await _GuestSession.start(
            // The daemon builds the host and reports where it put it. Taking
            // it from the handshake rather than a caller's guess means there
            // is one answer to "where is the host binary", and it is the one
            // that was actually built.
            hostPath: ready.hostPath,
            assetsDir: ready.assetsDir,
            icuData: ready.icuData,
            workDir: p.join(config.appPackageRoot, 'build', 'catalog'),
            viewport: viewport,
          );
        } else {
          var compiled = await daemon.select(id);
          if (!compiled.ok) {
            throw StateError('$id did not compile:\n${compiled.error}');
          }
          await guest.reload(compiled.dill!);
        }
        captured[id] = await guest.capture(outputFor(id));
      }
      return captured;
    } finally {
      await guest?.close();
      await daemon.close();
    }
  }

  /// Which entries the compiler can actually build, and why the rest cannot.
  ///
  /// Needs no guest: the daemon compiles every wrapper into one program while
  /// it prepares, and quarantines the ones that fail. So the answer is already
  /// in the handshake, and this is one connection rather than one compile per
  /// entry.
  ///
  /// The scan cannot answer this. It parses and finds an entry; whether the
  /// entry *compiles* is a fact only the compiler holds, which is why nothing
  /// but the panel could ask before now.
  Future<CatalogCheck> check() async {
    var (daemon, ready) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    try {
      return CatalogCheck(
        servable: ready.entries,
        quarantined: ready.quarantined,
      );
    } finally {
      await daemon.close();
    }
  }

  /// The knobs [entryId] declares, read from a live guest.
  ///
  /// A knob is a runtime fact — a demo declares one by *asking* for it while it
  /// builds — so no amount of parsing finds them. The guest registers
  /// `ext.flutterware.parameters` and answers with what its last build
  /// declared.
  ///
  /// Empty when the entry declares none, or when the guest is old enough not to
  /// register the extension. That is an answer, not a failure.
  Future<KnobReport> knobs({
    required String entryId,
    CaptureViewport viewport = CaptureViewport.panel,
  }) => _withGuest(
    entryId: entryId,
    viewport: viewport,
    (guest) => guest.settledKnobs(entryId),
  );
}

/// Turns a knob value written as text into whatever kind the demo declared.
///
/// Everything arrives as text: a shell flag has no types, and a JSON object
/// from an agent may disagree with the demo about int versus double. The demo
/// is the authority, so this follows [KnobDescriptor.kind] rather than guessing
/// from the characters — `count=5` is an int for a demo that declared an int
/// and a string for one that declared a string.
Object? coerceKnob(KnobDescriptor knob, String value) => switch (knob.kind) {
  KnobKind.boolean => switch (value.toLowerCase()) {
    'true' || 'yes' || '1' => true,
    'false' || 'no' || '0' => false,
    _ => throw ArgumentError.value(value, knob.name, 'expected true or false'),
  },
  KnobKind.integer =>
    int.tryParse(value) ??
        (throw ArgumentError.value(value, knob.name, 'expected an integer')),
  KnobKind.number =>
    num.tryParse(value) ??
        (throw ArgumentError.value(value, knob.name, 'expected a number')),
  KnobKind.picker =>
    knob.options.contains(value)
        ? value
        : throw ArgumentError.value(
            value,
            knob.name,
            'expected one of: ${knob.options.join(', ')}',
          ),
  KnobKind.string => value,
};

/// A captured frame, and the knobs it was rendered with.
class CatalogCapture {
  CatalogCapture({required this.file, required this.knobs});

  final File file;

  /// What the entry reported *after* the values were applied — so a clamped or
  /// ignored value is visible rather than assumed.
  final List<KnobDescriptor> knobs;
}

/// What the compiler could and could not build.
class CatalogCheck {
  CatalogCheck({required this.servable, required this.quarantined});

  final List<CatalogEntry> servable;

  /// Entries the compiler refused, each with its diagnostics verbatim.
  final List<QuarantinedEntry> quarantined;

  bool get ok => quarantined.isEmpty;
}

/// One embedder guest, kept alive across captures.
class _GuestSession {
  _GuestSession._(
    this._guest,
    this._connection,
    this._server,
    this._reader,
    this._vmService,
    this._workDir,
  );

  final Process _guest;
  final Socket _connection;
  final ServerSocket _server;
  final FrameReader _reader;
  final GuestVmService _vmService;
  final String _workDir;

  final _captures = <String, Completer<void>>{};

  static Future<_GuestSession> start({
    required String hostPath,
    required String assetsDir,
    required String icuData,
    required String workDir,
    required CaptureViewport viewport,
  }) async {
    // Not under [workDir]: a unix socket path is capped at 104 bytes, and a
    // build directory inside a worktree already spends most of that. The
    // derived name keeps two concurrent captures from colliding.
    var key = sha1.convert(utf8.encode(workDir)).toString().substring(0, 12);
    var socketPath = checkSocketPath(
      p.join(flutterwareRunDir(), 'shot-$key.sock'),
    );
    var socket = File(socketPath);
    if (socket.existsSync()) socket.deleteSync();
    var server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );

    var guest = await Process.start(hostPath, [
      assetsDir,
      icuData,
      socketPath,
      '${viewport.width}',
      '${viewport.height}',
    ]);
    var vmServiceUri = Completer<String>();
    guest.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
          if (match != null && !vmServiceUri.isCompleted) {
            vmServiceUri.complete(match.group(1));
          }
        });
    unawaited(guest.stderr.drain<void>());

    var connected = await Future.any<Object?>([server.first, guest.exitCode]);
    if (connected is! Socket) {
      throw StateError('the guest exited before connecting');
    }

    var session = _GuestSession._(
      guest,
      connected,
      server,
      FrameReader(),
      await GuestVmService.connect(await vmServiceUri.future),
      workDir,
    );
    connected.listen(session._onData);
    // Argv carried the buffer size; this carries what the buffer *means*. The
    // ratio and the safe areas have no other way in, and without them a phone
    // capture is a correctly-sized picture of the wrong layout.
    session._resize(viewport);
    return session;
  }

  void _resize(CaptureViewport viewport) => _connection.add(
    encodeMessage(
      ResizeMessage(
        width: viewport.width,
        height: viewport.height,
        pixelRatio: viewport.pixelRatio,
        insetTop: viewport.insetTop,
        insetRight: viewport.insetRight,
        insetBottom: viewport.insetBottom,
        insetLeft: viewport.insetLeft,
      ),
    ),
  );

  void _onData(List<int> chunk) {
    for (var message in _reader.addBytes(chunk)) {
      if (message is CapturedMessage) {
        _captures.remove(message.path)?.complete();
      } else if (message is ErrorMessage) {
        for (var pending in _captures.values) {
          if (!pending.isCompleted) {
            pending.completeError(StateError(message.message));
          }
        }
        _captures.clear();
      }
    }
  }

  Future<void> reload(String dill) => _vmService.reload(dill);

  /// What [entryId] declares, once the guest has actually built it.
  ///
  /// **Renders a frame first, and throws it away.** A knob is declared while
  /// the demo builds, and a headless host draws nothing until a frame is asked
  /// for — so without this the answer is always "no knobs". The panel never
  /// meets this because it drives frames continuously; measured here by
  /// getting an empty report from a demo that plainly has three.
  ///
  /// Then retried while the report names another entry, exactly as the panel
  /// does: a read landing between the reload and the frame describes whatever
  /// was on screen before.
  Future<KnobReport> settledKnobs(String entryId) async {
    await _renderScratchFrame();
    for (var attempt = 0; attempt < 20; attempt++) {
      var json = await _vmService.callExtension('ext.flutterware.parameters');
      // A guest without the extension: not an error, just no knobs.
      if (json == null) return KnobReport.empty;
      var report = KnobReport.fromJson(json);
      if (report.entryId == entryId) return report;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return KnobReport.empty;
  }

  /// Draws one frame nobody looks at, so the demo has built.
  Future<void> _renderScratchFrame() async {
    var scratch = p.join(_workDir, 'knobs.scratch.png');
    await capture(scratch);
    var file = File(scratch);
    if (file.existsSync()) file.deleteSync();
  }

  /// Turns [values] on [entryId], and reports what the entry says afterwards.
  ///
  /// Coerced to the kind the demo declared, because everything arrives as text:
  /// a shell flag has no types and a JSON object from an agent may disagree
  /// with the demo about int versus double.
  Future<KnobReport> applyKnobs(
    String entryId,
    Map<String, String> values,
  ) async {
    var declared = await settledKnobs(entryId);
    var known = {for (var knob in declared.knobs) knob.name: knob};

    for (var entry in values.entries) {
      var knob = known[entry.key];
      if (knob == null) {
        throw ArgumentError.value(
          entry.key,
          'knob',
          known.isEmpty
              ? 'this entry declares no knobs'
              : 'no such knob on $entryId. Declared: ${known.keys.join(', ')}',
        );
      }
      await _vmService.callExtension(
        'ext.flutterware.setParameter',
        args: {
          'payload': jsonEncode({
            'name': entry.key,
            'value': coerceKnob(knob, entry.value),
          }),
        },
      );
    }

    // Read once at the end: a demo's build decides what knobs exist, so
    // turning one can reveal or retire another, and only the settled set is
    // worth reporting.
    return values.isEmpty ? declared : await settledKnobs(entryId);
  }

  /// Asks the guest to write its next frame, and waits for the ack.
  Future<File> capture(String output) async {
    var rawFrame = p.join(_workDir, 'screenshot.rawframe');
    var raw = File(rawFrame);
    if (raw.existsSync()) raw.deleteSync();

    var done = _captures[rawFrame] = Completer<void>();
    _connection.add(encodeMessage(CaptureMessage(rawFrame)));
    await _connection.flush();
    await done.future.timeout(const Duration(seconds: 30));

    var image = decodeRawFrame(raw.readAsBytesSync());
    var file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image));
    raw.deleteSync();
    return file;
  }

  Future<void> close() async {
    await _vmService.close();
    _connection.add(encodeMessage(const ShutdownMessage()));
    await _connection.flush();
    await _connection.close();
    _guest.kill();
    await _server.close();
  }
}
