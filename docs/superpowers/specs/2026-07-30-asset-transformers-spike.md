# Asset transformers: what running them would cost

**Date:** 2026-07-30
**Status:** Spike findings. The reporting half shipped with this doc
(`AssetProblemKind.unsupportedTransformer`); the execution half is deferred,
costed below.
**Follows:** the asset verification session that found the gap (pre-M4 review
addendum, 2026-07-30).

## The gap

A pubspec may attach `transformers:` to an asset. A build runs each
transformer over the file and ships the *output*; `AssetCatalog` ignores the
key and `AssetBundleBuilder` symlinks the *source*. For a
`vector_graphics_compiler` asset that difference is fatal in the guest: the
app ships a compiled `.vec` the runtime loader can decode, the catalog serves
raw SVG bytes the same loader cannot. Worse than missing — the key resolves,
to the wrong bytes, and until now nothing said so.

## The contract (flutter_tools 3.47.0-0.1.pre)

`asset_transformer.dart` in `build_system/tools`:

- Per transformer: `dart run <package> --input=<tmp> --output=<tmp> <args...>`,
  run in the project directory, `FLUTTER_BUILD_MODE=<mode>` in the
  environment.
- Chained through temp files; the last output is copied to the bundle.
- A transformer may write `<output>.d` (a depfile) naming extra inputs; the
  tool folds those into invalidation.
- Failure is a non-zero exit or a missing output file, reported verbatim.
- `DevelopmentAssetTransformer` caps concurrency at `Pool(4)`.

## Measured

`vector_graphics_compiler ^1.1.11` via `fvm dart run`, resolved scratch
project, M-series macOS:

| case | wall clock |
|---|---|
| first `dart run` in the project | 0.53s |
| warm, 273-byte SVG (×3) | 0.26s each |
| warm, 163KB / 3000-path SVG (×2) | 1.02s then 0.40s |

The cost is process startup, not transformation: a 600× bigger input adds
~140ms. Call it **~0.3s per asset per run, sequential**; the tool's own
4-way pool makes it ~75ms amortised.

## What implementing it would look like

Transformed payloads cannot be symlinks, so `AssetBundleBuilder` would gain a
content-addressed cache: key = sha1 of (input bytes, transformer chain,
args), output under `build/catalog/transformed/<hash>`, bundle entry links
the cached output. First bundle of a project with N transformed assets pays
N×~75ms wall; an unchanged asset never pays again; an edited one pays ~0.3s
on the rebundle that notices it. Plus the real costs that are not milliseconds:
depfile invalidation, `FLUTTER_BUILD_MODE` (the guest is a debug build; a
transformer may emit differently per mode), and surfacing a transformer's
failure output through the inspector instead of a terminal.

## Decision

**Report now, run later.** `AssetCatalog` records
`unsupportedTransformer` per declaration — the asset still resolves so the
inspector can show it, and the problem says the guest's bytes are not the
build's. Execution waits for a project that needs it:

- The known concrete case is the SVG transformer, and it has a workaround
  that costs nothing here: load SVGs through the runtime parser (the
  `flutter_svg` path) instead of precompiling, which needs no transformer and
  renders identically in guest and app.
- For any other transformer the honest report beats a silently wrong render,
  and the cache design above is the implementation when one shows up.
