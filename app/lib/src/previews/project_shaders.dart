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

/// sha1 over the source and every local `#include`, recursively.
///
/// An include is looked for where the compiler looks: beside the file that
/// names it, then in [source]'s own directory, which is the one `--include`
/// [compileShader] passes on the project's behalf. Each file counts its
/// path relative to [source]'s directory as well as its bytes, so moving an
/// include without editing it is still a new key, and counts once however
/// often it is met, which is also what stops a cycle.
///
/// An include that resolves to neither is the engine's own `shader_lib`
/// (`<flutter/runtime_effect.glsl>`), which changes only with the engine —
/// and the engine revision is already in the directory this key is used
/// under.
String projectShaderHash(String source) {
  var input = BytesBuilder(copy: false);
  var seen = <String>{};
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
      for (var dir in [p.dirname(path), base]) {
        var candidate = p.join(dir, name);
        if (File(candidate).existsSync()) {
          visit(candidate);
          break;
        }
      }
    }
  }

  visit(source);
  return sha1.convert(input.takeBytes()).toString();
}

/// The compiled form of the shader at [source], and its reflection.
///
/// Compiles once per content: a warm call hashes the files and finds the
/// binary already there. [compileShader] renames the binary into place after
/// the reflection, so the binary existing is the whole of "done".
///
/// Throws [StateError] carrying `impellerc`'s own message when the shader does
/// not compile, and leaves no binary behind, so a later call for the same
/// content runs the compiler again.
Future<CompiledShader> compileProjectShader({
  required FlutterCache cache,
  required String source,
}) async {
  var dir = p.join(
    flutterwareDir(),
    'shaders',
    'project',
    '${cache.engineRevision}-$shaderStagesKey',
    projectShaderHash(source),
  );
  var compiled = CompiledShader(
    binary: p.join(dir, 'shader.iplr'),
    reflection: p.join(dir, 'reflection.json'),
  );
  if (File(compiled.binary).existsSync()) return compiled;
  Directory(dir).createSync(recursive: true);
  await compileShader(
    cache: cache,
    source: source,
    destination: compiled.binary,
    stages: shaderStages,
    reflection: compiled.reflection,
  );
  return compiled;
}
