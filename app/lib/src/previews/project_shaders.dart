// A project's own fragment shaders, compiled the way flutterware's lanes need
// them: every runtime stage at once, because one bundle feeds the harness, the
// guest and the render bundle, and with the compiler's list of uniforms beside
// the bytes, because the studio edits a shader through that list.
//
// Cached by CONTENT — the source and every local include — where the
// framework's two shaders are cached by name: theirs change only with the
// engine, which is already in the directory name; a project's change on every
// save.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../embedder/flutter_cache.dart';
import '../utils/run_dir.dart';
import 'asset_bundle.dart';

class CompiledShader {
  const CompiledShader({required this.binary, required this.reflection});

  /// The runtime-stage bundle `FragmentProgram.fromAsset` parses.
  final String binary;

  /// What `impellerc --reflection-json` wrote beside it: the uniforms and
  /// samplers the shader declares, each with its location and its type.
  final String reflection;
}

final _include = RegExp(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', multiLine: true);

/// How many times [projectShaderHashWithFiles] has actually hashed a
/// shader's content — every call, hit or miss. The function has no other
/// externally visible effect on a hit, so this is a test's seam for "did
/// this re-hash".
@visibleForTesting
var projectShaderHashCallsForTesting = 0;

/// sha1 over the source and every local `#include`, recursively.
///
/// An include is looked for where the compiler looks: beside the file that
/// names it, then in [source]'s own directory, which is the one `--include`
/// [compileShader] passes on the project's behalf. Each file counts its
/// path relative to [source]'s directory as well as its bytes, so moving an
/// include without editing it is still a new key, and counts once however
/// often it is met, which is also what stops a cycle.
///
/// An include that resolves to neither is one of two things, told apart by
/// its first segment. Under `flutter/` or `impeller/` it is the engine's own
/// `shader_lib` (`<flutter/runtime_effect.glsl>`) — the two directories the
/// other `--include` holds — which changes only with the engine, and the
/// engine revision is already in the directory this key is used under; it
/// adds nothing. Anything else is a file that is not there yet, and it adds
/// `missing:<name>`: the compile of a source naming it fails, that failure
/// is remembered by this key, and creating the file without touching the
/// source has to be a new key or the failure is served for good.
String projectShaderHash(String source) =>
    projectShaderHashWithFiles(source).hash;

/// Like [projectShaderHash], but also returns every file whose bytes fed
/// it — [source] and each local `#include`, normalized and absolute — so a
/// caller can watch those exact files for a change instead of re-hashing on
/// every call; and, as [missing], every place an include that is not there
/// yet would be found, so a caller can watch for it to appear.
({String hash, List<String> files, List<String> missing})
projectShaderHashWithFiles(String source) {
  projectShaderHashCallsForTesting++;
  var input = BytesBuilder(copy: false);
  var seen = <String>{};
  var missing = <String>{};
  var base = p.dirname(p.normalize(p.absolute(source)));
  void visit(String file) {
    var path = p.normalize(p.absolute(file));
    if (!seen.add(path)) return;
    var bytes = File(path).readAsBytesSync();
    input
      ..add(utf8.encode(p.relative(path, from: base)))
      ..addByte(0)
      ..add(bytes)
      ..addByte(0);
    var text = utf8.decode(bytes, allowMalformed: true);
    for (var match in _include.allMatches(text)) {
      var name = match.group(1)!;
      var candidates = {
        for (var dir in [p.dirname(path), base]) p.join(dir, name),
      };
      var found = candidates.where((c) => File(c).existsSync()).firstOrNull;
      if (found != null) {
        visit(found);
      } else if (!_engineOwned(name)) {
        input
          ..add(utf8.encode('missing:$name'))
          ..addByte(0);
        missing.addAll(candidates.map((c) => p.normalize(p.absolute(c))));
      }
    }
  }

  visit(source);
  return (
    hash: sha1.convert(input.takeBytes()).toString(),
    files: seen.toList(),
    missing: missing.toList(),
  );
}

/// Whether an include that is not the project's names the engine's
/// `shader_lib`: its `flutter/` and `impeller/` directories.
bool _engineOwned(String name) =>
    const {'flutter', 'impeller'}.contains(p.posix.split(name).first);

/// `impellerc` refused a project shader; [message] is what it said.
class ProjectShaderError extends StateError {
  ProjectShaderError(super.message, {required this.entry});

  /// The cache directory the failure belongs to — the content, the engine and
  /// the stage list — so a caller can report it once per entry, as it is
  /// compiled once per entry.
  final String entry;
}

/// What `impellerc` said about each cache entry it refused.
///
/// A failure is as deterministic as a success — the entry names the content,
/// the engine and the stage list — and remembering it is what keeps a `.frag`
/// that stays broken from spawning the compiler on every rebundle, which the
/// daemon runs every few seconds for as long as previews are open.
final _failures = <String, String>{};

@visibleForTesting
void resetProjectShaderFailuresForTesting() => _failures.clear();

/// Called between hashing a shader and compiling it, so a test can edit the
/// source in exactly the window a save can.
@visibleForTesting
void Function(String source)? beforeProjectShaderCompileForTesting;

/// How many compiles one call makes of a source that changes under each of
/// them before it returns one that is not cached.
const _attempts = 3;

var _stagingSerial = 0;

/// The compiled form of the shader at [source], and its reflection.
///
/// Compiles once per content: a warm call hashes the files and finds the
/// binary already there. The binary is renamed into place after the
/// reflection, so the binary existing is the whole of "done".
///
/// The hash is taken before `impellerc` reads the files, and a save can land
/// between the two — which would file the new text's program under the old
/// text's key, served for good the day the old text comes back. So the
/// compile goes to a staging directory of its own, the files are hashed
/// again, and only bytes whose content held still for the whole compile are
/// renamed into the entry. One that moved is compiled again as what it now
/// is; after [_attempts] of those the last compile is returned from outside
/// the cache, and the next call, the file at rest, files it properly.
///
/// Throws [ProjectShaderError] carrying `impellerc`'s own message when the
/// shader does not compile. The failure is remembered for the process, so
/// asking again for the same content throws the same message without running
/// the compiler.
Future<CompiledShader> compileProjectShader({
  required FlutterCache cache,
  required String source,
}) async {
  var root = p.join(
    flutterwareDir(),
    'shaders',
    'project',
    '${cache.engineRevision}-$shaderStagesKey',
  );
  for (var attempt = 1; ; attempt++) {
    var entry = p.join(root, projectShaderHash(source));
    var compiled = _compiledAt(entry);
    if (File(compiled.binary).existsSync()) return compiled;
    if (_failures[entry] case var message?) {
      throw ProjectShaderError(message, entry: entry);
    }

    var staging = p.join(root, 'staging', '$pid.${_stagingSerial++}');
    Directory(staging).createSync(recursive: true);
    var staged = _compiledAt(staging);
    try {
      beforeProjectShaderCompileForTesting?.call(source);
      String? failure;
      try {
        await compileShader(
          cache: cache,
          source: source,
          destination: staged.binary,
          stages: shaderStages,
          reflection: staged.reflection,
        );
      } on StateError catch (error) {
        failure = error.message;
      }
      var held = p.join(root, projectShaderHash(source)) == entry;
      if (held && failure != null) {
        _failures[entry] = failure;
        throw ProjectShaderError(failure, entry: entry);
      }
      if (held) {
        Directory(entry).createSync(recursive: true);
        return _moveInto(staged, compiled);
      }
      if (attempt == _attempts) {
        // Whose text a failure here is about is not known, so it is not
        // remembered; the next call compiles again.
        if (failure != null) throw ProjectShaderError(failure, entry: entry);
        // One place per source rather than per call, so a file that keeps
        // moving does not leave a directory per rebundle behind.
        var unsettled = p.join(
          root,
          'unsettled',
          sha1.convert(utf8.encode(p.absolute(source))).toString(),
        );
        Directory(unsettled).createSync(recursive: true);
        return _moveInto(staged, _compiledAt(unsettled));
      }
    } finally {
      Directory(staging).deleteSync(recursive: true);
    }
  }
}

CompiledShader _compiledAt(String dir) => CompiledShader(
  binary: p.join(dir, 'shader.iplr'),
  reflection: p.join(dir, 'reflection.json'),
);

/// Renames [from]'s two files onto [to]'s, the binary last: its existence is
/// what [compileProjectShader] takes to mean the reflection is there too.
CompiledShader _moveInto(CompiledShader from, CompiledShader to) {
  File(from.reflection).renameSync(to.reflection);
  File(from.binary).renameSync(to.binary);
  return to;
}
