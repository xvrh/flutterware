# Running build hooks in the catalog's bundle

**Date:** 2026-08-26
**Status:** Pieces 1 and 3 built — 3 on 2026-08-31, the day a real suite
needed it (see its section). Piece 2 stands as written, and the reason it
waits is in it.
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
| warm | **110–125 ms** in-process |
| cache on disk | 20 MB |
| a workspace whose only hook builds native code | **40 ms** |
| asking whether there is anything to run at all | **30 ms** |

The warm number is two caches deep and neither is ours: `hooks_runner` decides
whether to run the hook, and the hook decides whether to rewrite its own output.
A first ask after wiping only the former cost 1.2 s and rewrote nothing.

So it is affordable exactly once and never again, and the caching is not ours to
write: `package:hooks_runner` owns it.

**One trap in that number.** Deleting the hook's *output* does not invalidate the
cache — the run still reports warm and writes nothing. So the bundle builder can
never decide whether to run hooks by looking for files on disk; it has to ask the
runner every time and let the runner answer in a millisecond.

## The shape

Three pieces. Only the first is load-bearing on today's pin.

### 1. Run the hooks — built

`app/lib/src/assets/build_hooks.dart`, called from `AssetBundleBuilder.build`
before `AssetCatalog.resolve` — a hook writes into a directory the catalog
enumerates, so running second is a faithful reading of an empty directory.

`package:hooks_runner` is the backend `flutter_tools` itself drives, and an
ordinary pub package. **Pinned to the version the SDK in `.fvmrc` pins**, with a
test that fails when they drift, for two reasons. A hook and the runner
negotiate a protocol version, so the runner a project's own hooks were resolved
against is the one that can speak to them. And the newest (1.6.3) requires
`code_assets ^2.0.0`, which evicts `native_toolchain_c` and takes `sqlite3` back
a major version under the Server panel; 1.6.1 adds one package and changes
nothing else.

**Asked with no protocol extensions**, which is the whole of why piece 2 can
wait and is measured rather than assumed. A hook branches on what was asked for:
given no data assets it writes into its own package tree, which the bundle
already ships, and given no code assets it returns on its first line —
`sqlite3`'s hook opens `if (!input.config.buildCodeAssets) return;`. So the
ordinary project pays a process spawn, and native code is still not built for
previews, exactly as it never was.

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

### 3. A real NativeAssetsManifest — built 2026-08-31

From the `CodeAsset`s of the same run, replacing the empty map.

It was deferred because nothing measured needed it — and then a real suite
did: a consumer's 51 scenarios all open a database through `sqlite3` 3.x,
which resolves its C functions via `@Native` and this manifest, with no
runtime override left in the package. The empty map does not even fail
honestly. The VM falls back to looking the symbols up in the running process,
which happens to succeed on macOS `flutter_tester` (with the *system's*
SQLite) and fail on Linux and Windows — so the suite was green on every
laptop and red on CI, identically, on step 1, while the previews half of the
same comparison was perfect. Installing the system package changes nothing;
it is the build that is missing, not the library.

The build asks with a `CodeAssetExtension` for the host — `OS.current`,
`Architecture.current`, dynamic linking — because that is `flutter test`'s
tester target and `flutter_tester` is a host binary. No `cCompiler` is named:
`flutter test` itself tolerates not finding one for this target
(`mustMatchAppBuild: false`), a compiling hook discovers the host toolchain
the way it does under plain `dart test`, and `sqlite3`'s hook turns out to
*download* its library rather than compile it at all. Link hooks stay off
(`linkingEnabled: false`), as `flutter test` decides for a JIT build.

Bundled libraries are **copied** into the bundle
(`<assets>/native_assets/`, flat, plain basenames — the layout `flutter
test` uses) and the manifest names the copies. The first cut pointed the
manifest at the hook's own output in place; review killed that: the file a
warm guest has `dlopen`ed must be one nothing else rewrites, and
`.dart_tool/hooks_runner` is rewritten in place by any tool that re-runs the
hook on the checkout — on macOS, mutating a mapped signed dylib can kill the
process holding it. The copy is replaced by rename, never written in place,
so a rebundle leaves a live guest on its old inode; freshness rides a stamp
file (source path, mtime, size) so an unchanged library costs a stat, not a
byte-compare of megabytes. The flat directory also restores the two
properties the scattered layout lost — `@loader_path` references between
sibling dylibs resolve, and on Windows the tester is spawned with this one
directory prepended to `PATH`, the same line `flutter test` adds, so a hook
DLL's own dependencies resolve.

Open question 1 below is thereby half-settled: the target asked for is the
host's. What a hook emits for a *device* target is still nobody's question
here.

Verified end-to-end by `examples/example/test/scenarios/database_test.dart`,
which shows the version of the SQLite it loaded — the bundled library is
newer than the macOS system one, so the manifest lane is distinguishable
from the fallback that masks a regression on a Mac. The Windows CI scenarios
run is the honest platform.

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

1. **Which target do we ask for?** Settled for now by asking for no asset
   types at all, which is the only shape that needs no target. It becomes live
   again with piece 2: `flutter test` builds for the tester target, and a hook
   that branches on target platform will compile for it — but a hook compiles
   shaders for the *host's real* backend, and the tester's default backend is a
   different one, which is why `--impeller-backend=metal` is now passed on
   macOS. Whether asking for a different target changes what the hook emits is
   still unmeasured.
2. **Where the cache lives.** `.dart_tool/hooks_runner` is 20 MB for one
   package. `2026-08-23-flutterware-dir-growth-design.md` is the standing
   argument about what we are allowed to leave on a disk.
3. **Whether a stale hook can be detected cheaply.** ~~The runner answers in
   1.2 s warm~~ — 110–125 ms, measured in-process. Cheap, but not free against a
   reload, so the built version memoises on the resolution's content and asks
   again whenever that moves. What that does not notice is a hook's own source
   changing under a path dependency, which is a package author editing their own
   hook and costs them a restart.
