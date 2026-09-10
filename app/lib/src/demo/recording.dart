import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../launcher_icon/model/scan.dart';
import '../launcher_icon/screen.dart';
import '../plugins/scan_cache.dart';
import '../scenarios/artifacts.dart';
import 'recording_paths.dart';

export '../scenarios/artifacts_io.dart' show FileScenarioArtifacts;
export 'recording_paths.dart';

/// Where a recording is read from.
///
/// The scenario artifacts interface, under the name this use gives it: a
/// path-addressed store of bytes, text and images with a file end, an HTTP end
/// and — below — an asset end. It was written for a run's captured artifacts,
/// and a recording is the same shape: things the tool wrote once, read by
/// widgets that must not care where from. Renaming the interface to say so is
/// a follow-up; aliasing it says so here without touching the scenarios.
typedef Recording = ScenarioArtifacts;

/// A recording bundled into the app as assets.
///
/// This is the end that works everywhere the studio's own widgets are drawn:
/// the previews guest, whose working directory is not the package's; a
/// `flutter test`; and the web, where there is no disk at all and the asset
/// bundle is fetched. The file end (`FileScenarioArtifacts`) stays the one for
/// a scenario, which runs under FakeAsync and needs its reads synchronous.
class AssetRecording extends ScenarioArtifacts {
  const AssetRecording({this.prefix = defaultPrefix});

  /// Where `pubspec.yaml` declares the recording — see the `assets:` list.
  static const defaultPrefix = 'demo/fixture';

  final String prefix;

  String _key(String path) => '$prefix/$path';

  @override
  Future<Uint8List?> readBytes(String path) async {
    try {
      var data = await rootBundle.load(_key(path));
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readString(String path) async {
    try {
      return await rootBundle.loadString(_key(path));
    } catch (_) {
      return null;
    }
  }

  @override
  ImageProvider encodedImage(String path) => AssetImage(_key(path));

  @override
  Uri uriOf(String path) => Uri(path: _key(path));
}

/// A launcher-icon reader that answers from [recording] instead of the disk.
///
/// Handed to `LauncherIconCore(scan: …)`. The core is otherwise the live one:
/// same cache, same report, same panel. The package root is never asked for,
/// which is what lets this run where there is no filesystem.
IconScanner recordedIconScanner(Recording recording) =>
    ({required packageRoot, required packagePath, flavor}) async {
      var path = recordedIconScanPath(packagePath, flavor: flavor);
      // Through `Future.value`, so that a synchronous end — the file one hands
      // back `SynchronousFuture`s — still resumes this function on a microtask.
      // Resumed inline, a throw below would escape `await` into the zone
      // instead of failing the returned future, and no caller could catch it.
      var text = await Future.value(recording.readString(path));
      if (text == null) {
        throw ScanFailure(
          'This recording has no launcher icon scan for "$packagePath"'
          '${flavor == null ? '' : ' under the "$flavor" flavor'} '
          '(looked for $path).',
        );
      }
      return IconScan.fromJson(jsonDecode(text) as Map<String, Object?>);
    };

/// The pictures of a recorded scan: its files were copied into the recording
/// under the path each `absolutePath` now carries.
IconImage recordedIconImage(Recording recording) =>
    (file) => recording.encodedImage(file.absolutePath);
