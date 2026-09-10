# Scene text layers: shader paint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A text pass can be painted with one of the project's own fragment shaders — `ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': 0.4})` — in every flutterware lane, animated by scene time, reloaded in place when the `.frag` changes, and edited in the scene inspector with controls built from the compiler's own list of uniforms.

**Architecture:** flutterware's asset bundler learns `flutter: shaders:` (compiled with `impellerc` into a content-keyed cache, reflection JSON beside it), and the compiler daemon tells live guests which keys changed so they call `ext.ui.window.reinitializeShader`. The paint value lives in the pure core beside the gradients; the Flutter half gets a program cache (loads tracked by `RealWork`, a per-draw-slot shader pool) and the stack painter paints every shader pass as glyph coverage with the shader drawn over it (`srcIn`), placed by the canvas transform. Scene time reaches the painter as a clock it listens to — never as a rebuilt value — from `Playable.clock`, or from a new `time` field on the editor's wire. The studio reads a shader's uniforms from the reflection JSON plus `// @range`, `// @color`, `// @default` comments.

**Tech Stack:** Dart 3 / Flutter 3.48.0-0.2.pre (pinned in `.fvmrc`), `dart:ui` `FragmentProgram`/`FragmentShader`, `impellerc` from the pinned engine, the scene grammar (package `analyzer` AST), the studio design system (`app/lib/src/ui/`).

**Spec:** `docs/superpowers/specs/2026-09-10-scene-shader-paint-design.md` (the spike's output — decisions 1–11 and the build order). One decision is corrected by this plan, argued under **Corrections to the spec** below; Task 11 writes the correction back into the spec.

## Global Constraints

- Every Flutter/Dart command goes through fvm: `fvm flutter …` / `fvm dart …`. Never the PATH `dart`/`flutter`.
- Format only with `fvm dart tool/prepare_submit.dart` — never bare `dart format`.
- Lints: `var` for locals (`omit_local_variable_types`), single quotes, no `final` parameters, `unawaited(...)` for fire-and-forget, raw strings where they apply. Do not add `const` beyond what the code around it already uses.
- **Nothing written here may name a client, their repository, their people or their product** — code, comments, tests, commit messages, PR text.
- `lib/src/scene/core/` stays pure Dart: no `package:flutter` and no `dart:ui` import there (a test guards the import graph).
- Wire decoding is total: an unreadable payload decodes to null or the default, never throws.
- The file grammar omits every default, `emit ∘ parse` is the identity, and anything off the allowlist is refused **by name, with what to write instead** — never dropped silently.
- **A pass may change paint, never layout.** Nothing here adds a metric property to a pass, and a uniform or time change must never cost a relayout.
- `lib/src/scene/` and `lib/src/render/` are published API (`lib/scene.dart`, `lib/scene_authoring.dart`, `lib/render.dart`): new public names are exactly the ones this plan names — `ShaderPaint`, `precacheSceneShaders`, `LayeredText.time`, `SceneView.time`, `Playable.clock`/`position`. Everything else stays in `src/` unexported.
- Renderer-owned uniforms, exactly: `uSize` (vec2, the box's logical size), `uColor` (vec4, the text's own colour, straight RGBA 0–1), `uTime` (float, scene seconds). Each is set only when the shader declares it with that size.
- A shader pass paints **nothing** until its program has loaded, and nothing if it never loads. Never a stand-in colour.
- A uniform the shader does not declare (or declares at another size) is skipped and reported once per asset and name — never thrown in `paint`.
- GUI: tokens only (`context.colors`, `context.type`, `FwSpacing`, `context.radii`, `FwIconSize`); pickers are `FwPicker`, never `DropdownButton`; a `TextField` stays bare; controls come from `app/lib/src/ui/` and `app/lib/src/scene/ui/`; every drag detector in the scene editor passes `supportedDevices: editingDevices`.
- Commit titles name what changed and where, one plain line, no trailing period. Every commit ends with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- One PR at the end, not one per task. Commit only; never push.

## Corrections to the spec

1. **Scene time reaches the painter as a listenable clock, not a value `shouldRepaint` compares** (spec decision 7). A seek that changes no track writes no fx, so the scene never notifies and `SceneView` never rebuilds — a `time` value handed down at build would stay where it was. So `Playable` keeps its position in a `SceneValue<Duration> clock`; `SceneView` and `LayeredText` take a `ValueListenable<Duration>? time`; and the stack painter lists that clock in its `repaint` listenable **only when the stack holds a shader pass**. Same intent as the spec — text without a shader never repaints for time — and it survives a motion that animates nothing but `uTime`.
2. **Cached uniform handles are dropped on reassemble.** `reinitializeShader` swaps a program in place and zeroes every uniform, so the painter sets every uniform on every paint (it would anyway), and `LayeredText`'s state drops its shader slots in `reassemble()`. The daemon's reload (Task 3) calls `reinitializeShader` *before* the `ext.flutter.reassemble` it already sends.
3. **The bundler's shader cache is content-keyed** (source bytes plus every local `#include`, recursively), under its own directory. The framework's two shaders keep their basename-keyed cache untouched.
4. **The editor settles by the reply, not by polling the guest.** `ext.fw.scene.apply` answers with the programs still loading; the studio's `SceneGuest` is busy while a push is in flight or the last reply named pending programs, and re-pushes until none are left. `ScenePlugin.busyWith` reads it.

## File map

**Create**
- `app/lib/src/previews/project_shaders.dart` — `compileProjectShader`, `projectShaderHash`, `CompiledShader`: a project `.frag` compiled for flutterware's stage union, with reflection, cached by content.
- `lib/src/scene/shader_programs.dart` — `SceneShaderPrograms` (process-wide program cache, `RealWork`-tracked, a `Listenable`), `SceneShaderSlots`/`SceneShaderSlot` (per-draw-slot shaders, uniform setting), `precacheSceneShaders`.
- `app/lib/src/scene/shader_library.dart` — `declaredShaders`, `readShaderUniforms`, `SceneShaderUniform`, `SceneShaderInfo`, `SceneShaders`, `SceneShaderLibrary`, `FixedSceneShaders`.
- `app/lib/src/scene/ui/shader_field.dart` — `SceneShaderField`: asset picker plus uniform controls.
- `app/test/scene/shaders/probe.frag`, `app/test/scene/shaders/probe_bare.frag` — test shaders, declared in `app/pubspec.yaml`.
- `examples/example/shaders/foil.frag`, `examples/example/demo/foil_title.scene.dart` — the example.
- Tests: `app/test/previews/project_shaders_test.dart`, `app/test/scene/scene_shader_programs_test.dart`, `app/test/scene/scene_shader_paint_test.dart`, `app/test/scene/scene_shader_capture_test.dart`, `app/test/scene/scene_shader_library_test.dart`, `app/test/scene/scene_shader_field_test.dart`.

**Modify**
- `app/lib/src/assets/model/asset_catalog.dart` — `ResolvedShader`, `AssetCatalog.shaders`, `AssetProblemKind.missingShaderFile`.
- `app/lib/src/previews/asset_bundle.dart` — link project shaders; `BundleSync.shaders`; `compileShader(reflection:)`.
- `app/lib/src/previews/protocol.dart`, `app/tool/catalog/compiler_daemon.dart`, `app/lib/src/previews/catalog_session.dart` — `AssetsChanged.shaders`; `reinitializeShader`.
- `lib/src/scene/core/values.dart` — `ShaderPaint`, its wire.
- `lib/src/scene/core/motion_runtime.dart` — `Playable.clock`, `position`.
- `lib/src/scene/layered_text.dart` — stateful; shader pass; `time`; slots.
- `lib/src/scene/view.dart` — `SceneView.time`, clock to `LayeredText`.
- `lib/src/scene/host.dart` — `SceneCanvasHost` reads `time`, waits for programs, answers `pendingShaders`.
- `lib/src/scene/flutter_bridge.dart` — a `ValueListenable` adapter over `SceneValue`.
- `lib/scene.dart` — export `precacheSceneShaders`.
- `app/lib/src/scene/paint_grammar.dart`, `app/lib/src/scene/gradient_edit.dart`, `app/lib/src/scene/ui/paint_field.dart`, `app/lib/src/scene/ui/layer_list.dart`, `app/lib/src/scene/ui/inspector.dart`, `app/lib/src/scene/ui/workspace_view.dart`, `app/lib/src/scene/guest.dart`, `app/lib/src/plugins/native/scene_plugin.dart`.
- `app/pubspec.yaml` (test shaders), `examples/example/pubspec.yaml` (spike lines out, `foil.frag` in), `.github/workflows/analyze-and-test.yaml` (an Impeller run of the shader pixel test).
- `app/tool/catalog/demos/scene_paint_field.dart` — a shader specimen.
- Delete: `examples/example/demo/spike_shader_main.dart`, `examples/example/demo/spike_shader_text.dart`, `examples/example/test/spike_shader_text_test.dart`, `examples/example/test/spike_uniform_mutation_test.dart`, `examples/example/test/spike_shared_shader_test.dart`, `examples/example/shaders/spike_foil.frag`, `examples/example/shaders/spike_foil_filter.frag`, `examples/example/assets/spike_iplr/`.

## Facts the tasks rely on (measured 2026-09-10 on the pinned SDK)

- `impellerc --reflection-json=<file>` writes `{"uniforms": [...], "sampled_images": [...], ...}`. Each uniform: `name`, `location` (declaration order — the array itself is NOT in declaration order), `type.type_name` (`"ShaderType::kFloat"` for float/vecN), `type.vec_size` (1–4), `type.columns` (1 unless a matrix). A declared-but-unused uniform is kept.
- `impellerc --depfile=<file>` also works, but this plan hashes includes itself (Task 2) rather than depending on a previous compile's depfile.
- `FragmentShader.getUniformVec2/3/4(name)` throw `ArgumentError` when the name is undeclared **or** the size differs. `getUniformFloat(name, [index])` checks the name and only the index bound: on a `vec2` it succeeds at index 0. So a float is told from a wider uniform by also asking for index 1 and expecting an `ArgumentError` (`IndexError` is one).
- `reinitializeShader` re-creates every live `FragmentShader`'s float storage (all uniforms zero) and drops slots whose uniform is gone.
- A paragraph snapshots its foreground shader's uniforms at build; a `drawRect` snapshots them at the call. The vector capture (`lib/src/render/model.dart` `VgPaint.from`) keeps `ui.Paint.from(paint)` — the SAME shader object — and replays it later in `rasterizeUnsupported`.
- `RealWork.run(work, label:)` (`lib/src/real_work/tracker.dart`) starts `work` on `Zone.root` and tracks it; a load memoized across scenarios must use it, not `track`, or a future started inside one scenario's FakeAsync zone never completes for the next.
- Plain `flutter test` compiles a package's own `flutter: shaders:`; the test font draws every glyph as a filled box, so pixel tests read colours off solid ink.

---

### Task 1: The asset catalog reads `flutter: shaders:`

**Files:**
- Modify: `app/lib/src/assets/model/asset_catalog.dart`
- Test: `app/test/assets/asset_catalog_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ResolvedShader {
    ResolvedShader({required this.key, required this.package, required this.packageRoot, required this.declaration, required this.source});
    final String key;          // 'shaders/glow.frag', or 'packages/dep/shaders/glow.frag'
    final String? package;     // null for the root package
    final String packageRoot;
    final String declaration;  // the pubspec entry as written
    final String source;       // absolute path of the .frag
  }
  // on AssetCatalog:
  final List<ResolvedShader> shaders;
  // new AssetProblemKind member:
  missingShaderFile('Shader declared, and not on disk.'),
  ```

`flutter: shaders:` is a flat list of package-relative file paths (no directories, no maps, no transformers). Keys follow the same rule as assets: unprefixed for the root package, `packages/<name>/<path>` for a dependency. Shaders are NOT added to `assets` — a shader's bundle bytes are a compile, not the file on disk, and nothing that walks `catalog.assets` (the manifest, byte totals, the asset tree) should see one. `FragmentProgram.fromAsset` does not consult `AssetManifest.bin`.

- [ ] **Step 1: Read the catalog and its tests**

Read `_Resolver.readPubspec` (around line 468) and `_addFonts` (around 760–795) in `asset_catalog.dart`, and the fixture helpers at the top of `app/test/assets/asset_catalog_test.dart`. The font branch is the template: it resolves a declared file against the package root, prefixes the key, and records `missingFontFile` when the file is absent.

- [ ] **Step 2: Write the failing tests**

Add a group to `asset_catalog_test.dart`, using that file's own fixture helpers (write a pubspec, write a file, resolve):

```dart
group('shaders', () {
  test("the root package's shader is keyed as declared", () async {
    // pubspec: flutter: shaders: [shaders/glow.frag]; file shaders/glow.frag exists
    var catalog = await resolve();
    expect(catalog.shaders.map((s) => s.key), ['shaders/glow.frag']);
    expect(catalog.shaders.single.package, isNull);
    expect(catalog.shaders.single.source, p.join(root.path, 'shaders', 'glow.frag'));
  });

  test("a dependency's shader is keyed under its package", () async {
    // dependency `dep` declares shaders: [shaders/x.frag]
    var catalog = await resolve();
    expect(catalog.shaders.map((s) => s.key), contains('packages/dep/shaders/x.frag'));
  });

  test('a declared shader that is not on disk is a problem, not a key', () async {
    // pubspec declares shaders/missing.frag; no file
    var catalog = await resolve();
    expect(catalog.shaders, isEmpty);
    expect(catalog.problems.map((p) => p.kind), [AssetProblemKind.missingShaderFile]);
  });

  test('a shader is not an asset', () async {
    var catalog = await resolve();
    expect(catalog.assets.map((a) => a.key), isNot(contains('shaders/glow.frag')));
  });
});
```

Adapt the fixture calls to the file's actual helpers; the assertions are the contract.

- [ ] **Step 3: Run to see them fail**

Run: `cd app && fvm flutter test test/assets/asset_catalog_test.dart`
Expected: FAIL — `shaders` is not a member of `AssetCatalog`.

- [ ] **Step 4: Implement**

Add `ResolvedShader` and the `shaders` field (constructor parameter, defaulting to empty where the catalog is built elsewhere in tests). In `readPubspec`, beside `assets:` and `fonts:`:

```dart
if (flutter['shaders'] case YamlList shaders) {
  for (var entry in shaders) {
    if (entry is! String) continue;
    var source = p.normalize(p.join(packageRoot, entry));
    if (!File(source).existsSync()) {
      problems.add(AssetProblem(
        kind: AssetProblemKind.missingShaderFile,
        package: packageName,
        packageRoot: packageRoot,
        declaration: entry,
      ));
      continue;
    }
    shaders.add(ResolvedShader(
      key: packageName == null ? entry : 'packages/$packageName/$entry',
      package: packageName,
      packageRoot: packageRoot,
      declaration: entry,
      source: source,
    ));
  }
}
```

Match the local names the resolver actually uses (`problems`, the accumulator it passes to the catalog). Grep `AssetProblemKind` across `app/lib` and `app/test` and give any exhaustive switch the new member.

- [ ] **Step 5: Run the tests**

Run: `cd app && fvm flutter test test/assets/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/assets/model/asset_catalog.dart app/test/assets/asset_catalog_test.dart
git commit -m "Assets: read the shaders a pubspec declares into the catalog

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The bundle compiles the project's shaders, with reflection

**Files:**
- Create: `app/lib/src/previews/project_shaders.dart`
- Modify: `app/lib/src/previews/asset_bundle.dart`
- Test: `app/test/previews/project_shaders_test.dart`, `app/test/previews/asset_bundle_test.dart`

**Interfaces:**
- Consumes: `AssetCatalog.shaders` / `ResolvedShader` (Task 1); `compileShader`, `shaderStages`, `FlutterCache`, `flutterwareDir()` (existing).
- Produces:
  ```dart
  // project_shaders.dart
  class CompiledShader {
    const CompiledShader({required this.binary, required this.reflection});
    final String binary;      // path of the runtime-stage bundle the engine loads
    final String reflection;  // path of impellerc's --reflection-json beside it
  }
  /// sha1 over the source and every local #include, recursively.
  String projectShaderHash(String source);
  /// Compiles once per content; a warm call is a hash and two existence checks.
  Future<CompiledShader> compileProjectShader({required FlutterCache cache, required String source});
  // asset_bundle.dart
  typedef BundleSync = ({bool changed, bool fontsChanged, Set<String> shaders});
  Future<void> compileShader({required FlutterCache cache, required String source, required String destination, required List<String> stages, String? reflection});
  ```

Design:
- Cache directory: `p.join(flutterwareDir(), 'shaders', 'project', '${cache.engineRevision}-$stagesKey', projectShaderHash(source))` holding `shader.iplr` and `reflection.json`. Make the stage key (today the private `_stagesKey` in `asset_bundle.dart`) a library-visible `shaderStagesKey` so both files share it.
- Hash: sha1 of the source's bytes, then for each `#include` line (`^\s*#\s*include\s*[<"]([^>"]+)[>"]`) resolved first against the including file's directory, then against the source's directory, the resolved path relative to the source's directory plus that file's bytes — recursively, each file once, in the order met. An include that resolves to neither (the engine's `shader_lib`, e.g. `<flutter/runtime_effect.glsl>`) is covered by the engine revision in the directory name and skipped.
- `compileShader` gains `reflection`: when given, adds `--reflection-json=$scratch.json` and, after a successful run, renames the reflection into place **before** the binary (the binary's existence is the "done" marker `compileProjectShader` checks). Keep the existing scratch-then-rename protocol for the binary.
- In `AssetBundleBuilder`, after the framework shaders: for each `catalog.shaders` entry, `compileProjectShader` then `_link(output, shader.key, compiled.binary, sync)`; when that link was created or retargeted, add `shader.key` to `sync.shaders`. Make `_link` report whether it changed anything if it does not already. Compile the project shaders concurrently (`Future.wait`), as the framework ones are.
- A project shader that fails to compile is left out of the bundle (so a stale link is pruned and the program load fails as "not found" — a blank pass), impellerc's message goes to `stderr` once per content hash (a set in a top-level variable), and the build carries on. A broken `.frag` must not take previews down.
- A project key equal to a framework shader's key (`shaders/ink_sparkle.frag`, `shaders/stretch_effect.frag`) is not linked; write one `stderr` line naming the key. The framework's link stands.
- Return `sync.shaders` in `BundleSync`. Update every place that constructs a `BundleSync` record (grep `fontsChanged:`) to pass `shaders`.

- [ ] **Step 1: Write the failing tests**

`app/test/previews/project_shaders_test.dart` — the hash is pure and needs no SDK:

```dart
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fw_shader_hash'));
  tearDown(() => root.deleteSync(recursive: true));

  String write(String relative, String content) {
    var file = File(p.join(root.path, relative))..createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  test('the hash follows the source', () {
    var source = write('shaders/a.frag', 'void main() {}');
    var before = projectShaderHash(source);
    write('shaders/a.frag', 'void main() { }');
    expect(projectShaderHash(source), isNot(before));
  });

  test('the hash follows a local include, however deep', () {
    var source = write('shaders/a.frag', '#include "lib/b.glsl"\nvoid main() {}');
    write('shaders/lib/b.glsl', '#include "c.glsl"\n');
    write('shaders/lib/c.glsl', 'float k = 1.0;');
    var before = projectShaderHash(source);
    write('shaders/lib/c.glsl', 'float k = 2.0;');
    expect(projectShaderHash(source), isNot(before));
  });

  test("the engine's own includes are not files of the project", () {
    var source = write('shaders/a.frag', '#include <flutter/runtime_effect.glsl>\nvoid main() {}');
    expect(() => projectShaderHash(source), returnsNormally);
  });

  test('an include cycle is hashed once', () {
    var source = write('shaders/a.frag', '#include "b.glsl"\n');
    write('shaders/b.glsl', '#include "a.frag"\n');
    expect(() => projectShaderHash(source), returnsNormally);
  });
}
```

In `asset_bundle_test.dart`, add a group beside `'the framework shaders'`, with the same real-SDK setup (`FlutterCache(p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache'))`, `flutterwareDirOverride` into the temp root, `timeout: const Timeout(Duration(minutes: 2))`). The fixture pubspec declares `shaders: [shaders/glow.frag]` and writes:

```glsl
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec3 uTint;
out vec4 fragColor;
void main() { fragColor = vec4(uTint, 1.0); }
```

Tests (names are the contract; bodies follow the file's existing helpers):
1. `"a declared shader lands at its key, compiled"` — `output/shaders/glow.frag` exists, its bytes differ from the source's, and `sync.shaders == {'shaders/glow.frag'}` on the first build.
2. `'its reflection lands beside the compiled bytes'` — `compileProjectShader` for the same source returns a `reflection` path whose JSON's `uniforms` names are `{'uSize', 'uTint'}`.
3. `'an edited shader is compiled again and reported'` — edit the tint expression, rebuild: `sync.changed` is true, `sync.shaders == {'shaders/glow.frag'}`, bytes at the key differ.
4. `'an edited include is compiled again'` — the shader includes `common.glsl`; editing only `common.glsl` changes the bytes at the key.
5. `'a rebuild with nothing changed reports no shader'` — second build: `sync.changed` false, `sync.shaders` empty.
6. `"a shader that does not compile is left out, and the rest still land"` — a second declared shader with a syntax error: the first lands, the build does not throw, the broken key is absent.
7. `'a warm compile spawns nothing'` — the binary's `lastModifiedSync()` is unchanged by a second `compileProjectShader` call.
8. Extend `'two builders compiling at once do not share a scratch'` (or add a sibling) so it also races a project shader and asserts no `*.frag.<pid>.<n>` or `*.json` scratch is left under the cache.

- [ ] **Step 2: Run to see them fail**

Run: `cd app && fvm flutter test test/previews/project_shaders_test.dart test/previews/asset_bundle_test.dart`
Expected: FAIL — `projectShaderHash` / `compileProjectShader` undefined.

- [ ] **Step 3: Implement `project_shaders.dart`**

```dart
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

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../embedder/flutter_cache.dart';
import '../utils/run_dir.dart';
import 'asset_bundle.dart';

class CompiledShader {
  const CompiledShader({required this.binary, required this.reflection});

  final String binary;
  final String reflection;
}

final _include = RegExp(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', multiLine: true);

String projectShaderHash(String source) {
  var sink = AccumulatorSink<Digest>();
  var input = sha1.startChunkedConversion(sink);
  var seen = <String>{};
  var base = p.dirname(source);
  void visit(String file) {
    var path = p.normalize(p.absolute(file));
    if (!seen.add(path)) return;
    var bytes = File(path).readAsBytesSync();
    input
      ..add(utf8.encode(p.relative(path, from: base)))
      ..add([0])
      ..add(bytes)
      ..add([0]);
    for (var match in _include.allMatches(utf8.decode(bytes, allowMalformed: true))) {
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
  input.close();
  return sink.events.single.toString();
}

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
```

`AccumulatorSink` is `package:convert`; if `app/pubspec.yaml` does not already depend on `convert`, hash with `sha1.convert` over one concatenated `BytesBuilder` instead — do not add a dependency for this. Check which `crypto` import the codebase already uses (`AssetTransformerRunner._key`) and follow it.

- [ ] **Step 4: Wire it into `AssetBundleBuilder`**

As described under Design above: the `reflection` parameter on `compileShader`, `shaderStagesKey`, the project loop in `_linkCompiledShaders` (or a sibling `_linkProjectShaders` called right after it from `build()`), the failure and collision rules, `BundleSync.shaders`. `_Sync` (the builder's private accumulator) gains a `shaders` set.

- [ ] **Step 5: Run the tests**

Run: `cd app && fvm flutter test test/previews/`
Expected: PASS. The real-SDK group runs impellerc; a cold run can take tens of seconds.

- [ ] **Step 6: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/previews/ app/test/previews/
git commit -m "Previews: compile a project's own shaders into the bundle, with their reflection

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: A live guest reloads an edited shader in place

**Files:**
- Modify: `app/lib/src/previews/protocol.dart`, `app/tool/catalog/compiler_daemon.dart`, `app/lib/src/previews/catalog_session.dart`
- Test: the protocol's existing test file (grep `AssetsChanged` under `app/test`), `app/integration_test/asset_refresh_test.dart`

**Interfaces:**
- Consumes: `BundleSync.shaders` (Task 2).
- Produces: `AssetsChanged({required bool fontsChanged, List<String> shaders = const []})`, wire key `'shaders'`, decoded totally (absent or malformed → empty).

The daemon already rebuilds the bundle on every refresh poll (3s) and sends `AssetsChanged` when anything moved. A shader recompile now moves its link, so the message goes; it only has to say which keys. Every live guest session then calls `ext.ui.window.reinitializeShader {assetKey: key}` for each, **then** the existing `ext.flutter.evict` + `ext.flutter.reassemble` (the reassemble is what lets `LayeredText` drop cached uniform handles — Task 6). The `TesterHost` lane restarts its guest on any bundle change and needs nothing.

- [ ] **Step 1: Write the failing protocol test**

Beside the existing `AssetsChanged` coverage:

```dart
test('an asset change names the shaders it recompiled', () {
  var sent = AssetsChanged(fontsChanged: false, shaders: ['shaders/glow.frag']);
  var back = DaemonResponse.fromJson(jsonDecode(jsonEncode(sent.toJson())) as Map<String, dynamic>) as AssetsChanged;
  expect(back.shaders, ['shaders/glow.frag']);
});

test('an asset change from an older daemon names none', () {
  // the JSON an older daemon sends: no 'shaders' key
  ...
  expect(back.shaders, isEmpty);
});
```

Match the decode entry point the protocol file actually uses.

- [ ] **Step 2: Run to see it fail**

Run: `cd app && fvm flutter test <the protocol test file>`
Expected: FAIL — no `shaders` parameter.

- [ ] **Step 3: Implement**

1. `AssetsChanged` gains `shaders` (encode as a list; decode `switch (json['shaders']) { List l => [for (var s in l) if (s is String) s], _ => const [] }`).
2. `_CompilerDaemon._refreshAssets`: `AssetsChanged(fontsChanged: sync.fontsChanged, shaders: [...sync.shaders])`.
3. `CatalogSession._onAssetsChanged`:
   ```dart
   void _onAssetsChanged(AssetsChanged change) {
     var vm = _vmService;
     if (vm == null) return;
     _fireAndForget(() async {
       // A program is cached by key for the life of the isolate, so new bytes
       // on disk are invisible until the engine is told to read them again —
       // what `flutter run`'s `r` does for a `shaders:` entry. It swaps the
       // program under every live FragmentShader and zeroes their uniforms;
       // the reassemble below is what makes a painter set them again.
       for (var key in change.shaders) {
         await vm.service.callServiceExtension(
           'ext.ui.window.reinitializeShader',
           isolateId: vm.isolateId,
           args: {'assetKey': key},
         );
       }
       await vm.service.callServiceExtension(
         'ext.flutter.evict',
         isolateId: vm.isolateId,
         args: {'value': 'AssetManifest.bin'},
       );
       await vm.service.callServiceExtension(
         'ext.flutter.reassemble',
         isolateId: vm.isolateId,
       );
     }(), 'refresh assets');
   }
   ```
   One failing key must not stop the evict and reassemble: wrap each `reinitializeShader` call in its own try/catch that logs through the same logger `_fireAndForget` uses.

- [ ] **Step 4: Extend the integration test**

Read `app/integration_test/asset_refresh_test.dart` (tagged `gpu`, run locally, not in CI). Add a case in its shape: the guest paints a rect with a project shader whose colour is a constant in the source; edit the constant; drive the refresh the way the image-edit case does; assert the guest's next frame shows the new colour **and the guest was not restarted** (same isolate / pid, whichever the file already checks). If the file's harness cannot host a shader-painting guest without disproportionate new scaffolding, write down why in the report instead, and Task 11 verifies the reload by driving the studio.

- [ ] **Step 5: Run**

Run: `cd app && fvm flutter test <the protocol test file>` — PASS.
Run: `cd app && fvm dart test integration_test/asset_refresh_test.dart` — PASS (needs a GPU; report the output).

- [ ] **Step 6: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/previews/ app/tool/catalog/compiler_daemon.dart app/test app/integration_test
git commit -m "Previews: reload an edited shader in live guests with reinitializeShader

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `ShaderPaint` — the value, its wire and its spelling

**Files:**
- Modify: `lib/src/scene/core/values.dart`, `app/lib/src/scene/paint_grammar.dart`, `app/lib/src/scene/gradient_edit.dart`, `app/lib/src/scene/ui/paint_field.dart`, `app/lib/src/scene/ui/layer_list.dart`, `lib/src/scene/layered_text.dart`
- Test: `app/test/scene/scene_paint_test.dart`, `app/test/scene/scene_props_test.dart`, `app/test/scene/scene_gradient_edit_test.dart`, `app/test/scene/scene_layer_list_test.dart`, the scene file grammar tests (`app/test/scene/scene_file_test.dart`)

**Interfaces:**
- Produces:
  ```dart
  class ShaderPaint extends ScenePaint {
    const ShaderPaint(this.asset, {this.uniforms = const {}});
    final String asset;                          // the bundle key: 'shaders/foil.frag'
    final Map<String, List<double>> uniforms;    // one to four floats each
    static const rendererUniforms = {'uSize': 2, 'uColor': 4, 'uTime': 1};
  }
  // wire: {'k': 'shader', 'asset': asset, 'u': {name: [floats]}}  ('u' omitted when empty)
  // file: ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': 0.4, 'uTint': [1, 0.8, 0.2]})
  enum ScenePaintKind { text, solid, linear, radial, sweep, shader('Shader') }
  ```

- [ ] **Step 1: Write the failing tests**

In `scene_paint_test.dart`:

```dart
group('shader paint', () {
  const foil = ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': [0.4], 'uTint': [1, 0.8, 0.2]});

  test('survives the wire', () {
    expect(ScenePaint.fromWire(foil.toWire()), foil);
    expect(foil.toWire(), {'k': 'shader', 'asset': 'shaders/foil.frag', 'u': {'uAngle': [0.4], 'uTint': [1, 0.8, 0.2]}});
    expect(const ShaderPaint('a.frag').toWire(), {'k': 'shader', 'asset': 'a.frag'});
  });

  test('is a value: equal uniforms are equal paints', () {
    expect(ShaderPaint('a.frag', uniforms: {'u': [1.0]}), ShaderPaint('a.frag', uniforms: {'u': [1.0]}));
    expect(ShaderPaint('a.frag', uniforms: {'u': [1.0]}).hashCode, ShaderPaint('a.frag', uniforms: {'u': [1.0]}).hashCode);
    expect(ShaderPaint('a.frag', uniforms: {'u': [1.0]}), isNot(ShaderPaint('a.frag', uniforms: {'u': [2.0]})));
  });

  test('a wire with no asset is no paint', () {
    expect(ScenePaint.fromWire({'k': 'shader'}), isNull);
    expect(ScenePaint.fromWire({'k': 'shader', 'asset': 3}), isNull);
  });

  test('a bad uniform is skipped, the rest kept', () {
    var read = ScenePaint.fromWire({'k': 'shader', 'asset': 'a.frag', 'u': {'good': [1, 2], 'bare': 3, 'long': [1, 2, 3, 4, 5], 'words': ['x'], 4: [1]}});
    expect(read, const ShaderPaint('a.frag', uniforms: {'good': [1, 2], 'bare': [3]}));
  });
});
```

In `scene_props_test.dart`'s `sample()`, add one layer to the `layers` list (this feeds the wire, authored-JSON and file round-trips for free):

```dart
FillLayer(
  paint: ShaderPaint(
    'shaders/foil.frag',
    uniforms: {'uAngle': [0.4], 'uTint': [1, 0.8, 0.2]},
  ),
  box: SceneLayerBox.line,
),
```

In the scene-file grammar tests, refusals (use that file's existing refusal-assertion helper):
- `ShaderPaint(asset)` (not a string literal) → refused, message mentions `ShaderPaint('shaders/foil.frag')`.
- `ShaderPaint('a.frag', uniforms: {'u': [1]})` (a one-element list) → refused: a float is spelled bare.
- `ShaderPaint('a.frag', uniforms: {'u': [1, 2, 3, 4, 5]})` → refused.
- `ShaderPaint('a.frag', uniforms: {u: 1})` (unquoted key) → refused.
- `ShaderPaint('a.frag', tint: 1)` → refused by name (`ShaderPaint has no "tint"`).

In `scene_gradient_edit_test.dart`:

```dart
test('a shader converts like no paint: into the text colour, out of nothing kept', () {
  expect(ScenePaintKind.of(const ShaderPaint('a.frag')), ScenePaintKind.shader);
  expect(convertPaint(const ShaderPaint('a.frag'), ScenePaintKind.solid, own: _blue), const SolidPaint(_blue));
  expect(convertPaint(const SolidPaint(_red), ScenePaintKind.shader, own: _blue), const ShaderPaint(''));
});
```

In `scene_layer_list_test.dart`: a shader layer with `box: SceneLayerBox.line` shows the "Laid across" picker, and an edit through its paint field keeps `box: line`.

- [ ] **Step 2: Run to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart test/scene/scene_props_test.dart test/scene/scene_gradient_edit_test.dart test/scene/scene_layer_list_test.dart test/scene/scene_file_test.dart`
Expected: FAIL — `ShaderPaint` undefined.

- [ ] **Step 3: The value** (`values.dart`, after the gradients)

```dart
/// A pass painted by one of the project's own fragment shaders.
///
/// [asset] is the shader's key in the bundle — the path its pubspec declares
/// under `flutter: shaders:`, and what `FragmentProgram.fromAsset` takes.
/// [uniforms] are the author's values by name, one to four floats each (a
/// float, a vec2, a vec3, a vec4). The renderer sets [rendererUniforms]
/// itself, and a name the shader does not declare is skipped, never thrown.
class ShaderPaint extends ScenePaint {
  const ShaderPaint(this.asset, {this.uniforms = const {}});

  final String asset;
  final Map<String, List<double>> uniforms;

  /// What the renderer sets, by name and float count, when the shader
  /// declares it at that size: the box's logical size (the whole text, or
  /// one line), the text's own colour as straight RGBA 0–1, and scene
  /// seconds. A shader that does not declare one simply does not get it.
  static const rendererUniforms = {'uSize': 2, 'uColor': 4, 'uTime': 1};

  @override
  Object toWire() => {
    'k': 'shader',
    'asset': asset,
    if (uniforms.isNotEmpty)
      'u': {for (var e in uniforms.entries) e.key: [...e.value]},
  };

  @override
  bool operator ==(Object other) =>
      other is ShaderPaint &&
      other.asset == asset &&
      _sameUniforms(other.uniforms, uniforms);

  @override
  int get hashCode => Object.hash(
    asset,
    Object.hashAllUnordered([
      for (var e in uniforms.entries) Object.hash(e.key, Object.hashAll(e.value)),
    ]),
  );

  @override
  String toString() => 'ShaderPaint($asset, $uniforms)';
}

bool _sameUniforms(Map<String, List<double>> a, Map<String, List<double>> b) {
  if (a.length != b.length) return false;
  for (var e in a.entries) {
    if (!_sameList(e.value, b[e.key])) return false;
  }
  return true;
}
```

The `fromWire` arm, before `_ => null`:

```dart
Map m when m['k'] == 'shader' => switch (m['asset']) {
  String asset => ShaderPaint(asset, uniforms: _wireUniforms(m['u'])),
  _ => null,
},
```

```dart
// A uniform that is not one to four numbers is SKIPPED, like a bad colour:
// the rest of the shader's values still reach it.
Map<String, List<double>> _wireUniforms(Object? raw) => switch (raw) {
  Map u => {
    for (var MapEntry(:key, :value) in u.entries)
      if (key is String)
        if (_wireFloats(value) case var floats?) key: floats,
  },
  _ => const {},
};

List<double>? _wireFloats(Object? raw) => switch (raw) {
  num n => [n.toDouble()],
  List l when l.isNotEmpty && l.length <= 4 && l.every((x) => x is num) => [
    for (var x in l) (x as num).toDouble(),
  ],
  _ => null,
};
```

Update the `ScenePaint` doc comment's second sentence to mention a shader beside the gradients.

- [ ] **Step 4: The spelling** (`paint_grammar.dart`)

Emit arm in `_paint`:

```dart
ShaderPaint(:var asset, :var uniforms) => [
  'ShaderPaint(${_string(asset)}',
  if (uniforms.isNotEmpty)
    ', uniforms: {${[for (var e in uniforms.entries) '${_string(e.key)}: ${_floats(e.value)}'].join(', ')}}',
  ')',
].join(),
```

```dart
// A float is spelled bare and a vector as a list — the shape the shader
// declares it in.
String _floats(List<double> v) =>
    v.length == 1 ? _num(v.single) : '[${v.map(_num).join(', ')}]';

String _string(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
```

Read arm in `_readPaint`, before `default:`:

```dart
case ('ShaderPaint', var args):
  return _readShader(e, args, refuse);
```

```dart
ScenePaint? _readShader(Expression at, ArgumentList args, Refuse refuse) {
  var positional = [
    for (var a in args.arguments)
      if (a is! NamedArgument) a,
  ];
  if (positional.length != 1 || positional.single is! SimpleStringLiteral) {
    refuse(
      at.offset,
      'paint',
      "a shader paint names its asset first, as the pubspec declares it — "
          "ShaderPaint('shaders/foil.frag')",
    );
    return null;
  }
  var asset = (positional.single as SimpleStringLiteral).value;
  var named = <String, Expression>{
    for (var a in args.arguments)
      if (a is NamedArgument) a.name.lexeme: a.argumentExpression,
  };
  var uniforms = const <String, List<double>>{};
  if (named.remove('uniforms') case var u?) {
    var read = _readUniforms(u, refuse);
    if (read == null) return null;
    uniforms = read;
  }
  if (!_rest(named, 'ShaderPaint', refuse)) return null;
  return ShaderPaint(asset, uniforms: uniforms);
}

Map<String, List<double>>? _readUniforms(Expression e, Refuse refuse) {
  if (e is! SetOrMapLiteral) {
    refuse(
      e.offset,
      'uniforms',
      "a map of uniform names to values — {'uAngle': 0.4, 'uTint': [1, 0.8, 0.2]}",
    );
    return null;
  }
  var out = <String, List<double>>{};
  for (var entry in e.elements) {
    if (entry is! MapLiteralEntry || entry.key is! SimpleStringLiteral) {
      refuse(entry.offset, 'uniforms', "a uniform's name in quotes, like 'uAngle'");
      return null;
    }
    var name = (entry.key as SimpleStringLiteral).value;
    var value = _uniformValue(entry.value);
    if (value == null) {
      refuse(
        entry.value.offset,
        "uniform '$name'",
        'a number for a float, or a list of two to four numbers for a vec2, '
            'vec3 or vec4',
      );
      return null;
    }
    out[name] = value;
  }
  return out;
}

List<double>? _uniformValue(Expression e) {
  if (_number(e) case var v?) return [v];
  if (e is! ListLiteral || e.elements.length < 2 || e.elements.length > 4) {
    return null;
  }
  var out = <double>[];
  for (var x in e.elements) {
    if (x is! Expression) return null;
    var v = _number(x);
    if (v == null) return null;
    out.add(v);
  }
  return out;
}
```

The allowlist message in `default:` becomes: `'a paint is SolidPaint(SceneColor(0x…)); LinearPaint, RadialPaint or SweepPaint(colors: […]); or ShaderPaint('shaders/….frag') — nothing else is on the allowlist'` (use double-quoted Dart for the inner single quotes, matching the file's style).

- [ ] **Step 5: Every other switch**

- `gradient_edit.dart`: add `shader('Shader')` (update "The five things" to "The six things"); `of`: `ShaderPaint() => shader`; in `convertPaint`, a `ShaderPaint` source converts like `null` (the text's own colour) and the `shader` target is `const ShaderPaint('')` — an empty asset the renderer paints as nothing, which the inspector (Task 10) replaces with a declared shader:
  ```dart
  var (List<SceneColor> colors, List<double>? stops) = switch (from) {
    SceneGradient g => (g.colors, g.stops),
    SolidPaint(:var color) => ([color, _clear(color)], null),
    ShaderPaint() || null => ([own, _clear(own)], null),
  };
  return switch (kind) {
    ...
    ScenePaintKind.shader => const ShaderPaint(''),
  };
  ```
- `paint_field.dart` build switch: `ShaderPaint() => const []` — Task 10 fills it.
- `layer_list.dart`: the paint-change ternary keeps `box` for `next is SceneGradient || next is ShaderPaint`; the "Laid across" picker shows for `layer.paint is SceneGradient || layer.paint is ShaderPaint`; the row notes gain `if (layer.paint case ShaderPaint()) 'shader'`; the chip's `color:` switch gets a `ShaderPaint()` arm and its `gradient:` gets a fixed three-colour sweep for a shader (so the chip reads "not a colour"; use colours from `context.colors`, not literals).
- `layered_text.dart` `_paintFor`: `case ShaderPaint(): paint.color = const Color(0x00000000);` with the comment "Never painted through the glyph paint — see `_paintShader` (Task 6); transparent until then." (Task 6 routes every shader pass away before `_paintFor` is reached in non-mask mode.)
- Grep `SolidPaint()` and `case SceneGradient` across `lib/` and `app/lib/` once more for any switch this list missed.

- [ ] **Step 6: Run the tests**

Run: `cd app && fvm flutter test test/scene` then `fvm flutter analyze`
Expected: PASS, no analyzer issues.

- [ ] **Step 7: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test/scene
git commit -m "Scene: a shader paint for text layers, on the wire and in the file

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The program cache and the per-slot shader pool

**Files:**
- Create: `lib/src/scene/shader_programs.dart`, `app/test/scene/shaders/probe.frag`, `app/test/scene/shaders/probe_bare.frag`
- Modify: `lib/scene.dart`, `app/pubspec.yaml`
- Test: `app/test/scene/scene_shader_programs_test.dart`

**Interfaces:**
- Consumes: `ShaderPaint` (Task 4); `RealWork.run` (`lib/src/real_work/tracker.dart`); `SceneDocument.walk()`, `TextNode.layers` (existing).
- Produces:
  ```dart
  typedef SceneProgramLoader = Future<ui.FragmentProgram> Function(String asset);

  class SceneShaderPrograms extends ChangeNotifier {
    SceneShaderPrograms({SceneProgramLoader? loader});    // tests pass a loader
    static final instance = SceneShaderPrograms();
    ui.FragmentProgram? program(String asset);             // loaded, or null (starts the load)
    Future<void> load(String asset);                        // completes when landed or failed; never throws
    Iterable<String> get pending;                           // assets in flight
    Object? errorFor(String asset);
    Future<List<String>> settle({required Duration timeout}); // what is still pending after [timeout]
    void reportSkipped(String asset, String uniform, int floats); // once per asset+name
    @visibleForTesting void reset();
  }

  class SceneShaderSlots {
    SceneShaderSlot slot(ui.FragmentProgram program, String asset, int pass, int line);
    void clear();     // on reassemble: forget, do not dispose
    void dispose();
  }

  class SceneShaderSlot {
    ui.FragmentShader get shader;
    /// Sets the renderer's uniforms the shader declares, then the author's;
    /// returns the author's names that were skipped.
    List<String> setUniforms(ShaderPaint paint, {required ui.Size size, required ui.Color color, required double seconds});
  }

  Set<String> sceneShaderAssets(SceneDocument scene);   // every non-empty ShaderPaint asset on a text node
  Future<void> precacheSceneShaders(SceneDocument scene); // public
  ```

Why a slot per (pass, line): the vector capture keeps each draw's live shader object and replays it later, so a shader shared across draws would replay every draw with the last uniforms set; per-line bands set a different `uSize` within one pass. Slots are reused across frames. A slot whose program changed is replaced.

Why `RealWork.run`, not `track`: the cache outlives any one scenario, and a load started inside a scenario's FakeAsync zone would never complete for the next one (see `tracker.dart`'s own comment on memoized loads).

- [ ] **Step 1: The test shaders**

`app/test/scene/shaders/probe.frag`:

```glsl
#version 460 core
// A shader whose output names the uniform under test, so a pixel test can
// read a uniform back as a colour. uMode picks what is shown.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uColor;
uniform float uTime;
uniform vec3 uTint;
uniform float uMode;

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  if (uMode < 0.5) {
    fragColor = vec4(uTint, 1.0);                         // 0: the author's tint
  } else if (uMode < 1.5) {
    fragColor = vec4(fract(uTime), 0.0, 0.0, 1.0);        // 1: scene seconds
  } else if (uMode < 2.5) {
    fragColor = vec4(clamp(p.x, 0.0, 1.0), 0.0, 0.0, 1.0); // 2: where x sits in the box
  } else {
    fragColor = vec4(uColor.rgb, 1.0);                    // 3: the text's own colour
  }
}
```

`app/test/scene/shaders/probe_bare.frag` — declares `uSize` at the wrong size and nothing else of the renderer's:

```glsl
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform float uSize;
uniform vec3 uTint;

out vec4 fragColor;

void main() {
  fragColor = vec4(uTint * clamp(uSize, 1.0, 1.0), 1.0);
}
```

In `app/pubspec.yaml` under `flutter:`:

```yaml
  # The scene tests' own shaders: `flutter test` compiles what the package
  # declares, and nothing else can put a program in a test's bundle.
  shaders:
    - test/scene/shaders/probe.frag
    - test/scene/shaders/probe_bare.frag
```

- [ ] **Step 2: Write the failing tests**

`app/test/scene/scene_shader_programs_test.dart` — plain `test()`s with `TestWidgetsFlutterBinding.ensureInitialized()` (real async; `FragmentProgram.fromAsset` never completes under `testWidgets`' FakeAsync without `runAsync`):

```dart
const probe = 'test/scene/shaders/probe.frag';
const bare = 'test/scene/shaders/probe_bare.frag';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('programs', () {
    late SceneShaderPrograms programs;
    setUp(() => programs = SceneShaderPrograms());

    test('a program is null until its load lands, and listeners hear it land', () async {
      var heard = 0;
      programs.addListener(() => heard++);
      expect(programs.program(probe), isNull);
      expect(programs.pending, [probe]);
      await programs.load(probe);
      expect(programs.program(probe), isNotNull);
      expect(programs.pending, isEmpty);
      expect(heard, 1);
    });

    test('a load in flight is real work a harness waits for', () async {
      var before = RealWork.pending;
      programs.program(probe);
      expect(RealWork.pending, before + 1);
      await programs.load(probe);
      expect(RealWork.pending, before);
    });

    test('a missing asset stays null, says why, and is not asked for again', () async {
      await programs.load('no/such.frag');
      expect(programs.program('no/such.frag'), isNull);
      expect(programs.errorFor('no/such.frag'), isNotNull);
      expect(programs.pending, isEmpty);
    });

    test('settle names what is still loading when time runs out', () async {
      var gate = Completer<ui.FragmentProgram>();
      var slow = SceneShaderPrograms(loader: (_) => gate.future);
      slow.program('slow.frag');
      expect(await slow.settle(timeout: const Duration(milliseconds: 20)), ['slow.frag']);
      gate.complete(await ui.FragmentProgram.fromAsset(probe));
      expect(await slow.settle(timeout: const Duration(seconds: 1)), isEmpty);
    });
  });

  group('slots', () {
    late ui.FragmentProgram program;
    setUpAll(() async => program = await ui.FragmentProgram.fromAsset(probe));

    test('one slot per pass and line, the same one frame after frame', () {
      var slots = SceneShaderSlots();
      var a = slots.slot(program, probe, 0, 0);
      expect(slots.slot(program, probe, 0, 0), same(a));
      expect(slots.slot(program, probe, 0, 1).shader, isNot(same(a.shader)));
      expect(slots.slot(program, probe, 1, 0).shader, isNot(same(a.shader)));
      slots.dispose();
    });

    test('a slot whose program changed is a new shader', () async {
      var slots = SceneShaderSlots();
      var a = slots.slot(program, probe, 0, 0);
      var other = await ui.FragmentProgram.fromAsset(bare);
      expect(slots.slot(other, bare, 0, 0).shader, isNot(same(a.shader)));
      slots.dispose();
    });

    test('an undeclared uniform, or one of the wrong size, is skipped', () {
      var slots = SceneShaderSlots();
      var skipped = slots.slot(program, probe, 0, 0).setUniforms(
        const ShaderPaint(probe, uniforms: {'uTint': [1, 0, 0], 'uMissing': [1], 'uMode': [1, 2]}),
        size: const ui.Size(10, 10),
        color: const ui.Color(0xFF000000),
        seconds: 0,
      );
      expect(skipped, unorderedEquals(['uMissing', 'uMode']));
      slots.dispose();
    });

    test("a renderer uniform declared at another size is left alone", () async {
      var slots = SceneShaderSlots();
      var other = await ui.FragmentProgram.fromAsset(bare);
      expect(
        () => slots.slot(other, bare, 0, 0).setUniforms(
          const ShaderPaint(bare, uniforms: {'uTint': [0, 1, 0]}),
          size: const ui.Size(10, 10),
          color: const ui.Color(0xFF000000),
          seconds: 1,
        ),
        returnsNormally,
      );
      slots.dispose();
    });

    test('an author value for a renderer uniform loses to the renderer', () {
      var slots = SceneShaderSlots();
      var skipped = slots.slot(program, probe, 0, 0).setUniforms(
        const ShaderPaint(probe, uniforms: {'uTime': [9]}),
        size: const ui.Size(10, 10),
        color: const ui.Color(0xFF000000),
        seconds: 0,
      );
      expect(skipped, isEmpty); // not an error — just not the author's to set
      slots.dispose();
    });
  });

  test('precache loads every shader a scene paints with', () async {
    // A SceneDocument whose root holds a TextNode with
    // layers: [FillLayer(paint: ShaderPaint(probe))] — build it the way the
    // other scene tests build a document.
    await precacheSceneShaders(doc);
    expect(SceneShaderPrograms.instance.program(probe), isNotNull);
    expect(sceneShaderAssets(doc), {probe});
  });
}
```

- [ ] **Step 3: Run to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_shader_programs_test.dart`
Expected: FAIL — `SceneShaderPrograms` undefined.

- [ ] **Step 4: Implement `shader_programs.dart`**

```dart
// A project's fragment programs, loaded once per process, and the shaders a
// text pass draws them with.
//
// A program paints nothing until it has loaded: a blank pass is an honest
// "not yet", where a stand-in colour is a wrong frame that looks right. Every
// load is real work (`RealWork`), so each flutter_tester lane waits for it
// with no plumbing of its own; a plain `flutter test` has no such wait, and
// awaits [precacheSceneShaders] instead.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../real_work/tracker.dart';
import 'core/model.dart';
import 'core/values.dart';

typedef SceneProgramLoader = Future<ui.FragmentProgram> Function(String asset);

class SceneShaderPrograms extends ChangeNotifier {
  SceneShaderPrograms({SceneProgramLoader? loader})
    : _loader = loader ?? ui.FragmentProgram.fromAsset;

  static final instance = SceneShaderPrograms();

  final SceneProgramLoader _loader;
  final _loaded = <String, ui.FragmentProgram>{};
  final _failed = <String, Object>{};
  final _loading = <String, Future<void>>{};
  final _reported = <String>{};

  ui.FragmentProgram? program(String asset) {
    if (_loaded[asset] case var p?) return p;
    unawaited(load(asset));
    return null;
  }

  Future<void> load(String asset) {
    if (_loaded.containsKey(asset) || _failed.containsKey(asset)) {
      return Future.value();
    }
    return _loading[asset] ??= RealWork.run(
      () => _loader(asset),
      label: 'shader $asset',
    ).then<void>(
      (program) => _loaded[asset] = program,
      onError: (Object error, StackTrace _) {
        _failed[asset] = error;
        debugPrint('flutterware: shader $asset did not load — $error');
      },
    ).whenComplete(() {
      _loading.remove(asset);
      notifyListeners();
    });
  }

  Iterable<String> get pending => _loading.keys;

  Object? errorFor(String asset) => _failed[asset];

  Future<List<String>> settle({required Duration timeout}) async {
    var deadline = DateTime.now().add(timeout);
    while (_loading.isNotEmpty) {
      var left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) break;
      try {
        await Future.wait(_loading.values.toList()).timeout(left);
      } on TimeoutException {
        break;
      }
    }
    return _loading.keys.toList();
  }

  void reportSkipped(String asset, String uniform, int floats) {
    if (!_reported.add('$asset $uniform')) return;
    debugPrint(
      'flutterware: $asset has no uniform "$uniform" of $floats '
      'float${floats == 1 ? '' : 's'} — its value is skipped',
    );
  }

  @visibleForTesting
  void reset() {
    _loaded.clear();
    _failed.clear();
    _loading.clear();
    _reported.clear();
  }
}
```

Check `RealWork.run`'s exact signature in `tracker.dart` and whether the returned future's error must be observed there; the `.then(onError:)` above observes it.

Slots:

```dart
class SceneShaderSlots {
  final _slots = <(int, int), SceneShaderSlot>{};

  SceneShaderSlot slot(ui.FragmentProgram program, String asset, int pass, int line) {
    var existing = _slots[(pass, line)];
    if (existing != null && identical(existing._program, program)) return existing;
    return _slots[(pass, line)] = SceneShaderSlot._(program, asset);
  }

  /// After a reassemble — which follows a shader reload — every cached
  /// uniform handle may point at a slot the reload dropped. Forgotten, not
  /// disposed: a capture taken before may still hold the shaders.
  void clear() => _slots.clear();

  void dispose() {
    for (var s in _slots.values) {
      s.shader.dispose();
    }
    _slots.clear();
  }
}

class SceneShaderSlot {
  SceneShaderSlot._(this._program, this._asset) : shader = _program.fragmentShader();

  final ui.FragmentProgram _program;
  final String _asset;
  final ui.FragmentShader shader;

  // Null: not declared, or declared at another size. Asked once per name.
  final _handles = <(String, int), void Function(List<double>)?>{};

  List<String> setUniforms(
    ShaderPaint paint, {
    required ui.Size size,
    required ui.Color color,
    required double seconds,
  }) {
    _set('uSize', [size.width, size.height]);
    _set('uColor', [color.r, color.g, color.b, color.a]);
    _set('uTime', [seconds]);
    var skipped = <String>[];
    for (var MapEntry(:key, :value) in paint.uniforms.entries) {
      if (ShaderPaint.rendererUniforms.containsKey(key)) continue;
      if (!_set(key, value)) {
        skipped.add(key);
        SceneShaderPrograms.instance.reportSkipped(_asset, key, value.length);
      }
    }
    return skipped;
  }

  bool _set(String name, List<double> v) {
    var set = _handles.putIfAbsent((name, v.length), () => _handle(name, v.length));
    set?.call(v);
    return set != null;
  }

  void Function(List<double>)? _handle(String name, int floats) {
    try {
      switch (floats) {
        case 1:
          var slot = shader.getUniformFloat(name);
          // getUniformFloat checks the name, not the size: a vec2 answers at
          // index 0. Index 1 existing means it is wider than a float.
          try {
            shader.getUniformFloat(name, 1);
            return null;
          } on ArgumentError {
            return (v) => slot.set(v[0]);
          }
        case 2:
          var slot = shader.getUniformVec2(name);
          return (v) => slot.set(v[0], v[1]);
        case 3:
          var slot = shader.getUniformVec3(name);
          return (v) => slot.set(v[0], v[1], v[2]);
        case 4:
          var slot = shader.getUniformVec4(name);
          return (v) => slot.set(v[0], v[1], v[2], v[3]);
      }
    } on ArgumentError {
      return null;
    }
    return null;
  }
}
```

Scene helpers:

```dart
/// Every shader a scene's text paints with.
Set<String> sceneShaderAssets(SceneDocument scene) => {
  for (var (node, _) in scene.walk())
    if (node is TextNode)
      for (var layer in node.layers)
        if (layer.paint case ShaderPaint(:var asset) when asset.isNotEmpty) asset,
};

/// Loads every fragment program [scene] paints with.
///
/// A flutterware lane waits for these loads by itself. A plain `flutter
/// test` does not — `pumpAndSettle` never asks — so a test that pumps a scene
/// with a shader pass awaits this first, or the pass is blank.
Future<void> precacheSceneShaders(SceneDocument scene) => Future.wait([
  for (var asset in sceneShaderAssets(scene)) SceneShaderPrograms.instance.load(asset),
]);
```

Check how `TextNode` exposes its composed layers (`view.dart` reads `t.layers`) and use the same accessor. Export from `lib/scene.dart`: `export 'src/scene/shader_programs.dart' show precacheSceneShaders;`.

- [ ] **Step 5: Run the tests**

Run: `cd app && fvm flutter test test/scene/scene_shader_programs_test.dart`
Expected: PASS. If `getUniformFloat(name, 1)` on a float throws something that is not an `ArgumentError`, widen that one catch to what it throws and say so in the report.

- [ ] **Step 6: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene/shader_programs.dart lib/scene.dart app/pubspec.yaml app/test/scene
git commit -m "Scene: load shader programs once, tracked as real work, with a shader per draw slot

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The stack painter paints a shader pass

**Files:**
- Modify: `lib/src/scene/layered_text.dart`, `.github/workflows/analyze-and-test.yaml`
- Test: `app/test/scene/scene_shader_paint_test.dart`, `app/test/scene/scene_shader_capture_test.dart`, `app/test/scene/scene_layered_text_test.dart`

**Interfaces:**
- Consumes: `SceneShaderPrograms`, `SceneShaderSlots`, `SceneShaderSlot.setUniforms` (Task 5); `ShaderPaint` (Task 4).
- Produces:
  ```dart
  class LayeredText extends StatefulWidget {
    const LayeredText({super.key, required this.span, required this.style, required this.layers,
      required this.textAlign, required this.maxLines, this.time});
    /// Scene time for a shader pass's uTime. Listened to only when the stack
    /// holds a shader pass; null is zero.
    final ValueListenable<Duration>? time;
  }
  SceneTextStackPainter({..., this.time, SceneShaderSlots? slots});
  @visibleForTesting Listenable? get repaintsOn;   // on SceneTextStackPainter
  ```

The shape (spec decisions 3–5):
- Every shader pass takes the mask path, `box: text` included: glyph coverage in opaque black (the same coverage key a per-line gradient uses, so a uniform change never relayouts) inside a `saveLayer` bounded by the pass's margin, whose paint carries the pass's blend **and its opacity**; the shader drawn over it with `srcIn`.
- `box: text` is one box — the painter's `Offset.zero & size` — and one draw over the whole margin-inflated rect. `box: line` is one box per line and one band per line, exactly the bands a per-line gradient draws (extract the band arithmetic from `_paintPerLine` into a helper both use).
- Before each draw: `canvas.save(); canvas.translate(box.left, box.top);` and the rect shifted by `-box.topLeft`, so `FlutterFragCoord()` runs over `[0, uSize]` whatever the pass's `dx`/`dy` or line.
- `uSize` is the box's size, `uColor` is `style.color` (the resolved text colour; black when null), `uTime` is `time?.value` in seconds (0 when null).
- No program (loading, failed, or an empty asset) → the pass draws nothing, not even its coverage layer.
- The painter's `repaint` listenable: `Listenable.merge([SceneShaderPrograms.instance, ?time])` when any layer's paint is a `ShaderPaint`, otherwise null. That is the whole of "text without a shader never repaints for time".
- `LayeredText` becomes stateful to own a `SceneShaderSlots`: created in `initState`, `clear()`ed in `reassemble()`, `dispose()`d in `dispose()`, handed to each painter. A painter built without slots (tests do) makes its own.
- `shouldRepaint` also compares `time` by identity.

- [ ] **Step 1: Write the failing pixel tests**

`app/test/scene/scene_shader_paint_test.dart`. Copy the `_paint` (build a bare `SceneTextStackPainter`, `paint` into a `PictureRecorder`, `toImage`) and `_mean` (mean RGBA of inked pixels in a region) helpers from `app/test/scene/scene_gradient_paint_test.dart`, extended so `_paint` takes `time` and `slots` and returns the painter too. Plain `test()`s with `TestWidgetsFlutterBinding.ensureInitialized()`; `setUpAll` awaits `SceneShaderPrograms.instance.load(probe)` and `load(bare)`.

```dart
const probe = 'test/scene/shaders/probe.frag';
const bare = 'test/scene/shaders/probe_bare.frag';

FillLayer shaderPass(double mode, {Map<String, List<double>> more = const {}, SceneLayerBox box = SceneLayerBox.text, double dx = 0, double opacity = 1}) =>
    FillLayer(paint: ShaderPaint(probe, uniforms: {'uMode': [mode], ...more}), box: box, dx: dx, opacity: opacity);

test("a shader pass paints the author's uniform", () async {
  var image = await _paint([shaderPass(0, more: {'uTint': [0, 1, 0]})]);
  var ink = await _mean(image);
  expect(ink.g, greaterThan(0.95));
  expect(ink.r, lessThan(0.05));
});

test("uColor is the text's own colour", () async {
  var image = await _paint([shaderPass(3)], color: const Color(0xFF0000FF));
  expect((await _mean(image)).b, greaterThan(0.95));
});

test('scene time changes the picture with no relayout', () async {
  var time = ValueNotifier(const Duration(milliseconds: 250));
  var (painter, first) = await _paintWith([shaderPass(1)], time: time);
  expect((await _mean(first)).r, closeTo(0.25, 0.02));
  time.value = const Duration(milliseconds: 750);
  var second = await _repaint(painter); // the SAME painter instance, painted again
  expect((await _mean(second)).r, closeTo(0.75, 0.02));
});

test('the box starts at zero wherever the pass is moved', () async {
  var image = await _paint([shaderPass(2, dx: 40)]);
  expect((await _mean(image, region: leftmostInkColumn)).r, lessThan(0.1));
  expect((await _mean(image, region: rightmostInkColumn)).r, greaterThan(0.9));
});

test('a line box restarts the shader on every line', () async {
  // two lines: a width that wraps the text once
  var image = await _paint([shaderPass(2, box: SceneLayerBox.line)], text: 'MMMM MMMM', width: 90);
  expect((await _mean(image, region: leftInkOfLine(0))).r, lessThan(0.1));
  expect((await _mean(image, region: leftInkOfLine(1))).r, lessThan(0.1));
});

test("the pass's opacity is the layer's", () async {
  // 0.6, not 0.5: the copied `_mean` counts a pixel as ink from alpha 128.
  var image = await _paint([shaderPass(0, more: {'uTint': [1, 1, 1]}, opacity: 0.6)]);
  expect((await _mean(image)).a, closeTo(0.6, 0.05));
});

test('nothing is painted until the program has loaded', () async {
  var programs = SceneShaderPrograms.instance..reset();
  var image = await _paint([shaderPass(0, more: {'uTint': [1, 1, 1]})]);
  expect(await _inkCount(image), 0);
  await programs.load(probe);
  var after = await _paint([shaderPass(0, more: {'uTint': [1, 1, 1]})]);
  expect(await _inkCount(after), greaterThan(0));
});

test('an undeclared uniform is skipped and reported once, never thrown', () async {
  var said = <String>[];
  var saved = debugPrint;
  debugPrint = (m, {wrapWidth}) => said.add(m ?? '');
  addTearDown(() => debugPrint = saved);
  await _paint([shaderPass(0, more: {'uTint': [1, 0, 0], 'uNope': [1]})]);
  await _paint([shaderPass(0, more: {'uTint': [1, 0, 0], 'uNope': [1]})]);
  expect(said.where((m) => m.contains('uNope')), hasLength(1));
});

test('a shader with none of the renderer uniforms still paints', () async {
  var image = await _paint([FillLayer(paint: ShaderPaint(bare, uniforms: {'uTint': [0, 0, 1]}))]);
  expect((await _mean(image)).b, greaterThan(0.95));
});
```

`_mean` returns channels 0–1; regions are helpers you write (the test font's glyphs are solid boxes, so "leftmost ink column" is the first x with alpha ≥ 0.5 on a middle row). Adjust tolerances only if a measured value is stable and off by rounding, and say so in the report.

In `scene_layered_text_test.dart`:

```dart
testWidgets('text with no shader pass never listens to time', (tester) async {
  var time = ValueNotifier(Duration.zero);
  await tester.pumpWidget(_mountWithTime([const FillLayer()], time));
  var painter = tester.widget<CustomPaint>(find.byType(CustomPaint)).foregroundPainter! as SceneTextStackPainter;
  expect(painter.repaintsOn, isNull);
});

testWidgets('a shader pass listens to time and to its program', (tester) async {
  ... // same, with a ShaderPaint layer
  expect(painter.repaintsOn, isNotNull);
});
```

- [ ] **Step 2: Write the failing capture test**

`app/test/scene/scene_shader_capture_test.dart`, in the shape of `test/render/scene_text_gradient_capture_test.dart` (mount under a `RepaintBoundary`, capture inside `tester.runAsync`; `precacheSceneShaders`/`load(probe)` inside `runAsync` first):

```dart
testWidgets("a two-line shader pass keeps each band's own shader", (tester) async {
  // LayeredText, two lines, [shaderPass(2, box: SceneLayerBox.line)]
  await tester.runAsync(() async {
    var recording = captureVector(boundary);
    var shaders = [
      for (var op in recording.ops)
        if (op is VgDrawRect /* whatever the rect op type is */ && op.paint.blendMode == BlendMode.srcIn)
          op.paint.source!.shader,
    ];
    expect(shaders, hasLength(2));
    expect(identical(shaders[0], shaders[1]), isFalse);
    var svg = await captureSvg(boundary);
    expect(svg, contains('<image')); // the layer went out as a raster patch
  });
});
```

Read `lib/src/render/model.dart` for the real op class names and the `VgPaint.source` field; the assertion is: two `srcIn` draws, two distinct shader objects, and an SVG that exports without throwing and carries the patch.

- [ ] **Step 3: Run to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_shader_paint_test.dart test/scene/scene_shader_capture_test.dart test/scene/scene_layered_text_test.dart`
Expected: FAIL.

- [ ] **Step 4: Implement**

In `SceneTextStackPainter`:

```dart
SceneTextStackPainter({
  ...,
  this.time,
  SceneShaderSlots? slots,
}) : _slots = slots ?? SceneShaderSlots(),
     super(repaint: _repaintFor(layers, time));

final ValueListenable<Duration>? time;
final SceneShaderSlots _slots;

/// Only a shader pass is drawn by the clock or waits on a load, so only a
/// stack holding one listens to either — text without one never repaints
/// for time.
static Listenable? _repaintFor(List<TextLayer> layers, ValueListenable<Duration>? time) =>
    layers.any((l) => l.paint is ShaderPaint)
        ? Listenable.merge([SceneShaderPrograms.instance, ?time])
        : null;

@visibleForTesting
Listenable? get repaintsOn => _repaintFor(layers, time);
```

(`repaintsOn` recomputes rather than exposing the private `_repaint` — enough for the test's null/non-null question.)

`paint` iterates with an index, and a shader pass goes first:

```dart
for (var pass = 0; pass < layers.length; pass++) {
  var layer = layers[pass];
  ...moved...
  if (layer.paint case ShaderPaint shader) {
    _paintShader(canvas, pass, layer, shader, size);
  } else if (_perLine(layer)) {
  ...
```

```dart
/// A pass painted by a fragment shader, always through a mask.
///
/// A paragraph freezes its foreground shader's uniforms when it is built
/// (measured on Skia and Impeller), so a shader handed to the glyph paint
/// would never see a new `uTime` without a relayout. So the glyphs go in as
/// coverage, the same as a per-line gradient's, and the shader is drawn over
/// them fresh on every paint. The box is placed by the transform — the
/// canvas moves to the box's corner and the rect is drawn from zero — so
/// `FlutterFragCoord()` runs over `[0, uSize]` wherever the pass sits.
void _paintShader(Canvas canvas, int pass, TextLayer layer, ShaderPaint paint, Size size) {
  var program = paint.asset.isEmpty
      ? null
      : SceneShaderPrograms.instance.program(paint.asset);
  if (program == null) return;
  var coverage = layer.withPaint(null).copyWith(opacity: 1, blend: SceneBlendMode.normal);
  var mask = _painterFor(coverage, size, mask: true);
  var margin = _spillMargin(layer);
  var whole = Offset.zero & size;
  canvas.saveLayer(
    whole.inflate(margin),
    Paint()
      ..blendMode = layer.blend.flutter
      ..color = Color.fromRGBO(0, 0, 0, layer.opacity),
  );
  mask.paint(canvas, Offset.zero);
  var boxes = layer.box == SceneLayerBox.line
      ? _lineBands(mask, size, margin)
      : [(box: whole, band: whole.inflate(margin))];
  var seconds = (time?.value ?? Duration.zero).inMicroseconds / Duration.microsecondsPerSecond;
  for (var line = 0; line < boxes.length; line++) {
    var (:box, :band) = boxes[line];
    var slot = _slots.slot(program, paint.asset, pass, line)
      ..setUniforms(paint, size: box.size, color: style.color ?? const Color(0xFF000000), seconds: seconds);
    canvas
      ..save()
      ..translate(box.left, box.top)
      ..drawRect(
        band.shift(-box.topLeft),
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = slot.shader,
      )
      ..restore();
  }
  canvas.restore();
}
```

`_lineBands(TextPainter mask, Size size, double margin) → List<({Rect box, Rect band})>` is the loop body of `_paintPerLine` lifted out — `box` is the line's `Rect.fromLTRB(line.left, top, line.left + line.width, bottom)`, `band` the `Rect.fromLTRB(-margin, bandTop, size.width + margin, bandBottom)` — and `_paintPerLine` then draws its gradient over each `band` with `sceneGradientShader(gradient, box, opacity: layer.opacity)`, unchanged in output. Keep `_paintPerLine`'s comments where they still describe it.

`shouldRepaint` adds `|| old.time != time`. `_paintFor`'s `ShaderPaint` arm comment now points at `_paintShader`.

`LayeredText` becomes a `StatefulWidget` (`_LayeredTextState`), its build unchanged apart from passing `time: widget.time, slots: _slots`. Update the class doc ("With no layers this is exactly the `Text.rich` it always was" still holds — no `CustomPaint`, no slots used).

- [ ] **Step 5: Run the tests on both engines**

Run: `cd app && fvm flutter test test/scene` — PASS (Skia).
Run: `cd app && fvm flutter test --enable-impeller test/scene/scene_shader_paint_test.dart test/scene/scene_shader_capture_test.dart` — PASS (Impeller). If Impeller disagrees on a tolerance, report both measured values.
Run: `fvm flutter test test/render` from the root — PASS (the gradient capture test still holds after the `_lineBands` extraction).

- [ ] **Step 6: CI runs the pixel test on Impeller too**

In `.github/workflows/analyze-and-test.yaml`'s macOS job, after the `app` `flutter test` step:

```yaml
      # The shader pixel tests again on Impeller: a paragraph freezing its
      # shader is engine behaviour, and the mask path has to hold on both.
      - run: flutter test --enable-impeller test/scene/scene_shader_paint_test.dart test/scene/scene_shader_capture_test.dart
        working-directory: app
```

- [ ] **Step 7: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene/layered_text.dart app/test .github/workflows/analyze-and-test.yaml
git commit -m "Scene: paint a shader text pass through a glyph mask, placed by the transform

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Scene time reaches the painter

**Files:**
- Modify: `lib/src/scene/core/motion_runtime.dart`, `lib/src/scene/flutter_bridge.dart`, `lib/src/scene/view.dart`, `lib/src/scene/host.dart`, `app/lib/src/scene/guest.dart` (and whichever file schedules its pushes during playback — see Step 4)
- Test: `app/test/scene/motion_runtime_test.dart`, `app/test/scene/scene_play_test.dart`

**Interfaces:**
- Consumes: `LayeredText.time` (Task 6); `sceneShaderAssets` (Task 5).
- Produces:
  ```dart
  // Playable (core)
  final clock = SceneValue<Duration>(Duration.zero);
  Duration get position => clock.value;
  // flutter_bridge.dart
  extension SceneValueToFlutter<T> on SceneValue<T> { ValueListenable<T> get flutter; }
  // SceneView (both constructors)
  final ValueListenable<Duration>? time;   // explicit scene time; null reads motion?.clock
  // ext.fw.scene.apply gains param 'time': seconds as a decimal string
  ```

- [ ] **Step 1: Write the failing tests**

`motion_runtime_test.dart`:

```dart
test('a playable remembers where it was last applied', () {
  // a bound motion, as the file's other tests build one
  var heard = 0;
  bound.clock.addListener(() => heard++);
  bound.apply(const Duration(milliseconds: 250));
  expect(bound.position, const Duration(milliseconds: 250));
  bound.apply(const Duration(milliseconds: 250));
  expect(heard, 1); // the same time again is not news
});

test("a child's clock is its own time, not the parent's", () {
  // an _At / delayed child through the public combinator the file already uses
  ...
  expect(child.position, parentTime - offset);
});
```

`scene_play_test.dart` (it already mounts `MotionPlayer` + `SceneView`):

```dart
testWidgets("a text's time is the motion's position", (tester) async {
  // scene with a TextNode whose layers hold a ShaderPaint, motion bound to it
  ...
  player.position = const Duration(milliseconds: 400);
  await tester.pump();
  var text = tester.widget<LayeredText>(find.byType(LayeredText));
  expect(text.time!.value, const Duration(milliseconds: 400));
});

testWidgets('an explicit time wins over the motion', (tester) async {
  var time = ValueNotifier(const Duration(seconds: 2));
  // SceneView.document(scene, motion: bound, time: time)
  ...
  expect(tester.widget<LayeredText>(find.byType(LayeredText)).time, same(time));
});

testWidgets('the time listenable is the same object across rebuilds', (tester) async {
  // rebuild the SceneView twice; LayeredText.time is identical both times,
  // so the painter does not re-subscribe or repaint for a rebuild
});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd app && fvm flutter test test/scene/motion_runtime_test.dart test/scene/scene_play_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the core and the view**

`Playable`:

```dart
/// Where this playable was last applied — scene time, for what is drawn by
/// the clock rather than by a track: a shader pass's `uTime`. Every [apply]
/// records it before it writes; one never applied is at zero. A child's is
/// its own local time.
final clock = SceneValue<Duration>(Duration.zero);

Duration get position => clock.value;
```

Every `apply` override in `motion_runtime.dart` (`BoundGroup`, `_Par`, `_Seq`, `_At`, `_Speed`, `_Repeat`, `BoundMotion`) starts with `clock.value = t;`. Grep for other `Playable` subclasses outside this file and do the same.

`flutter_bridge.dart`, beside `SceneListenableToFlutter`:

```dart
extension SceneValueToFlutter<T> on SceneValue<T> {
  /// This value as a Flutter [ValueListenable]. A fresh adapter per call:
  /// hold the one you listen to.
  ValueListenable<T> get flutter => _SceneValueAdapter(this);
}

class _SceneValueAdapter<T> extends ValueListenable<T> { ... } // forwards add/removeListener, value
```

Follow the existing `_SceneListenableAdapter`'s shape.

`SceneView`: `time` on both constructors, documented "Scene time for what the clock draws — a shader pass's `uTime`. Null reads the motion's; with neither it is zero." In `_SceneViewState`, hold `ValueListenable<Duration>? _time`, computed in `initState` and in `didUpdateWidget` when `time` or `motion` changed: `widget.time ?? widget.motion?.clock.flutter`. Pass `time: _time` to the `LayeredText` built for a `TextNode`.

`SceneCanvasHost` (`host.dart`): `final _time = ValueNotifier(Duration.zero);` disposed with the state; `_apply` reads `params['time']` → `double.tryParse` → `_time.value = Duration(microseconds: (seconds * 1e6).round())` (absent or unparsable: unchanged); `SceneView.document(..., time: _time)`.

- [ ] **Step 4: The studio sends the playhead**

`SceneGuest._push` (`app/lib/src/scene/guest.dart`) adds `'time': '${editor.playhead.inMicroseconds / Duration.microsecondsPerSecond}'` to the args.

A playing motion reaches the guest as composed documents, one per flush — so a motion that animates nothing but `uTime` would never push. Read how `SceneGuest` decides to push and how `ScenePlayback` (`app/lib/src/scene/playback.dart`) writes `editor.playhead`; add the smallest trigger that pushes on a playhead move **only when the document paints with a shader** (`sceneShaderAssets(editor.doc).isNotEmpty`, computed when the document changes, not per tick), coalesced the way other pushes are. Write down in the report where the trigger lives and why there.

If `SceneGuest` can be built in a test with a fake session cheaply, test that its push carries `time`; if not, say so in the report — Task 11 verifies it by driving the studio.

- [ ] **Step 5: Run the tests**

Run: `cd app && fvm flutter test test/scene` — PASS.
Run: `fvm flutter test` from the root — PASS.

- [ ] **Step 6: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test/scene
git commit -m "Scene: carry scene time from the playhead to a shader pass's clock

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: The scene editor waits for shader programs

**Files:**
- Modify: `lib/src/scene/host.dart`, `app/lib/src/scene/guest.dart`, `app/lib/src/plugins/native/scene_plugin.dart`
- Test: `app/test/scene/scene_shader_programs_test.dart` (settle already covered in Task 5), a `SceneGuest` busy test if Task 7 found a seam; otherwise covered by driving in Task 11

**Interfaces:**
- Consumes: `SceneShaderPrograms.settle`, `precacheSceneShaders` (Task 5).
- Produces: `ext.fw.scene.apply`'s reply gains `'pendingShaders': [assets still loading]`; `SceneGuest.busyWith` (`String?`); `ScenePlugin.busyWith` overrides `NativePlugin`'s default.

Three waits exist and each lane uses its own: `RealWork` for flutter_tester lanes (already covered by Task 5's loads), `SettleRegistry`/`waitForSettle` for the GUI's `fw capture`, and the editor canvas's own `_apply`. This task is the last two.

- [ ] **Step 1: `_apply` waits, bounded, and says what is left**

In `SceneCanvasHost._apply`, after the new document is decoded and before the forced frame:

```dart
// A shader pass paints nothing until its program loads, so a picture taken
// before is honest and wrong. Wait for the loads — bounded, a broken shader
// must not hang the editor — then draw.
try {
  await precacheSceneShaders(scene).timeout(const Duration(seconds: 2));
} on TimeoutException {
  // What is still loading is named in the reply.
}
```

and add to the reply map: `'pendingShaders': SceneShaderPrograms.instance.pending.toList()`.

- [ ] **Step 2: The studio is busy while a push is out or programs are pending**

`SceneGuest`:
- count pushes in flight (increment before `callGuestExtension`, decrement in `finally`);
- keep the last reply's `pendingShaders`;
- when that list is non-empty, schedule one re-push after 250ms (a timer cancelled by `dispose` and by any newer push);
- ```dart
  /// What the canvas is still waiting on, or null when what it shows is
  /// what the document says — read by the plugin's settle source.
  String? get busyWith => _inFlight > 0
      ? 'drawing the scene'
      : _pendingShaders.isEmpty
      ? null
      : 'loading ${_pendingShaders.join(', ')}';
  ```

`ScenePlugin`: `@override String? get busyWith => _guest?.busyWith;` — if the plugin already has other busy states worth reporting, combine them the way `PreviewsPlugin.busyWith` does.

- [ ] **Step 3: Test what can be tested without a guest**

If `SceneGuest` accepts a fake session (Task 7 found out), test: in-flight push → busy; reply with `pendingShaders: ['a.frag']` → busy with `'loading a.frag'` and a re-push after 250ms (use `fakeAsync`); reply with none → idle. Otherwise record that in the report.

- [ ] **Step 4: Run**

Run: `cd app && fvm flutter test test/scene` and `fvm flutter analyze` — PASS.

- [ ] **Step 5: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene/host.dart app/lib/src/scene/guest.dart app/lib/src/plugins/native/scene_plugin.dart app/test
git commit -m "Scene editor: wait for shader programs before the canvas answers or settles

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: The studio reads a shader's uniforms

**Files:**
- Create: `app/lib/src/scene/shader_library.dart`
- Test: `app/test/scene/scene_shader_library_test.dart`

**Interfaces:**
- Consumes: `compileProjectShader`, `projectShaderHash`, `CompiledShader` (Task 2); `ShaderPaint.rendererUniforms` (Task 4); `FlutterCache`.
- Produces:
  ```dart
  class SceneShaderUniform {
    const SceneShaderUniform({required this.name, required this.size, required this.location,
      this.range, this.isColor = false, this.defaults});
    final String name;
    final int size;                 // 1..4 floats
    final int location;             // declaration order
    final (double, double)? range;  // // @range a b
    final bool isColor;             // // @color (vec3 or vec4)
    final List<double>? defaults;   // // @default …, exactly [size] numbers
    bool get rendererOwned => ShaderPaint.rendererUniforms[name] == size;
  }
  class SceneShaderInfo {
    const SceneShaderInfo({required this.key, this.uniforms = const [], this.error});
    final String key;
    final List<SceneShaderUniform> uniforms;  // declaration order
    final String? error;                      // why the uniforms could not be read
    Map<String, List<double>> get defaults;   // every non-renderer uniform's @default
  }
  List<String> declaredShaders(String packageRoot);
  List<SceneShaderUniform> readShaderUniforms(String reflectionJson, String source);
  abstract interface class SceneShaders implements Listenable {
    List<String> get declared;
    SceneShaderInfo? info(String key);   // null while it is being read
  }
  class SceneShaderLibrary extends ChangeNotifier {
    SceneShaderLibrary({required FlutterCache? cache,
      @visibleForTesting Future<CompiledShader> Function(String source)? compile});
    SceneShaders forPackage(String packageRoot);
  }
  class FixedSceneShaders extends ChangeNotifier implements SceneShaders {
    FixedSceneShaders(this.infos);
    final Map<String, SceneShaderInfo> infos;
  }
  ```

Rules:
- `declaredShaders` reads `packageRoot/pubspec.yaml`'s `flutter: shaders:` (strings only, in order; unreadable or absent → `[]`). The root package's keys only — a dependency's shaders are not offered in v1.
- `readShaderUniforms`: parse the JSON's `uniforms` (malformed JSON or a missing array → `[]`, never a throw); keep entries whose `type.type_name == 'ShaderType::kFloat'`, `type.columns == 1` (or absent) and `1 <= type.vec_size <= 4`; sort by `location`. Then scan the source for annotations on each uniform's declaration line:
  - declaration: `^\s*uniform\s+(?:(?:lowp|mediump|highp)\s+)?(float|vec2|vec3|vec4)\s+(\w+)\s*;(.*)$`
  - in the tail after `//`: `@range <a> <b>` (two numbers), `@color` (only honoured for vec3/vec4), `@default <n…>` (honoured only when it gives exactly `size` numbers).
  - A tag that does not parse is ignored — the control degrades to a plain number field, never an error.
- `SceneShaderLibrary.forPackage(root).info(key)`: source is `p.join(root, key)`. Cached by `projectShaderHash(source)`: a hit returns at once; a miss (or a changed hash) starts one compile, returns null, and notifies when it lands. A compile failure → `SceneShaderInfo(key: key, error: <impellerc's message, first lines>)`. A missing source → `error: "'$key' is not on disk"`. `cache == null` → `error: 'no Flutter SDK to compile with'`. A non-empty `sampled_images` → the info carries its uniforms **and** `error: 'uses a sampler (<names>) — a scene cannot feed one yet'`.
- `declared` on the package view re-reads the pubspec when its mtime changed.

- [ ] **Step 1: Write the failing tests**

```dart
const reflection = '''
{"uniforms": [
  {"name": "uSize", "location": 0, "type": {"type_name": "ShaderType::kFloat", "vec_size": 2, "columns": 1}},
  {"name": "uAngle", "location": 3, "type": {"type_name": "ShaderType::kFloat", "vec_size": 1, "columns": 1}},
  {"name": "uTime", "location": 1, "type": {"type_name": "ShaderType::kFloat", "vec_size": 1, "columns": 1}},
  {"name": "uShine", "location": 2, "type": {"type_name": "ShaderType::kFloat", "vec_size": 3, "columns": 1}}
], "sampled_images": []}''';

const source = '''
uniform vec2 uSize;
uniform float uTime;
uniform vec3 uShine; // @color @default 1 0.85 0.4
uniform float uAngle; // @range 0 6.283 @default 0.6
''';

test('uniforms come in declaration order, with what the comments add', () {
  var u = readShaderUniforms(reflection, source);
  expect(u.map((x) => x.name), ['uSize', 'uTime', 'uShine', 'uAngle']);
  expect(u[2].isColor, isTrue);
  expect(u[2].defaults, [1, 0.85, 0.4]);
  expect(u[3].range, (0, 6.283));
  expect(u[3].defaults, [0.6]);
  expect(u[0].rendererOwned, isTrue);
  expect(u[3].rendererOwned, isFalse);
});

test('a tag that does not fit is ignored', () {
  var u = readShaderUniforms(reflection, 'uniform float uAngle; // @range zero six @default 1 2\nuniform vec2 uSize; // @color');
  var angle = u.firstWhere((x) => x.name == 'uAngle');
  expect(angle.range, isNull);
  expect(angle.defaults, isNull);
  expect(u.firstWhere((x) => x.name == 'uSize').isColor, isFalse);
});

test('unreadable reflection is no uniforms, not a throw', () {
  expect(readShaderUniforms('not json', source), isEmpty);
  expect(readShaderUniforms('{"uniforms": 3}', source), isEmpty);
});

test('the declared shaders are the pubspec's, in order', () {
  // temp package with flutter: shaders: [shaders/b.frag, shaders/a.frag]
  expect(declaredShaders(root.path), ['shaders/b.frag', 'shaders/a.frag']);
});

test('info is null while compiling, then lands and notifies', () async {
  var gate = Completer<CompiledShader>();
  var library = SceneShaderLibrary(cache: null, compile: (_) => gate.future);
  var shaders = library.forPackage(root.path);
  var heard = 0;
  shaders.addListener(() => heard++);
  expect(shaders.info('shaders/a.frag'), isNull);
  gate.complete(/* a CompiledShader whose reflection file holds `reflection` */);
  await pumpEventQueue();
  expect(shaders.info('shaders/a.frag')!.uniforms, hasLength(4));
  expect(heard, 1);
});

test("a shader that does not compile says why", () async { ... error non-null ... });

group('on the pinned SDK', () {
  // The reflection JSON is the compiler's output, not an API: this pins
  // that it still carries what the inspector reads.
  test("the probe shader's uniforms, from impellerc itself", () async {
    var cache = FlutterCache(p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache'));
    var compiled = await compileProjectShader(cache: cache, source: p.absolute('test/scene/shaders/probe.frag'));
    var u = readShaderUniforms(File(compiled.reflection).readAsStringSync(), File('test/scene/shaders/probe.frag').readAsStringSync());
    expect([for (var x in u) (x.name, x.size)], [('uSize', 2), ('uColor', 4), ('uTime', 1), ('uTint', 3), ('uMode', 1)]);
  }, timeout: const Timeout(Duration(minutes: 2)));
});
```

Use `flutterwareDirOverride` in the SDK group so the test never touches `~/.flutterware`.

- [ ] **Step 2: Run to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_shader_library_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement** per the rules above. Keep it one file; the pure parsers at the top, the library below.

- [ ] **Step 4: Run**

Run: `cd app && fvm flutter test test/scene/scene_shader_library_test.dart` — PASS.

- [ ] **Step 5: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/scene/shader_library.dart app/test/scene/scene_shader_library_test.dart
git commit -m "Scene editor: read a shader's uniforms from the compiler's reflection and its comments

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: The inspector edits a shader pass

**Files:**
- Create: `app/lib/src/scene/ui/shader_field.dart`
- Modify: `app/lib/src/scene/ui/paint_field.dart`, `app/lib/src/scene/ui/layer_list.dart`, `app/lib/src/scene/ui/inspector.dart`, `app/lib/src/scene/ui/workspace_view.dart`, `app/lib/src/plugins/native/scene_plugin.dart`, `app/tool/catalog/demos/scene_paint_field.dart` (and `app/lib/src/scene/ui/library_view.dart` if it mounts `SceneLayerList`)
- Test: `app/test/scene/scene_shader_field_test.dart`, `app/test/scene/scene_layer_list_test.dart`

**Interfaces:**
- Consumes: `SceneShaders`, `SceneShaderInfo`, `SceneShaderUniform`, `SceneShaderLibrary`, `FixedSceneShaders` (Task 9); `ShaderPaint` and the `layer_list` box rules (Task 4).
- Produces: `SceneShaderField({required ShaderPaint paint, required SceneShaders? shaders, required PaintChanged onChanged})`; a `SceneShaders? shaders` parameter on `ScenePaintField`, `SceneLayerList`, `SceneInspector`, `SceneWorkspaceView`.

The field, top to bottom:
1. **Asset** — `FwPicker<String>` keyed `ValueKey('paint:shader')`: one `FwChoice` per `shaders.declared` (label `p.basename`, detail the key). `empty:` `'No shaders under flutter: shaders: in pubspec.yaml.'`; with `shaders == null`, `'No package to look in.'`. A current asset not among them is prepended with detail `'not declared'`, and a red caption under the picker reads `"'<asset>' is not declared under flutter: shaders:"` (the `_pickRow` convention in `inspector.dart`: `context.type.caption.copyWith(color: context.colors.red)`). Picking writes `ShaderPaint(key, uniforms: shaders.info(key)?.defaults ?? const {})`, label `'Shader'`.
2. **Uniforms** — rebuilt on `shaders` (a `ListenableBuilder`). `info == null` → a muted caption `'Reading uniforms…'`. `info.error` → the error in a red caption, then a plain number field per component for each uniform already in the value. Otherwise one control per non-renderer uniform, in declaration order; the value is `paint.uniforms[name] ?? u.defaults ?? zeros(size)`:
   - float with `range` → `SceneNumberField(label: name, shape: SceneNumberShape(softMin: a, softMax: b, slider: true, perPixel: (b - a) / 200, decimals: 3), …)`;
   - float without → `SceneNumberField` with a scrub shape (`perPixel: 0.01, decimals: 3`);
   - `isColor` vec3/vec4 → the name as a caption plus `SceneColorField(current: <the floats as a SceneColor>, allowNone: false)`, writing back `[r, g, b]` or `[r, g, b, a]` rounded to three decimals;
   - any other vecN → N `SceneNumberField`s labelled `name.x`, `name.y`, `name.z`, `name.w`.
   Each edit: `onChanged(ShaderPaint(paint.asset, uniforms: {...paint.uniforms, name: next}), label: 'Shader uniform', mergeKey: 'shader:$name')` while dragging, and the same without `mergeKey` on commit — follow `paint_field.dart`'s `_number` helper for the exact drag/commit pairing.
3. **Strays** — a uniform in the value that the reflection does not list: a red caption `"$name is set, and ${p.basename(paint.asset)} declares no such uniform"`.

`ScenePaintField`:
- the `ShaderPaint` arm renders `SceneShaderField`;
- choosing **Shader** in the kind picker writes the first declared shader with its defaults when there is one, else `convertPaint`'s `ShaderPaint('')`.

Plumbing: `ScenePlugin` owns one `SceneShaderLibrary(cache: FlutterCache(p.join(host.workspace.flutterSdk.root, 'bin', 'cache')))`, disposed with the plugin, and passes `library.forPackage(_core.rootFor(_package!))` as `shaders:` where it builds `SceneWorkspaceView` (next to `packageRoot:`). Thread it `SceneWorkspaceView` → `SceneInspector` → `SceneLayerList` → `ScenePaintField`, the way `packageRoot` and `axesFor` already travel. A library view that mounts `SceneLayerList` without a package passes null.

- [ ] **Step 1: Write the failing widget tests**

`scene_shader_field_test.dart`, harness as in `scene_paint_field_test.dart` (`MaterialApp(theme: appTheme, …)`, a `StatefulBuilder` holding the paint, `onChanged` writing it back), with:

```dart
final shaders = FixedSceneShaders({
  'shaders/foil.frag': SceneShaderInfo(key: 'shaders/foil.frag', uniforms: [
    SceneShaderUniform(name: 'uSize', size: 2, location: 0),
    SceneShaderUniform(name: 'uAngle', size: 1, location: 1, range: (0, 6.283), defaults: [0.6]),
    SceneShaderUniform(name: 'uShine', size: 3, location: 2, isColor: true, defaults: [1, 0.85, 0.4]),
    SceneShaderUniform(name: 'uOffset', size: 2, location: 3),
  ]),
  'shaders/plain.frag': SceneShaderInfo(key: 'shaders/plain.frag'),
});
```

Tests:
1. `'choosing Shader takes the first declared shader, with its defaults'` — from `SolidPaint`, pick kind `'Shader'` → `ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': [0.6], 'uShine': [1, 0.85, 0.4]})`.
2. `"the renderer's uniforms are not offered"` — no control labelled `uSize`.
3. `'a ranged float is a slider'` — the `SceneNumberField` labelled `uAngle` has `shape.editor == SceneEditorShape.slider`; committing 1.5 writes `'uAngle': [1.5]` and keeps `uShine`.
4. `'a vec2 is one field per component'` — fields `uOffset.x`, `uOffset.y`; committing `uOffset.y` = 3 writes `[0, 3]`.
5. `'a colour uniform is a colour field'` — a `SceneColorField` is present; picking a swatch writes three floats in 0–1.
6. `'picking another shader starts from its defaults'` — pick `plain.frag` → `ShaderPaint('shaders/plain.frag')`.
7. `'an undeclared asset says so'` — paint `ShaderPaint('shaders/gone.frag')` → text containing `'is not declared'`.
8. `'a stray uniform says so'` — paint foil with `{'uNope': [1]}` → text containing `'declares no such uniform'`.
9. `'while it compiles, it says so'` — a `SceneShaders` whose `info` returns null → `'Reading uniforms…'`.

In `scene_layer_list_test.dart`: switching a layer to Shader through its row keeps `box: line` when it was set, and the box picker is there.

- [ ] **Step 2: Run to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_shader_field_test.dart test/scene/scene_layer_list_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement** the field, the kind-picker rule, and the plumbing as described.

- [ ] **Step 4: The catalog demo**

In `app/tool/catalog/demos/scene_paint_field.dart`, add a `ShaderPaint('shaders/foil.frag', …)` specimen fed by a `FixedSceneShaders` like the test's, in both the light and dark previews.

- [ ] **Step 5: Run, and look at it**

Run: `cd app && fvm flutter test test/scene` and `fvm flutter analyze` — PASS.
Then render the demo — through the flutterware MCP, `previews screenshot` of the *Paint field* entry, light and dark, `node=SceneShaderField` — and check the form column uses one type size, the captions sit on the ramp, and the slider/colour/number rows align with the gradient specimens beside them. Fix what looks wrong; attach the screenshot paths to the report.

- [ ] **Step 6: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/scene app/lib/src/plugins/native/scene_plugin.dart app/tool/catalog/demos app/test/scene
git commit -m "Scene inspector: pick a declared shader and edit its uniforms

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: An example shader, the spike removed, and the whole path driven

**Files:**
- Create: `examples/example/shaders/foil.frag`, `examples/example/demo/foil_title.scene.dart` (and a motion for it if one is needed to play — see Step 2)
- Modify: `examples/example/pubspec.yaml`, `docs/superpowers/specs/2026-09-10-scene-shader-paint-design.md`, `docs/superpowers/specs/2026-09-05-scene-master-plan.md`
- Delete: the spike files listed in the File map.

- [ ] **Step 1: The example shader**

`examples/example/shaders/foil.frag`:

```glsl
#version 460 core
// Foil for a headline: diagonal sheen bands over a tint, drifting with scene
// time. The comments on the uniforms are what the studio's inspector reads.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uColor;
uniform float uTime;
uniform float uAngle; // @range 0 6.283 @default 0.6
uniform float uSpeed; // @range 0 2 @default 0.35
uniform vec3 uShine; // @color @default 1 0.92 0.6

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 dir = vec2(cos(uAngle), sin(uAngle));
  float phase = dot(frag / max(uSize.y, 1.0), dir) * 3.0 - uTime * uSpeed * 6.2831853;
  float sheen = pow(0.5 + 0.5 * sin(phase), 6.0);
  vec3 base = uColor.rgb * (0.75 + 0.25 * frag.y / max(uSize.y, 1.0));
  vec3 c = mix(base, uShine, sheen);
  fragColor = vec4(c * uColor.a, uColor.a);
}
```

`examples/example/pubspec.yaml`: remove the spike's `assets/spike_iplr/` entry and its comment, and the two spike `shaders:` lines; declare `- shaders/foil.frag`. Delete every spike file listed in the File map.

- [ ] **Step 2: A scene that uses it**

`examples/example/demo/foil_title.scene.dart`, in the grammar the other demo scenes use (`arcade_poster.scene.dart` for a layered title): a frame with a two-line headline whose layers are a dark `StrokeLayer` under a `FillLayer(paint: ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': 0.6, 'uSpeed': 0.35, 'uShine': [1, 0.92, 0.6]}), box: SceneLayerBox.line)`. Write it through the studio's grammar rules (defaults omitted). For playback, give it a motion the way the other demo scenes do; if a motion needs a track, animate something small (the headline's opacity from 0.9 to 1) — the point is that the playhead runs so `uTime` moves.

- [ ] **Step 3: Drive the whole path**

Through the flutterware MCP (open with `flutterware_act {verb: observe}`; launch Studio (dev) only if nothing runs):
1. Open the scene editor on `foil_title` → the headline paints with foil in the canvas (screenshot).
2. Scrub the playhead → the sheen moves; play → it drifts. Note how smooth it looks against other motion (spec risk: editor playback cadence) and record the observed push cadence if the logs show it.
3. Select the fill pass → the inspector shows Shader, `foil.frag`, a slider for `uAngle` and `uSpeed`, a colour field for `uShine`, and no `uSize`/`uColor`/`uTime`. Drag `uAngle` → the canvas follows; undo reverts in one step; the file on disk gains the new spelling.
4. Edit `foil.frag` (change the base multiplier) and save → within a few seconds the canvas shows the change **without the guest restarting** (Task 3's reload). Revert the edit.
5. `previews screenshot` (or the scene video export) of the scene → the foil is in the flutter_tester lane too.
6. Break the shader on purpose (a syntax error), save → the canvas pass goes blank, the inspector shows impellerc's error, previews keep working; fix it → the pass comes back.
Record each observation, with screenshot paths, in the report. Anything that fails is a finding to fix in this task before committing.

- [ ] **Step 4: The spec catches up**

In `docs/superpowers/specs/2026-09-10-scene-shader-paint-design.md`: the status line says it is implemented, with the plan's path; decision 7 is rewritten to the clock-listenable form (Correction 1 of the plan); decisions 3 and 8 gain one sentence each for Corrections 2 and 4; any measured risk from Step 3 (the playback cadence) replaces its "measure once built" sentence with the measurement. In `docs/superpowers/specs/2026-09-05-scene-master-plan.md` §4.5 / M10, one line: shader paint shipped, pointing at the design doc.

- [ ] **Step 5: Full suites**

Run: `fvm flutter analyze`, `fvm flutter test` (root), `cd app && fvm flutter test`, `cd app && fvm flutter test --enable-impeller test/scene/scene_shader_paint_test.dart test/scene/scene_shader_capture_test.dart`, `fvm dart tool/prepare_submit.dart` → no diff.
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add -A examples/example docs/superpowers/specs
git commit -m "Example: a foil headline scene painted by a project shader, and the spike removed

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Self-review against the spec

| Spec | Where |
|---|---|
| 1. Bundle user shaders, stage union, content cache, reflection beside | Tasks 1–2 |
| 2. The value, file spelling, total wire, no samplers | Task 4 (samplers: Task 9 reports them) |
| 3. Mask path always; one rect / one band per line; layer carries blend and opacity | Task 6 |
| 4. Coordinates by transform | Task 6 |
| 5. Renderer uniforms, set only when declared at their size; strays skipped and reported | Tasks 5–6 |
| 6. Programs once per process, `RealWork`, `Listenable`, blank until loaded; per-slot pool | Task 5, used in Task 6; capture test in Task 6 |
| 7. Scene time as an input; repaint only with a shader pass (corrected: a clock) | Tasks 6–7 |
| 8. Editor waits; live reload in place | Tasks 3 and 8 |
| 9. Uniform controls from reflection + annotations; renderer uniforms hidden; asset picker; CI pin | Tasks 9–10 |
| 10. `precacheSceneShaders` | Task 5 |
| 11. Deferred: `ImageFilter.shader`, samplers, web | not built |
| Build order 9: example, spike removed | Task 11 |
