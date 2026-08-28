@Tags(['gpu'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/previews/asset_bundle.dart';
import 'package:flutterware_app/src/previews/package_config_locator.dart';
import 'package:flutterware_app/src/embedder/embedder_build.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/embedder/guest_vm_service.dart';
import 'package:flutterware_app/src/embedder/protocol.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every way a project's assets can move under a live guest, end to end:
///
/// - **edit** — the bundle links the file, so a reassemble alone repaints it;
/// - **add** — an in-place rebundle plus a manifest evict makes it resolve;
/// - **remove** — the same pair makes it stop resolving;
/// - **fonts** — nothing short of a guest relaunch applies them, which is the
///   claim `AssetsChanged.fontsChanged` exists to carry.
///
/// One guest, phases in sequence, against a throwaway project so the churn
/// touches nothing anyone commits. The colours are the assertions: each phase
/// paints a square only one file can produce.
void main() {
  test('edit, add, remove and fonts against one live guest', () async {
    var appRoot = Directory.current.path;
    var repoRoot = p.dirname(appRoot);
    var cache = FlutterCache.fromRunningSdk();
    var root = Directory.systemTemp.createTempSync('fw_asset_refresh');
    addTearDown(() => root.deleteSync(recursive: true));

    // --- The throwaway project -------------------------------------------
    var projectRoot = p.join(root.path, 'project');
    void write(String relative, List<int> bytes) {
      var file = File(p.join(projectRoot, relative));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    }

    void writeText(String relative, String content) =>
        write(relative, utf8.encode(content));

    List<int> square(int r, int g, int b) => img.encodePng(
      img.fill(img.Image(width: 48, height: 48), color: img.ColorRgb8(r, g, b)),
    );

    var pubspecPlain = '''
name: project
flutter:
  assets:
    - assets/images/
''';
    writeText('pubspec.yaml', pubspecPlain);
    writeText('.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": []}
''');
    write('assets/images/edit_me.png', square(0x21, 0x96, 0xF3)); // blue

    // --- Bundle, scene, guest --------------------------------------------
    var bundle = p.join(root.path, 'bundle');
    var builder = AssetBundleBuilder(
      cache: cache,
      rootPackageRoot: projectRoot,
      packageConfigPath: p.join(
        projectRoot,
        '.dart_tool',
        'package_config.json',
      ),
    );
    await builder.build(bundle);

    // Fixed-size slots, so the layout — and with it the text band compared
    // below — is identical in every phase no matter which images exist.
    var scene = File(p.join(root.path, 'scene.dart'))
      ..writeAsStringSync('''
import 'package:flutter/material.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Image.asset(
                'assets/images/edit_me.png',
                errorBuilder: (c, e, s) => Text('gone'),
              ),
            ),
            SizedBox(
              width: 60,
              height: 60,
              child: Image.asset(
                'assets/images/added.png',
                errorBuilder: (c, e, s) => Text('gone'),
              ),
            ),
            Text(
              'AaBbCcDdEe',
              style: TextStyle(fontFamily: 'ProbeFont', fontSize: 32),
            ),
          ],
        ),
      ),
    ),
  ),
);
''');
    var engineDir = await ensureEmbedderEngine(cache);
    var hostPath = await buildHost(
      nativeSourceDir: p.join(appRoot, 'native'),
      nativeBuildDir: p.join(appRoot, 'build', 'catalog', 'native'),
      engineDir: engineDir,
    );
    await compileScene(
      scenePath: scene.path,
      kernelBlob: p.join(bundle, 'kernel_blob.bin'),
      packageConfig: requirePackageConfig(appRoot),
      cache: cache,
    );

    Process? guest;
    Socket? conn;
    ServerSocket? server;
    GuestVmService? vm;
    Completer<void>? captured;
    var captureIndex = 0;

    Future<void> launch(String label) async {
      var socketPath = checkSocketPath(
        p.join(flutterwareRunDir(), 'asset-refresh-$label.sock'),
      );
      var socketFile = File(socketPath);
      if (socketFile.existsSync()) socketFile.deleteSync();
      server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      guest = await Process.start(hostPath, [
        bundle,
        cache.icuData,
        socketPath,
        '600',
        '400',
      ]);
      var vmUri = Completer<String>();
      guest!.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            var match = RegExp(r'(http://127\.0\.0\.1:\S+/)').firstMatch(line);
            if (match != null && !vmUri.isCompleted) {
              vmUri.complete(match.group(1));
            }
          });
      unawaited(guest!.stderr.drain<void>());

      var connected = await Future.any<Object?>([
        server!.first,
        guest!.exitCode,
      ]);
      if (connected is! Socket) {
        throw StateError('the guest exited before connecting');
      }
      conn = connected;
      var reader = FrameReader();
      var frames = 0;
      conn!.listen((chunk) {
        for (var message in reader.addBytes(chunk)) {
          if (message is FrameReadyMessage) frames++;
          if (message is CapturedMessage) captured?.complete();
          if (message is ErrorMessage) {
            fail('guest error: ${message.message}');
          }
        }
      });
      while (frames == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      vm = await GuestVmService.connect(await vmUri.future);
    }

    Future<void> shutdown() async {
      await vm?.close();
      conn?.add(encodeMessage(const ShutdownMessage()));
      await conn?.flush();
      await conn?.close();
      guest?.kill();
      await server?.close();
    }

    addTearDown(shutdown);

    /// The frame after the scene settles, as raw BGRA.
    Future<List<int>> capture() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      var path = p.join(root.path, 'frame${captureIndex++}.rawframe');
      captured = Completer<void>();
      conn!.add(encodeMessage(CaptureMessage(path)));
      await conn!.flush();
      await captured!.future.timeout(const Duration(seconds: 30));
      return File(path).readAsBytesSync();
    }

    int count(List<int> frame, bool Function(int r, int g, int b) match) {
      var hits = 0;
      for (var i = 12; i + 3 < frame.length; i += 4) {
        if (match(frame[i + 2], frame[i + 1], frame[i])) hits++;
      }
      return hits;
    }

    int blue(List<int> f) =>
        count(f, (r, g, b) => b > 200 && r < 100 && g > 100 && g < 200);
    int green(List<int> f) =>
        count(f, (r, g, b) => g > 130 && r < 120 && b < 120);

    /// The rows the probe text sits in, for the font phases. The images above
    /// it occupy fixed 60px slots, so these rows hold nothing but the text.
    List<int> textBand(List<int> frame) {
      const width = 600, rowBytes = width * 4;
      return frame.sublist(12 + 260 * rowBytes, 12 + 340 * rowBytes);
    }

    Future<void> evictAndReassemble(List<String> keys) async {
      for (var key in keys) {
        await vm!.service.callServiceExtension(
          'ext.flutter.evict',
          isolateId: vm!.isolateId,
          args: {'value': key},
        );
      }
      await vm!.service.callServiceExtension(
        'ext.flutter.reassemble',
        isolateId: vm!.isolateId,
      );
    }

    // --- Phase 1: the starting point -------------------------------------
    await launch('a');
    var start = await capture();
    expect(blue(start), greaterThan(800), reason: 'edit_me.png renders');
    expect(green(start), isZero, reason: 'nothing green exists yet');

    // --- Phase 2: edit — repaint only, no rebundle -----------------------
    write('assets/images/edit_me.png', square(0x4C, 0xAF, 0x50)); // green
    var afterEdit = await builder.build(bundle);
    expect(
      afterEdit.changed,
      isFalse,
      reason:
          'The bundle links the file, so an edit changes no bundle byte — '
          'which is why the edit path needs only the reassemble below.',
    );
    await evictAndReassemble(['assets/images/edit_me.png']);
    var edited = await capture();
    expect(green(edited), greaterThan(800), reason: 'the edit repainted');
    expect(blue(edited), isZero, reason: 'the old pixels are gone');

    // --- Phase 3: add — rebundle, evict the manifest ---------------------
    write('assets/images/added.png', square(0x21, 0x96, 0xF3)); // blue again
    var afterAdd = await builder.build(bundle);
    expect(afterAdd.changed, isTrue);
    expect(afterAdd.fontsChanged, isFalse);
    await evictAndReassemble(['AssetManifest.bin']);
    var added = await capture();
    expect(blue(added), greaterThan(800), reason: 'the added file renders');
    expect(green(added), greaterThan(800), reason: 'the edit survives');

    // --- Phase 4: remove — the same pair, the other direction ------------
    File(p.join(projectRoot, 'assets', 'images', 'edit_me.png')).deleteSync();
    var afterRemove = await builder.build(bundle);
    expect(afterRemove.changed, isTrue);
    await evictAndReassemble(['AssetManifest.bin']);
    var removed = await capture();
    expect(green(removed), isZero, reason: 'the removed key stopped resolving');
    expect(blue(removed), greaterThan(800), reason: 'its neighbour is intact');

    // --- Phase 5: fonts — eviction is not enough -------------------------
    write(
      'assets/fonts/Probe.ttf',
      File(
        p.join(
          repoRoot,
          'examples',
          'example',
          'assets',
          'fonts',
          'Roboto-Bold.ttf',
        ),
      ).readAsBytesSync(),
    );
    writeText('pubspec.yaml', '''
$pubspecPlain  fonts:
    - family: ProbeFont
      fonts:
        - asset: assets/fonts/Probe.ttf
''');
    var afterFont = await builder.build(bundle);
    expect(afterFont.changed, isTrue);
    expect(afterFont.fontsChanged, isTrue);
    await evictAndReassemble(['FontManifest.json', 'AssetManifest.bin']);
    var fontEvicted = await capture();
    expect(
      textBand(fontEvicted),
      textBand(removed),
      reason:
          'The engine registered fonts at startup; eviction and reassemble '
          'must not pretend otherwise. This equality is the measured fact '
          'behind AssetsChanged.fontsChanged meaning "relaunch".',
    );

    // --- Phase 6: fonts — a relaunch is ----------------------------------
    await shutdown();
    await launch('b');
    var relaunched = await capture();
    expect(
      textBand(relaunched),
      isNot(textBand(fontEvicted)),
      reason: 'A fresh guest read the new FontManifest and renders ProbeFont.',
    );
    expect(
      blue(relaunched),
      greaterThan(800),
      reason: 'and the bundle it read is the synced one',
    );
  });
}
