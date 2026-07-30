# The GUI slice — catalog loop in the flutterware app

**Date:** 2026-07-27
**Status:** Working, verified in the running GUI. Two limitations recorded below.
**Follows:** `2026-07-27-generated-wrapper-spike-findings.md` (the render path),
`2026-07-26-s1-scenario-in-embedder-findings.md` (the guest and the texture
bridge, whose "display in the GUI" gap this closes).

## What now works

`flutter run -t lib/main_catalog_dev.dart -d macos` brings up the catalog: an
entry list beside a **live embedder guest** in an external texture. Verified by
driving the running app:

| check | result |
|---|---|
| the guest renders the first entry | Team list, three avatar tiles |
| selecting an entry switches it | compile **5–10ms**, reload **85–107ms** |
| the compiler stays warm | `+0 libs` on every revisit |
| pointer events reach the guest | three clicks → `Taps: 3` |
| a desktop entry renders | NavigationRail + table |
| switching remounts state | back to Counter → `Taps: 0` |

Cold start was **509ms** with the asset bundle and C host already cached.

## The failure that shaped the design

The first cut put the resident compiler inside the Flutter GUI. It became an
**exponential fork bomb** that filled the machine in seconds.

`FrontendServerClient` spawns the compiler as
`Platform.resolvedExecutable <frontend_server snapshot>` and offers no way to
override the executable — passing `frontendServerPath` still uses
`resolvedExecutable` as the binary. Inside a Flutter app that is *the app
binary*, so asking for a compiler launched a second copy of the app, which
started its own session, which asked for a compiler. Each generation doubled.

Two things made it worse than it needed to be, both worth remembering:

- **The first symptom was silence.** `CatalogSession` reported failures only
  into its own UI, so a headless observer saw a stalled log and nothing else.
  Failures now also go to stdout.
- **A wrong inference cost a second run.** A 71MB `kernel_blob.bin` was read as
  "the cold compile succeeded" — it had been written by `flutter build bundle`,
  which writes a kernel into the asset dir too. The compiler had never
  succeeded at all.

> The master plan already required this: *the catalog pipeline must stay
> Flutter-free so the CLI can drive it later.* That constraint was not a
> preference about layering; violating it fills the machine.

## The split

| daemon — plain Dart | GUI — Flutter |
|---|---|
| engine framework download | guest process |
| asset bundle | texture bridge, input |
| entrypoint + wrapper generation | VM-service reload |
| resident compiler | entry list, timings, errors |
| C host build | |

`ResidentCompiler` refuses to start anywhere but a real Dart VM, so the
recursion cannot recur. `SessionLock` refuses a second session against the same
build directory.

Verify without the GUI at any time:

```sh
cd app && dart run tool/catalog/headless_check.dart
```

It runs the daemon and a real guest, switches through every entry, and asserts
what the guest **renders** — via an opt-in `FW-PROBE` line carrying the live
entry id and its text projection — rather than that a reload reported success.

## Limitations found by looking at it

1. **`preview.size` is clamped by the viewport.** The generated host centres a
   `SizedBox` of the declared size, and `Center` passes *loose* constraints, so a
   1440×900 desktop entry renders at whatever the guest view is rather than at
   its declared size. Nothing scales or scrolls it. The canvas-boundary decision
   already says device frames render **in the guest**, so this resolves when
   `DeviceFrame` + `FittedWidget` move there — but today the declared size is
   effectively advisory whenever the window is smaller.
2. **The entry list runs under the macOS traffic lights.** No title-bar inset,
   so the first row is partly hidden. Cosmetic, one padding away.

## Still stubbed

Discovery. The entry list is hand-written in `lib/src/catalog/stub_entries.dart`,
carrying each entry's annotation as source text exactly as a syntactic scan
would. Everything downstream of it — wrapper generation, the accumulating
entrypoint, the compiler, reload-to-switch — is real.

## Two mechanisms worth not rediscovering

- **`reloadSources` needs `rootLibUri`** set to the incremental dill, or the VM
  tries to start its own kernel-compiler isolate and every reload fails with
  `Error while starting Kernel isolate task`. It is what `flutter_tools` does at
  `run_hot.dart:1272`, and it was already in `run_scenario.dart:311` — only the
  S3 write-up omitted it.
- **`host.c` tags every log line**, so a guest's `print` arrives as
  `[embedder] FW-PROBE: …`. Matching on line start silently finds nothing.
