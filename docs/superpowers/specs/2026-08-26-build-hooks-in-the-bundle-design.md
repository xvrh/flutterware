# Running build hooks in the catalog's bundle

**Date:** 2026-08-26
**Status:** Design. Nothing built.
**Follows:** the Flutter GPU research of the same day, which is where the gap
surfaced and where every number below was measured.
**Sibling:** `2026-08-17-asset-transformers-design.md`. That one runs a chain
declared in a pubspec; this one runs a program a package ships. They land in the
same bundle and neither is the other.

## A model rendered, and it should not have

`flutter_scene` 0.23 loads a `.glb` through `Node.fromGlbAsset`. Made an
ordinary `@Preview` and driven by a two-step scenario, it rendered — lit,
shaded, captured as a step PNG like any other.

It rendered because **some other build had already run the hook**.

`flutter_scene`'s engine shaders come from its own `hook/build.dart`. Where the
toolchain offers data assets the hook registers them there; where it does not,
it writes into `flutter_scene_generated/` inside its own package directory,
which its pubspec declares as an ordinary asset. `AssetBundleBuilder` symlinks
declared package assets, so it shipped them happily — bytes produced by a hook
it never ran, left in the shared pub cache by an unrelated `flutter test`.

Move that directory aside and the same scenario says so in the package's own
words:

```
failed: Bad state: The physical material shaders are missing.
flutter_scene's build hook compiles them during the build,
so this is a build that ran without hooks.
```

**That is the whole bug.** Not that hook output is bundled wrong — it is bundled
correctly — but that whether it exists at all depends on what else the machine
happened to do. A clean checkout renders nothing; a developer who ran the app
once renders everything; and neither can tell which they are.

## What is there today

`AssetBundleBuilder` writes:

```dart
'NativeAssetsManifest.json',
jsonEncode({'format-version': [1, 0, 0], 'native-assets': <String, Object?>{}}),
```

A hard-coded empty map, with a comment saying it is empty in a JIT debug build
and the engine expects the file to exist. Both halves of that are true and
neither is the question — the file exists so the engine starts, and nothing has
ever put anything in it.

No hook runs anywhere in the previews or scenarios path.

## What it costs, measured

`flutter_scene`'s hook, which compiles a whole engine shader bundle:

| | |
|---|---|
| cold, with `.dart_tool/hooks_runner` wiped | **49.9 s** |
| warm | **1.2 s** — the same as a run with no hooks at all |
| cache on disk | 20 MB |

So it is affordable exactly once and never again, and the caching is not ours to
write: `package:hooks_runner` owns it.

**One trap in that number.** Deleting the hook's *output* does not invalidate the
cache — the run still reports warm and writes nothing. So the bundle builder can
never decide whether to run hooks by looking for files on disk; it has to ask the
runner every time and let the runner answer in a millisecond.

## The shape

Three pieces. Only the first is load-bearing on today's pin.

### 1. Run the hooks

`package:hooks_runner` (1.6.3) is the backend `flutter_tools` itself drives, and
an ordinary pub package. It is invoked once per build, before the manifests are
written, with the target the tester runs as.

This belongs beside `AssetTransformerRunner` and not inside it. Both produce
files the bundle then owns, and the resemblance ends there: a transformer chain
is declared in the consuming pubspec and runs per asset, and a hook is a program
a *dependency* ships and runs once for the whole package graph. They are two
stages, in that order, because a hook can produce a file a transformer then
transforms and never the reverse.

### 2. Bundle the data assets

Each `DataAsset` becomes one bundle entry, keyed

```
packages/<package>/<asset.name>
```

sourced from the hook's output file. That is `flutter_tools/lib/src/asset.dart`
at the `flutterHookResult.dataAssets` loop, and copying its key derivation
exactly is the point — a bundle whose keys differ from the tool's is a bundle
where `ShaderLibrary.fromAsset('…')` resolves in one and not the other.

Mirror its conflict rule too. The tool errors when a hook asset collides with a
pubspec-declared one rather than letting either win, and silence there is the
kind of bug that surfaces as a wrong picture.

**This is not urgent, and the reason is worth writing down.** `dartDataAssets` is
a master-only feature in `flutter_tools`; on beta and stable a hook is told
`buildDataAssets: false` and a well-behaved package falls back to writing into
its own tree — which the existing symlinking already ships. So on the pinned
SDK, *running* the hooks is the entire fix. This piece becomes load-bearing the
day the feature reaches beta, and building it before then means building against
a path nothing here can exercise.

### 3. A real NativeAssetsManifest

From the `CodeAsset`s of the same run, replacing the empty map.

Last, and behind a test, because nothing measured needed it: no package in
reach shipped native code through a hook. Writing it now would be writing it
blind.

## What a failure becomes

A hook is a program a dependency ships, so it can fail in ways an asset copy
cannot: it can be slow, it can throw, it can want a toolchain that is not
installed. The bundle builder's current failures are all `StateError`s about
files.

A hook failure must not read as "your catalog is broken". It is closer to a
compile error in a dependency, and the entries that do not need the hook's
output are still fine. The audit already distinguishes an unreachable package
from broken entries; a hook failure is the former.

## Deliberately not in this

- **Making it fast.** It is 49.9 seconds once. If that turns out to hurt, the
  lever is the runner's cache directory placement, not our own layer over it.
- **Running hooks for the guest separately.** The guest and the tester read the
  same bundle directory. One build, both lanes.
- **`build.dart` authoring.** Consumers write hooks; we run them.

## Open, to settle before building

1. **Which target do we ask for?** `flutter test` builds for the tester target,
   and a hook that branches on target platform will compile for it. But the
   research turned up that a hook compiles shaders for the *host's real*
   backend, and that the tester's default backend is a different one — which is
   why `--impeller-backend=metal` is now passed on macOS. Whether asking for a
   different target changes what the hook emits, and whether that is better or
   worse than what CI already proved works, is unmeasured.
2. **Where the cache lives.** `.dart_tool/hooks_runner` is 20 MB for one
   package. `2026-08-23-flutterware-dir-growth-design.md` is the standing
   argument about what we are allowed to leave on a disk.
3. **Whether a stale hook can be detected cheaply.** The runner answers in
   1.2 s warm, which is probably cheap enough to just always ask. Worth
   measuring against the sync path's own budget before assuming it.
