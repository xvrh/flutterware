# Flutter Embedder — Step 3a (Plan 2): Live texture display in the GUI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display the out-of-process embedder guest's live, animated, interactive output inside the flutterware desktop GUI via an external `Texture`, with the panel resizable and forwarding pointer/keyboard input.

**Architecture:** A native macOS plugin (`EmbedderTexturePlugin`) registers an external `FlutterTexture` with the host engine's texture registrar and wraps the guest's shared `IOSurface`s as `CVPixelBuffer`s. A Dart runtime (`EmbeddedEngine`) builds and spawns the guest, owns the control socket, and bridges `FrameReady`/`SurfacesAllocated` to the plugin and `Resize`/`PointerEvent`/`KeyEvent` back to the guest. A dev-harness screen hosts the `Texture` widget with input and resize wiring.

**Tech Stack:** Dart/Flutter, Swift (`FlutterMacOS`, `CoreVideo`, `IOSurface`), the wire protocol from Plan 1.

**Reference spec:** `docs/superpowers/specs/2026-05-15-flutter-embedder-step3a-design.md`

**Prerequisite:** Plan 1 (`2026-05-15-flutter-embedder-step3a-guest.md`) is complete and merged — `protocol.dart`, `embedder_build.dart`, the long-lived C guest, and `live_bridge_test.dart` all exist and pass.

**Environment assumptions (verified):**
- The flutterware GUI is a Flutter macOS desktop app in `app/`. Its macOS Runner is at `app/macos/Runner/` with `MainFlutterWindow.swift` registering plugins via `RegisterGeneratedPlugins`.
- The GUI process runs as a compiled desktop binary, so `Platform.resolvedExecutable` is **not** a Dart SDK. Compiling the guest scene needs the Flutter SDK's `dart`; therefore `EmbeddedEngine` delegates the build to a subprocess run with `<flutterSdk>/bin/dart`.
- `app/lib/main_dev.dart` discovers a Flutter SDK via `FlutterSdkPath.findSdks()` (`app/lib/src/utils/flutter_sdk.dart`); each `FlutterSdk` exposes a `root` path.
- `FlutterCache(cacheDir)` accepts an explicit `<flutter>/bin/cache` directory (see `app/lib/src/embedder/flutter_cache.dart`).
- Dart `ServerSocket.bind` supports Unix domain sockets via `InternetAddress(path, type: InternetAddressType.unix)`.

**Lint notes:** `prefer_single_quotes`, `omit_local_variable_types` (prefer `var`), `avoid_final_parameters`, `unawaited_futures`. `prefer_const_*` Flutter lints are off.

**Spec deviation (deliberate, flagged for the reviewer):** the spec says the harness screen is "reachable when running via `main_dev.dart`". Wiring a new screen into the flutterware app's project-tool navigation is invasive and unrelated to the embedder. This plan instead adds a dedicated IDE dev entrypoint `app/lib/main_embedder_dev.dart` that shows only the harness — the same spirit (an IDE-launched dev harness) with no coupling to the app's navigation.

---

## File structure

| File | Responsibility |
|---|---|
| `app/tool/embedder/build_guest.dart` (new) | CLI: ensure framework + compile scene + build host; prints `HOST_PATH=…`. |
| `app/macos/Runner/EmbedderTexturePlugin.swift` (new) | Native plugin: external texture + `IOSurface`→`CVPixelBuffer`. |
| `app/macos/Runner/MainFlutterWindow.swift` (modify) | Register `EmbedderTexturePlugin`. |
| `app/macos/Runner.xcodeproj/project.pbxproj` (modify) | Add the new Swift file to the Runner target. |
| `app/lib/src/embedder/embedded_engine.dart` (new) | GUI-side runtime: build, spawn, socket, texture bridge, state. |
| `app/lib/src/embedder/embedder_harness_screen.dart` (new) | The dev-harness screen widget. |
| `app/lib/main_embedder_dev.dart` (new) | IDE dev entrypoint that runs the harness. |
| `app/lib/src/embedder/README.md` (modify) | Document the GUI display. |

---

## Task 1: `build_guest.dart` — guest build CLI

**Files:**
- Create: `app/tool/embedder/build_guest.dart`

`EmbeddedEngine` runs this with the Flutter SDK's `dart` so the
SDK-dependent steps (frontend_server, CMake) happen in a process that has a
real Dart SDK. It reuses Plan 1's `embedder_build.dart` helpers and prints the
built host path on a recognisable line.

- [ ] **Step 1: Create `app/tool/embedder/build_guest.dart`:**

```dart
import 'dart:io';

import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;

/// Ensures the embedder engine framework, compiles `scene.dart`, and builds the
/// C guest. Prints `HOST_PATH=<absolute path>` and `ASSETS_DIR=<absolute path>`
/// on success. Run with the Flutter SDK's `dart`.
///
/// Usage: dart run tool/embedder/build_guest.dart
Future<void> main() async {
  var packageRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  var repoRoot = p.dirname(packageRoot);
  var cache = FlutterCache.fromRunningSdk();

  var buildDir = p.join(packageRoot, 'build', 'embedder');
  var assetsDir = p.join(buildDir, 'assets');
  var engineDir = p.join(packageRoot, '.engine');
  Directory(buildDir).createSync(recursive: true);

  await ensureEmbedderFramework(cache, engineDir);
  await compileScene(
    scenePath: p.join(packageRoot, 'tool', 'embedder', 'scene.dart'),
    kernelBlob: p.join(assetsDir, 'kernel_blob.bin'),
    packageConfig: p.join(repoRoot, '.dart_tool', 'package_config.json'),
    cache: cache,
  );
  var hostPath = await buildHost(
    nativeSourceDir: p.join(packageRoot, 'native'),
    nativeBuildDir: p.join(buildDir, 'native'),
    engineDir: engineDir,
  );

  stdout.writeln('ASSETS_DIR=$assetsDir');
  stdout.writeln('ICU_DATA=${cache.icuData}');
  stdout.writeln('HOST_PATH=$hostPath');
}
```

- [ ] **Step 2: Verify analysis and a real build**

Run: `cd app && /Users/xavier/flutter/bin/dart analyze tool/embedder/build_guest.dart`
Expected: "No issues found!"

Run: `cd app && /Users/xavier/flutter/bin/dart run tool/embedder/build_guest.dart`
Expected: ends with three lines `ASSETS_DIR=…`, `ICU_DATA=…`, `HOST_PATH=…`,
and the `host` executable exists at the printed path.

- [ ] **Step 3: Commit**

```bash
git add app/tool/embedder/build_guest.dart
git commit -m "Add build_guest.dart CLI for the embedder GUI runtime"
```

---

## Task 2: macOS native texture plugin

**Files:**
- Create: `app/macos/Runner/EmbedderTexturePlugin.swift`
- Modify: `app/macos/Runner/MainFlutterWindow.swift`
- Modify: `app/macos/Runner.xcodeproj/project.pbxproj`

The plugin registers a `FlutterTexture` with the host engine's texture
registrar and serves a `MethodChannel`. Each shared `IOSurface` is looked up by
ID (`IOSurfaceLookup`) and wrapped once as a `CVPixelBuffer`; `copyPixelBuffer`
returns whichever ring slot the latest `markFrameAvailable` selected.

- [ ] **Step 1: Create `app/macos/Runner/EmbedderTexturePlugin.swift`:**

```swift
import Cocoa
import CoreVideo
import FlutterMacOS
import IOSurface

/// An external Flutter texture backed by a ring of shared IOSurfaces.
class EmbedderTexture: NSObject, FlutterTexture {
  private var buffers: [CVPixelBuffer]
  private var currentIndex: Int = 0
  private let lock = NSLock()

  init?(surfaceIds: [UInt32]) {
    guard let created = EmbedderTexture.wrap(surfaceIds) else { return nil }
    self.buffers = created
    super.init()
  }

  private static func wrap(_ surfaceIds: [UInt32]) -> [CVPixelBuffer]? {
    var result: [CVPixelBuffer] = []
    for id in surfaceIds {
      guard let surface = IOSurfaceLookup(IOSurfaceID(id)) else { return nil }
      var pixelBuffer: CVPixelBuffer?
      let status = CVPixelBufferCreateWithIOSurface(
        kCFAllocatorDefault, surface, nil, &pixelBuffer)
      guard status == kCVReturnSuccess, let pb = pixelBuffer else {
        return nil
      }
      result.append(pb)
    }
    return result
  }

  /// Re-wraps a fresh set of surfaces after a resize. Returns false if any
  /// lookup fails.
  func setSurfaces(_ surfaceIds: [UInt32]) -> Bool {
    guard let created = EmbedderTexture.wrap(surfaceIds) else { return false }
    lock.lock()
    buffers = created
    currentIndex = 0
    lock.unlock()
    return true
  }

  func setCurrentIndex(_ index: Int) {
    lock.lock()
    if index >= 0 && index < buffers.count { currentIndex = index }
    lock.unlock()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard currentIndex < buffers.count else { return nil }
    return Unmanaged.passRetained(buffers[currentIndex])
  }
}

public class EmbedderTexturePlugin: NSObject, FlutterPlugin {
  private let registry: FlutterTextureRegistry
  private var textures: [Int64: EmbedderTexture] = [:]

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutterware/embedder_texture",
      binaryMessenger: registrar.messenger)
    let instance = EmbedderTexturePlugin(registry: registrar.textures)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall,
                     result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "createTexture":
      guard let ids = args["surfaceIds"] as? [Int] else {
        result(FlutterError(code: "bad_args",
                            message: "surfaceIds required", details: nil))
        return
      }
      let surfaceIds = ids.map { UInt32(truncatingIfNeeded: $0) }
      guard let texture = EmbedderTexture(surfaceIds: surfaceIds) else {
        result(FlutterError(code: "lookup_failed",
                            message: "IOSurfaceLookup failed", details: nil))
        return
      }
      let textureId = registry.register(texture)
      textures[textureId] = texture
      result(NSNumber(value: textureId))
    case "updateSurfaces":
      guard let textureId = (args["textureId"] as? Int).map({ Int64($0) }),
            let ids = args["surfaceIds"] as? [Int],
            let texture = textures[textureId] else {
        result(FlutterError(code: "bad_args",
                            message: "unknown texture", details: nil))
        return
      }
      let ok = texture.setSurfaces(
        ids.map { UInt32(truncatingIfNeeded: $0) })
      result(NSNumber(value: ok))
    case "markFrameAvailable":
      guard let textureId = (args["textureId"] as? Int).map({ Int64($0) }),
            let ringIndex = args["ringIndex"] as? Int,
            let texture = textures[textureId] else {
        result(FlutterError(code: "bad_args",
                            message: "unknown texture", details: nil))
        return
      }
      texture.setCurrentIndex(ringIndex)
      registry.textureFrameAvailable(textureId)
      result(nil)
    case "disposeTexture":
      if let textureId = (args["textureId"] as? Int).map({ Int64($0) }) {
        registry.unregisterTexture(textureId)
        textures.removeValue(forKey: textureId)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

- [ ] **Step 2: Register the plugin in `MainFlutterWindow.swift`**

Replace `app/macos/Runner/MainFlutterWindow.swift` entirely with:

```swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    EmbedderTexturePlugin.register(
      with: flutterViewController.registrar(forPlugin: "EmbedderTexturePlugin"))

    super.awakeFromNib()
  }
}
```

- [ ] **Step 3: Add the Swift file to the Xcode project**

The Runner target only compiles Swift files referenced in `project.pbxproj`.
Add `EmbedderTexturePlugin.swift` to the Runner target. The reliable way:

```sh
open app/macos/Runner.xcodeproj
```
In Xcode: right-click the **Runner** group → *Add Files to "Runner"…* → select
`app/macos/Runner/EmbedderTexturePlugin.swift` → ensure *Add to target: Runner*
is checked → Add. Save and close Xcode.

If editing `project.pbxproj` by hand instead, add the file in four places: a
`PBXBuildFile` entry, a `PBXFileReference` entry, the file reference in the
`Runner` group's `children`, and the build-file ID in the Runner target's
`PBXSourcesBuildPhase` `files` list. Verify afterward (Step 4).

- [ ] **Step 4: Verify the macOS build compiles the plugin**

Run: `cd app && /Users/xavier/flutter/bin/flutter build macos --debug`
Expected: the build succeeds and the build log shows `EmbedderTexturePlugin.swift`
being compiled. If the build fails with `cannot find 'EmbedderTexturePlugin'`,
the file is not in the Runner target — redo Step 3.

If the build fails on an API name (`registrar.textures`, `registrar.messenger`,
`register(_:)`, `textureFrameAvailable(_:)`, `unregisterTexture(_:)`, or
`registrar(forPlugin:)`), the installed `FlutterMacOS` spelling differs:
inspect `app/macos/Flutter/ephemeral/FlutterMacOS.framework/Headers/` (or
`FlutterMacOS.modulemap`) for the exact selector and adjust. Report any change.

- [ ] **Step 5: Commit**

```bash
git add app/macos/Runner/EmbedderTexturePlugin.swift app/macos/Runner/MainFlutterWindow.swift app/macos/Runner.xcodeproj/project.pbxproj
git commit -m "Add macOS external-texture plugin for the embedder"
```

---

## Task 3: `EmbeddedEngine` GUI runtime

**Files:**
- Create: `app/lib/src/embedder/embedded_engine.dart`

Owns the whole guest lifecycle: run `build_guest.dart` with the SDK `dart`,
spawn the guest, hold the control socket, bridge protocol messages to the
texture plugin, and expose a `textureId` plus a state for the UI. It is a
`ChangeNotifier` so the harness screen can rebuild on state changes.

- [ ] **Step 1: Create `app/lib/src/embedder/embedded_engine.dart`:**

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'protocol.dart';

enum EmbeddedEnginePhase { building, running, error }

/// Drives an out-of-process Flutter-engine guest and bridges its rendered
/// frames into a host external texture.
class EmbeddedEngine extends ChangeNotifier {
  EmbeddedEngine({required this.appPackageRoot, required this.flutterSdkRoot});

  /// Absolute path to the `flutterware_app` package root (the `app/` dir).
  final String appPackageRoot;

  /// Absolute path to the Flutter SDK checkout root.
  final String flutterSdkRoot;

  static const _channel = MethodChannel('flutterware/embedder_texture');

  EmbeddedEnginePhase phase = EmbeddedEnginePhase.building;
  String? errorMessage;
  int? textureId;
  int textureWidth = 0;
  int textureHeight = 0;

  ServerSocket? _server;
  Socket? _conn;
  Process? _guest;
  final FrameReader _reader = FrameReader();
  int _currentGeneration = -1;
  bool _disposed = false;

  String get _dartExecutable =>
      p.join(flutterSdkRoot, 'bin', 'dart');

  /// Builds and launches the guest. Call once.
  Future<void> start({int width = 800, int height = 600}) async {
    try {
      var build = await _runBuild();
      if (_disposed) return;

      var buildDir = p.join(appPackageRoot, 'build', 'embedder');
      var socketPath = p.join(buildDir, 'embedder_gui.sock');
      var socketFile = File(socketPath);
      if (socketFile.existsSync()) socketFile.deleteSync();
      _server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix), 0);

      _guest = await Process.start(
        build.hostPath,
        [
          build.assetsDir,
          build.icuData,
          socketPath,
          '$width',
          '$height',
        ],
        mode: ProcessStartMode.normal,
      );
      _guest!.stdout.transform(const SystemEncoding().decoder).listen((line) {
        debugPrint('[guest] $line');
      });
      _guest!.stderr.transform(const SystemEncoding().decoder).listen((line) {
        debugPrint('[guest:err] $line');
      });

      _conn = await _server!.first;
      _conn!.listen(_onSocketData, onDone: _onSocketClosed);
    } catch (e) {
      _fail('$e');
    }
  }

  Future<({String hostPath, String assetsDir, String icuData})>
      _runBuild() async {
    var result = await Process.run(
      _dartExecutable,
      ['run', p.join('tool', 'embedder', 'build_guest.dart')],
      workingDirectory: appPackageRoot,
    );
    if (result.exitCode != 0) {
      throw StateError('build_guest.dart failed:\n${result.stderr}');
    }
    String? extract(String key) {
      for (var line in (result.stdout as String).split('\n')) {
        if (line.startsWith('$key=')) return line.substring(key.length + 1);
      }
      return null;
    }
    var hostPath = extract('HOST_PATH');
    var assetsDir = extract('ASSETS_DIR');
    var icuData = extract('ICU_DATA');
    if (hostPath == null || assetsDir == null || icuData == null) {
      throw StateError('build_guest.dart did not print the expected paths');
    }
    return (hostPath: hostPath, assetsDir: assetsDir, icuData: icuData);
  }

  void _onSocketData(Uint8List chunk) {
    for (var message in _reader.addBytes(chunk)) {
      unawaited(_handle(message));
    }
  }

  Future<void> _handle(EmbedderMessage message) async {
    switch (message) {
      case ReadyMessage():
        break;
      case SurfacesAllocatedMessage():
        await _onSurfaces(message);
      case FrameReadyMessage():
        if (textureId != null) {
          await _channel.invokeMethod('markFrameAvailable', {
            'textureId': textureId,
            'ringIndex': message.ringIndex,
          });
        }
      case ErrorMessage():
        _fail(message.message);
      case ResizeMessage():
      case PointerEventMessage():
      case KeyEventMessage():
      case ShutdownMessage():
        break; // GUI-to-guest messages; never received here.
    }
  }

  Future<void> _onSurfaces(SurfacesAllocatedMessage message) async {
    textureWidth = message.width;
    textureHeight = message.height;
    if (textureId == null) {
      textureId = await _channel.invokeMethod<int>('createTexture', {
        'surfaceIds': message.surfaceIds,
      });
      phase = EmbeddedEnginePhase.running;
    } else if (message.generation != _currentGeneration) {
      await _channel.invokeMethod('updateSurfaces', {
        'textureId': textureId,
        'surfaceIds': message.surfaceIds,
      });
    }
    _currentGeneration = message.generation;
    notifyListeners();
  }

  void _onSocketClosed() {
    if (phase != EmbeddedEnginePhase.error && !_disposed) {
      _fail('the embedder guest exited');
    }
  }

  void _fail(String message) {
    errorMessage = message;
    phase = EmbeddedEnginePhase.error;
    notifyListeners();
  }

  void _send(EmbedderMessage message) {
    var conn = _conn;
    if (conn != null && phase == EmbeddedEnginePhase.running) {
      conn.add(encodeMessage(message));
    }
  }

  /// Forwards a new physical-pixel size to the guest.
  void resize(int width, int height, double pixelRatio) {
    _send(ResizeMessage(
        width: width, height: height, pixelRatio: pixelRatio));
  }

  void sendPointer({
    required PointerPhase phaseKind,
    required double x,
    required double y,
    int buttons = 0,
    double scrollDeltaX = 0,
    double scrollDeltaY = 0,
  }) {
    _send(PointerEventMessage(
      phase: phaseKind,
      x: x,
      y: y,
      buttons: buttons,
      scrollDeltaX: scrollDeltaX,
      scrollDeltaY: scrollDeltaY,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  void sendKey({
    required KeyEventKind kind,
    required int physicalKey,
    required int logicalKey,
  }) {
    _send(KeyEventMessage(
      kind: kind,
      physicalKey: physicalKey,
      logicalKey: logicalKey,
      modifiers: 0,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    if (_conn != null && phase == EmbeddedEnginePhase.running) {
      _conn!.add(encodeMessage(const ShutdownMessage()));
    }
    if (textureId != null) {
      unawaited(_channel
          .invokeMethod('disposeTexture', {'textureId': textureId})
          .catchError((_) {}));
    }
    unawaited(_conn?.close());
    unawaited(_server?.close());
    _guest?.kill();
    super.dispose();
  }
}
```

- [ ] **Step 2: Verify analysis is clean**

Run: `cd app && /Users/xavier/flutter/bin/dart analyze lib/src/embedder/embedded_engine.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add app/lib/src/embedder/embedded_engine.dart
git commit -m "Add EmbeddedEngine GUI runtime for the embedder"
```

---

## Task 4: Dev-harness screen and entrypoint

**Files:**
- Create: `app/lib/src/embedder/embedder_harness_screen.dart`
- Create: `app/lib/main_embedder_dev.dart`

The harness screen owns an `EmbeddedEngine`, shows its state, and — once
running — displays the `Texture`. A `LayoutBuilder` reports size changes as
physical-pixel `Resize` messages; a `Listener` and `Focus` forward pointer and
key input. Coordinates are converted to physical pixels (the guest's surfaces
are sized in physical pixels).

- [ ] **Step 1: Create `app/lib/src/embedder/embedder_harness_screen.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'embedded_engine.dart';
import 'protocol.dart';

/// A standalone dev harness that runs the embedder guest and shows its live
/// output in an external texture.
class EmbedderHarnessScreen extends StatefulWidget {
  const EmbedderHarnessScreen({
    super.key,
    required this.appPackageRoot,
    required this.flutterSdkRoot,
  });

  final String appPackageRoot;
  final String flutterSdkRoot;

  @override
  State<EmbedderHarnessScreen> createState() => _EmbedderHarnessScreenState();
}

class _EmbedderHarnessScreenState extends State<EmbedderHarnessScreen> {
  late final EmbeddedEngine _engine = EmbeddedEngine(
    appPackageRoot: widget.appPackageRoot,
    flutterSdkRoot: widget.flutterSdkRoot,
  );
  final FocusNode _focusNode = FocusNode();
  Size? _lastReportedSize;

  @override
  void initState() {
    super.initState();
    _engine.start();
  }

  @override
  void dispose() {
    _engine.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _maybeResize(Size size, double dpr) {
    if (size == _lastReportedSize) return;
    _lastReportedSize = size;
    _engine.resize(
        (size.width * dpr).round(), (size.height * dpr).round(), dpr);
  }

  void _sendPointer(PointerPhase phase, Offset local, double dpr,
      {int buttons = 0}) {
    _engine.sendPointer(
      phaseKind: phase,
      x: local.dx * dpr,
      y: local.dy * dpr,
      buttons: buttons,
    );
  }

  @override
  Widget build(BuildContext context) {
    var dpr = MediaQuery.of(context).devicePixelRatio;
    return Scaffold(
      appBar: AppBar(title: const Text('Embedder harness')),
      body: AnimatedBuilder(
        animation: _engine,
        builder: (context, _) {
          switch (_engine.phase) {
            case EmbeddedEnginePhase.building:
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Building and starting the embedder guest…'),
                  ],
                ),
              );
            case EmbeddedEnginePhase.error:
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Embedder error:\n${_engine.errorMessage}',
                      style: const TextStyle(color: Colors.red)),
                ),
              );
            case EmbeddedEnginePhase.running:
              return LayoutBuilder(
                builder: (context, constraints) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _maybeResize(constraints.biggest, dpr);
                  });
                  return Focus(
                    focusNode: _focusNode,
                    onKeyEvent: (node, event) {
                      var kind = event is KeyDownEvent
                          ? KeyEventKind.down
                          : event is KeyRepeatEvent
                              ? KeyEventKind.repeat
                              : KeyEventKind.up;
                      _engine.sendKey(
                        kind: kind,
                        physicalKey: event.physicalKey.usbHidUsage,
                        logicalKey: event.logicalKey.keyId,
                      );
                      return KeyEventResult.handled;
                    },
                    child: Listener(
                      onPointerDown: (e) {
                        _focusNode.requestFocus();
                        _sendPointer(PointerPhase.down, e.localPosition, dpr,
                            buttons: 1);
                      },
                      onPointerMove: (e) => _sendPointer(
                          PointerPhase.move, e.localPosition, dpr,
                          buttons: 1),
                      onPointerHover: (e) => _sendPointer(
                          PointerPhase.hover, e.localPosition, dpr),
                      onPointerUp: (e) => _sendPointer(
                          PointerPhase.up, e.localPosition, dpr),
                      child: SizedBox.expand(
                        child: _engine.textureId == null
                            ? const SizedBox()
                            : Texture(textureId: _engine.textureId!),
                      ),
                    ),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Create `app/lib/main_embedder_dev.dart`:**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'src/embedder/embedder_harness_screen.dart';
import 'src/utils/flutter_sdk.dart';

/// IDE dev entrypoint: runs only the embedder harness screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var sdks = await FlutterSdkPath.findSdks();
  var flutterSdkRoot = sdks.first.root;
  // The compiled app runs with its bundle as the working dir; the `app/`
  // package root is resolved from this source file's location during dev.
  var appPackageRoot = Directory.current.path.endsWith('app')
      ? Directory.current.path
      : p.join(Directory.current.path, 'app');

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: EmbedderHarnessScreen(
      appPackageRoot: appPackageRoot,
      flutterSdkRoot: flutterSdkRoot,
    ),
  ));
}
```

- [ ] **Step 3: Verify analysis is clean**

Run: `cd app && /Users/xavier/flutter/bin/dart analyze lib/src/embedder/embedder_harness_screen.dart lib/main_embedder_dev.dart`
Expected: "No issues found!"

If `FlutterSdkPath` / `FlutterSdk.root` names differ, open
`app/lib/src/utils/flutter_sdk.dart` and adjust to the real API (see how
`main_dev.dart` uses `FlutterSdkPath.findSdks()` and `flutterSdk.root`).

- [ ] **Step 4: Commit**

```bash
git add app/lib/src/embedder/embedder_harness_screen.dart app/lib/main_embedder_dev.dart
git commit -m "Add embedder dev-harness screen and entrypoint"
```

---

## Task 5: Manual verification and README

**Files:**
- Modify: `app/lib/src/embedder/README.md`

The native plugin + host texture registrar path is not automatically testable;
verify it by running the harness.

- [ ] **Step 1: Run the harness**

Run: `cd app && /Users/xavier/flutter/bin/flutter run -t lib/main_embedder_dev.dart -d macos`

Confirm, in order:
1. The window shows "Building and starting the embedder guest…", then the
   embedded scene appears.
2. The white square **rotates continuously** — frames are flowing live.
3. **Clicking** the "Tap me" button increments the "Taps:" counter — pointer
   input reaches the guest.
4. **Resizing** the window reflows the embedded scene to the new size without
   distortion — `Resize` re-allocates the guest surfaces.
5. Colours are correct (blue background). If swapped, fix the channel order in
   `app/native/surface.c` per Plan 1 Task 8 Step 3 and rebuild.
6. Closing the window exits cleanly with no orphaned `host` process
   (`pgrep -fl '/host'` returns nothing afterward).

- [ ] **Step 2: Replace `app/lib/src/embedder/README.md` entirely with:**

```markdown
# Embedder

Experimental Flutter engine embedder, part of `flutterware_app`.

**Step 3a (current):** an out-of-process Flutter-engine guest renders an
animated, interactive scene with the software renderer into shared
`IOSurface`s; the flutterware desktop GUI displays it live in an external
`Texture`. The panel is resizable and forwards pointer/keyboard input.

## Run the GUI harness

```sh
cd app && flutter run -t lib/main_embedder_dev.dart -d macos
```

This builds and spawns the guest, then shows its live output.

## Run the headless smoke

```sh
dart run app/tool/embedder/run.dart
```

Spawns the guest and writes its first frame to `app/build/embedder/scene.png`.

## How it works

Two processes, a Unix-domain-socket control channel, and shared `IOSurface`s:

- **Guest** (`native/`) — the long-lived C host embedding `FlutterEmbedder`.
  `host.c` runs the engine; `surface.{c,h}` is the `IOSurface` triple-buffer
  ring; `ipc.{c,h}` is the framed socket protocol; `input.{c,h}` translates
  pointer/key events.
- **GUI runtime** (`lib/src/embedder/`) — `embedded_engine.dart` builds and
  spawns the guest, owns the socket, and bridges frames to the texture;
  `embedder_harness_screen.dart` is the dev screen; `protocol.dart` is the wire
  codec; `embedder_build.dart` / `tool/embedder/build_guest.dart` orchestrate
  the build.
- **Native plugin** (`macos/Runner/EmbedderTexturePlugin.swift`) — registers
  the external `FlutterTexture` and wraps each `IOSurface` as a `CVPixelBuffer`.

The guest announces surfaces by `IOSurfaceID`, signals each frame with
`FrameReady`, and accepts `Resize`/`PointerEvent`/`KeyEvent`/`Shutdown`.

## Tests

- `app/test/embedder/` — fast unit tests (`raw_frame_test`, `protocol_test`).
- `app/integration_test/embedder/` — heavy tests (`compiler_test`,
  `flutter_cache_test`, `live_bridge_test`):

  ```sh
  cd app && dart test integration_test/embedder
  ```

The GUI texture path is verified manually via the harness.

## Not yet implemented

GPU/Metal rendering and a zero-copy path (step 3b), hot reload (step 4), text
input/IME, multiple embedded engines, non-macOS platforms.
```

- [ ] **Step 3: Verify workspace-wide analysis is clean**

Run (from repo root): `/Users/xavier/flutter/bin/flutter analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add app/lib/src/embedder/README.md
git commit -m "Update embedder README for step 3a (live GUI display)"
```

---

## Self-Review notes

- **Spec coverage:** out-of-process guest reused from Plan 1; native macOS
  plugin registering an external texture (Task 2); `IOSurface`→`CVPixelBuffer`
  wrapping (Task 2); `EmbeddedEngine` absorbing build orchestration (Tasks 1,
  3); per-frame `markFrameAvailable` via `MethodChannel` (Task 3); dev-harness
  screen with `Texture` + `Listener` + `Focus` + `LayoutBuilder` (Task 4);
  resize forwarding (Tasks 3, 4); pointer/key forwarding (Tasks 3, 4);
  generation-checked surface updates (Task 3 `_onSurfaces`); error state on
  guest crash / EOF (Task 3 `_onSocketClosed`); manual verification (Task 5).
- **Spec deviation:** the harness is a dedicated entrypoint
  (`main_embedder_dev.dart`) rather than a screen inside `main_dev.dart` — see
  the header note. Flagged for the reviewer.
- **Native-API risk:** the `FlutterMacOS` texture-registrar selectors and the
  Xcode-project file addition are pinned by Task 2 Steps 3–4 with explicit
  remedies. The `FlutterSdkPath` API is pinned by Task 4 Step 3.
- **Type consistency:** the `MethodChannel` name `flutterware/embedder_texture`
  and the methods `createTexture`/`updateSurfaces`/`markFrameAvailable`/
  `disposeTexture` with args `surfaceIds`/`textureId`/`ringIndex` match between
  the Swift plugin (Task 2) and `EmbeddedEngine` (Task 3). `EmbeddedEngine`
  consumes `SurfacesAllocatedMessage`/`FrameReadyMessage`/`ErrorMessage` and
  sends `ResizeMessage`/`PointerEventMessage`/`KeyEventMessage`/
  `ShutdownMessage` exactly as defined in Plan 1's `protocol.dart`.
- **Deferred items** (Metal/zero-copy, hot reload, IME, multi-engine,
  non-macOS) are intentionally absent.
```
