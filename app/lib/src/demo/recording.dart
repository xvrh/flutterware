import 'dart:convert';

import '../launcher_icon/model/scan.dart';
import '../launcher_icon/screen.dart';
import '../plugins/scan_cache.dart';
import '../scenarios/artifacts.dart';
import 'recording_paths.dart';

export '../scenarios/artifacts_http.dart' show HttpScenarioArtifacts;
export '../scenarios/artifacts_io.dart' show FileScenarioArtifacts;
export 'recording_paths.dart';

/// Where a recording is read from.
///
/// The scenario artifacts interface, under the name this use gives it: a
/// path-addressed store of bytes, text and images with a file end and an HTTP
/// end. It was written for a run's captured artifacts, and a recording is the
/// same shape: things the tool wrote once, read by widgets that must not care
/// where from. Renaming the interface to say so is a follow-up; aliasing it
/// says so here without touching the scenarios.
///
/// Two ends and no third. The file end is what a scenario, a widget test and
/// a catalog demo open — synchronous reads, which a walk under FakeAsync
/// needs, and a working directory that is the package's, which the previews
/// guest has. The HTTP end is the web page's, fetching from wherever the page
/// was served: `tool/demo/build_web.dart` copies the recording beside the
/// build. There is deliberately no asset end: a recording declared in
/// `pubspec.yaml` rides in every desktop build of the studio, and it grows
/// with every plugin recorded.
typedef Recording = ScenarioArtifacts;

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
