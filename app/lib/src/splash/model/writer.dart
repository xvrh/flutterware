/// Writing one key back into a splash config.
///
/// The rule this file exists to hold: **write only the keys we mean, and never
/// round-trip the file.** Decoding a config with `loadYaml` and re-encoding it
/// would lose every comment, every blank line and the author's key order — for
/// a `pubspec.yaml`, which is where a great many of these configs live, that is
/// a diff nobody would accept from a tool. `yaml_edit` splices the new value
/// into the original text and leaves the rest byte-for-byte, so a fix shows up
/// in `git diff` as the one line it actually is.
///
/// **All three config kinds take the same path.** A standalone
/// `flutter_native_splash.yaml`, a `flutter_native_splash-<flavor>.yaml` and
/// the `flutter_native_splash:` block inside a `pubspec.yaml` all nest their
/// keys under a top-level `flutter_native_splash:` — the generator reads
/// `yamlMap['flutter_native_splash']` whichever file it opened (see
/// `model/scan.dart`). So [editSplashConfig] never asks which kind it is
/// holding, and there is no branch here that could get one of them wrong.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'config.dart';

/// The key every config nests under, whichever file it lives in.
const splashConfigSection = 'flutter_native_splash';

/// One key to set, or to remove when [value] is null.
class SplashWrite {
  const SplashWrite(this.key, this.value);

  const SplashWrite.remove(this.key) : value = null;

  /// Dotted for the nested section — `color_dark`, `android_12.image`. The same
  /// spelling `SplashProblem.key` uses and the same one the panel prints beside
  /// a value, so a fix can be read against the caption that provoked it.
  final String key;

  /// `null` removes the key. A splash config has no meaningful null value —
  /// `color:` with nothing after it is a key the generator ignores — so there is
  /// nothing to be ambiguous about.
  final Object? value;

  /// The path into the document, section included.
  List<Object?> get path => [splashConfigSection, ...key.split('.')];

  @override
  String toString() => value == null ? 'remove $key' : '$key: $value';
}

/// Applies [writes] to [source] and returns the new text.
///
/// Pure, so the interesting half is testable without a filesystem and a caller
/// can show a diff before committing to it.
///
/// Two traps in `yaml_edit`, both of which throw rather than no-op:
///
/// - `update` traverses to the **parent** of the path and requires it to be a
///   mapping. Setting `android_12.image` on a config with no `android_12:`
///   section throws, and so does any write at all against an empty file.
/// - `remove` requires the node itself to exist. Removing a key that is already
///   absent is a legitimate thing for a fix to ask for — a rename whose old key
///   was written twice, say — so it is guarded rather than allowed to throw.
///
/// Missing levels are created in **one** write rather than as a chain of empty
/// maps. `update` on an empty map splices in flow style, so creating
/// `android_12:` and then filling it leaves `android_12: {image: …}` sitting in
/// an otherwise block-styled file. Writing the whole nested value at once gets
/// block style, which is what the rest of the config looks like.
String editSplashConfig(String source, List<SplashWrite> writes) {
  var editor = YamlEditor(source);

  for (var write in writes) {
    var path = write.path;

    if (write.value == null) {
      if (_nodeAt(editor, path) != null) editor.remove(path);
      continue;
    }

    // How far down the path a mapping already exists. Depth 0 is the document
    // itself, which is missing exactly when the file is empty.
    var depth = 0;
    while (depth < path.length &&
        _nodeAt(editor, path.sublist(0, depth)) is YamlMap) {
      depth++;
    }

    if (depth == path.length) {
      editor.update(path, write.value);
      continue;
    }

    // Replacing a level that exists and is not a mapping is fine — an
    // `android_12: true` is not a config, it is a mistake. Replacing the whole
    // *document* is not: that would discard a file we never understood.
    if (depth == 0 && _nodeAt(editor, const []) != null) {
      throw StateError(
        'The root of this file is not a mapping, so there is nowhere to write '
        '"${write.key}".',
      );
    }

    var nested = write.value;
    for (var i = path.length - 1; i >= depth; i--) {
      nested = <String, Object?>{'${path[i]}': nested};
    }
    editor.update(path.sublist(0, depth), nested);
  }

  return editor.toString();
}

/// The node at [path], or null when the path does not lead anywhere.
///
/// `parseAt` takes an `orElse`, but it returns a `YamlNode` — there is no way to
/// say "nothing" through it, and a `YamlScalar(null)` is also what an empty
/// `android_12:` parses to. Catching is the only way to tell the two apart, and
/// the difference matters: one wants creating, the other wants replacing.
YamlNode? _nodeAt(YamlEditor editor, List<Object?> path) {
  try {
    var node = editor.parseAt(path);
    return node.value == null ? null : node;
  } catch (_) {
    return null;
  }
}

/// Writes keys back into the file one config came from.
///
/// Built from a [SplashConfig] because the config already knows which of the
/// three files it was read from — asking a caller to say again is how the GUI
/// and the CLI come to write to different files.
class SplashWriter {
  SplashWriter({required this.packageRoot, required this.config});

  /// Absolute.
  final String packageRoot;

  final SplashConfig config;

  File get file => File(p.join(packageRoot, config.path));

  /// Applies [writes] and returns the path written, package-relative.
  ///
  /// Reads the file again rather than working from [SplashConfig.raw]: the
  /// config may have been scanned seconds ago and edited since, and splicing
  /// into stale text would silently revert whatever the author just typed.
  Future<String> apply(List<SplashWrite> writes) async {
    if (writes.isEmpty) return config.path;
    var target = file;
    var source = await target.exists() ? await target.readAsString() : '';
    var edited = editSplashConfig(source, writes);
    if (edited != source) await target.writeAsString(edited);
    return config.path;
  }
}
