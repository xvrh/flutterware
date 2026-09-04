// Running the generator over a directory of scenes.
//
// Load order, and the reason this is its own step: declarations come before
// scene files. A scene file spells `const DrinkBadgeArgs(size: 140)`, whose
// class is written from the app's declaration of that widget — so the
// declaration is read, the classes are written, and only then does anything
// parse a scene.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'args_codegen.dart';
import 'discovery.dart';
import 'externals_file.dart';
import 'scene_file.dart';

/// Where a package declares the widgets its scenes may place.
const sceneExternalsFileName = 'scene_externals.dart';

/// What a generation run had to say.
class SceneArgsResult {
  SceneArgsResult({
    required this.path,
    required this.wrote,
    this.refusals = const [],
    this.source,
  });

  /// The generated file, or null when there was nothing to generate.
  final String? path;

  /// Whether the file changed. A run that writes nothing is the common one:
  /// the generator is called on every scan, and a scan usually finds what
  /// the last one did.
  final bool wrote;

  /// Why the declarations could not be read. The generated file is left
  /// exactly as it was — half a vocabulary is worse than a stale one.
  final List<SceneRefusal> refusals;

  /// What the generator produced, whether or not it was written.
  final String? source;
}

/// Writes `scene_args.dart` for the scenes under [directory].
///
/// Both halves are read here: the app's declaration file, if it has one, and
/// every scene class's own parameters — which need no declaration, because
/// a scene already says what it takes in its header.
SceneArgsResult generateSceneArgsIn(String directory, {bool write = true}) {
  var dir = Directory(directory);
  if (!dir.existsSync()) return SceneArgsResult(path: null, wrote: false);

  var externals = <ExternalWidgetDecl>[];
  String? externalsImport;
  var declarationFile = File(p.join(directory, sceneExternalsFileName));
  if (declarationFile.existsSync()) {
    var parsed = parseExternalsFile(declarationFile.readAsStringSync());
    if (!parsed.ok) {
      return SceneArgsResult(
        path: null,
        wrote: false,
        refusals: parsed.refusals,
      );
    }
    externals = parsed.widgets;
    externalsImport = sceneExternalsFileName;
  }

  var scenes = <SceneClassDecl>[];
  for (var entry in discoverScenes(directory)) {
    var parsed = parseSceneFile(File(entry.path).readAsStringSync());
    // A scene that does not parse is the panel's problem to report with line
    // numbers; here it simply contributes no arguments class, and the one it
    // had last time stays until it parses again.
    if (parsed.doc == null) continue;
    scenes.add(
      SceneClassDecl(
        entry.className,
        parsed.doc!.params.toList(),
        p.url.joinAll(p.split(p.relative(entry.path, from: directory))),
      ),
    );
  }
  scenes.sort((a, b) => a.className.compareTo(b.className));

  var target = File(p.join(directory, sceneArgsFileName));
  if (externals.isEmpty && scenes.isEmpty) {
    return SceneArgsResult(path: target.path, wrote: false);
  }
  var source = emitSceneArgs(
    externals: externals,
    scenes: scenes,
    externalsImport: externalsImport,
  );
  if (target.existsSync() && target.readAsStringSync() == source) {
    return SceneArgsResult(path: target.path, wrote: false, source: source);
  }
  if (write) target.writeAsStringSync(source);
  return SceneArgsResult(path: target.path, wrote: write, source: source);
}
