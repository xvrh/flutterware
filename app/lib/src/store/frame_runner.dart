import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:flutterware/src/store/frame_entrypoint.dart'
    show generateStoreFrameEntrypoint;
import 'package:path/path.dart' as p;

import '../embedder/tester_host.dart';

/// The second pass, kept warm: the project's frame compiled once and asked to
/// compose as often as anybody edits a headline.
///
/// **Its own host, and its own build directory.** Two `TesterHost`s sharing one
/// directory tear each other's dill — the bug the comparison lane paid for —
/// and this one's program is not the capture pass's: different sources,
/// different entrypoint, different dill. Keeping it separate is also what makes
/// a recompose cheap, since it never touches the scenario harness at all.
class StoreFrameRunner {
  StoreFrameRunner({
    required this.packageRoot,
    required String flutterSdkRoot,
    required String frameFile,
    void Function(String line)? onLog,
  }) : _host = TesterHost(
         packageRoot: packageRoot,
         flutterSdkRoot: flutterSdkRoot,
         program: _StoreFrameProgram(
           packageRoot: packageRoot,
           frameFile: frameFile,
         ),
         buildDirectory: buildDirectory,
         onLog: onLog,
       );

  /// Where this runner's dill, bundle and generated entrypoint live, relative
  /// to [packageRoot].
  static const buildDirectory = 'build/flutterware/store_frames';

  final String packageRoot;
  final TesterHost _host;

  /// Composes every job in [jobs], each `{image, out, slug, index, total,
  /// locale, device, canvasWidth, canvasHeight, canvasRatio}`.
  ///
  /// The jobs travel as a file rather than as arguments: a set is tens of them
  /// and a service-extension call takes a map of strings.
  Future<Map<String, Object?>> compose(
    List<Map<String, Object?>> jobs, {
    required String manifestPath,
  }) => _host.exclusive(() async {
    var wasWarm = _host.isWarm;
    await _host.ensureGuest();
    if (wasWarm) await _host.sync();
    File(manifestPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(jobs));
    var response =
        await _host.vm.requireExtension(
          'ext.flutterware.store.compose',
          args: {'manifest': manifestPath},
        ) ??
        const <String, Object?>{};
    if (response['error'] case var error?) {
      throw StateError('$error\n${response['stack'] ?? ''}');
    }
    return response.cast<String, Object?>();
  });

  Future<void> dispose() => _host.dispose();
}

class _StoreFrameProgram extends TesterProgram {
  _StoreFrameProgram({required this.packageRoot, required this.frameFile});

  final String packageRoot;

  /// The declared frame, package-relative.
  final String frameFile;

  @override
  String get name => 'store_frames';

  @override
  String get readyLine => 'flutterware store frames harness ready';

  /// One source, and that is the point: the frame is the only project code this
  /// program compiles, so its dill is small and its recompiles are cheap. What
  /// the frame *imports* is the project's own business and travels with it.
  @override
  List<String> sources() => [frameFile];

  @override
  String writeEntrypoint(List<String> sources) {
    var path = p.join(packageRoot, storeFrameEntrypointPath);
    var content = generateStoreFrameEntrypoint(frameFile: sources.single);
    var file = File(path)..parent.createSync(recursive: true);
    // Left alone when it is already right: a touched mtime is what the source
    // invalidator reads as an edit, and would recompile for nothing.
    if (!file.existsSync() || file.readAsStringSync() != content) {
      file.writeAsStringSync(content);
    }
    return path;
  }
}

/// Where the generated entrypoint goes, relative to the package.
const storeFrameEntrypointPath =
    '${StoreFrameRunner.buildDirectory}/store_frames.dart';
