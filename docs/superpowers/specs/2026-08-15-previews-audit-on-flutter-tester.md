# `previews audit` runs under `flutter_tester`

2026-08-15. The audit rendered every entry in the embedder guest, one at a time,
in real time. That is right for a panel somebody is looking at and wrong for a
catalog-wide check — see `2026-08-14-previews-audit-loop-speed-findings.md` for
the measurements. It renders under `flutter_tester` now.

Measured on this repo's own catalog, 101 entries, same six broken entries
reported either way:

| | |
|---|---|
| guest audit, before any of this | 356s |
| guest audit, after the settle floor and the runtime entry switch | 47s |
| tester harness, cold — a fresh process per audit | 10.1s |
| **tester harness, warm — the loop** | **8.2s** |

Four audits in one session: 10.5s, 8.2s, 8.1s, 8.1s. `examples/example`, 6
entries, cold: 13.3s.

**Cold and warm are two seconds apart, and that is the useful fact.** The
compile is not what an audit costs. Of the warm 8.2s, **6.6s is the 101 test
bodies** at ~65ms each and ~1.7s is host-side — the scan, the asset-bundle
sync, the invalidator sweep, one VM-service round trip. The slowest entry is
514ms (the first, paying first-frame warmup), then 256, 215, 189: a flat
distribution with no cliff in it, which is FakeAsync having removed the
three-real-seconds-per-animation problem rather than merely reducing it.

### Two levers measured and not taken

`--initialize-from-dill`, which is how `flutter test` makes a second run of the
same file feel quick, **does nothing here**. Alternated three times: 10152 /
10036 / 10446ms without a cached kernel against 10075 / 10036 / 10068ms with
one. That is noise, and it agrees with the ~25ms
`2026-07-27-compile-pipeline-performance-findings.md` measured for the same
flag — including its warning not to trust a before/after that was not
alternated. The kernel is 87MB, so priming from one would have copied that on
every cold start to buy nothing.

The remaining ~65ms an entry has two candidates, neither pursued: the boot turn
is unconditional (every entry pays `runAsync` with five real-millisecond delays
whether or not it loads an image), and `Settle.standard` waits for animations an
errors-only audit never photographs. Both are worth perhaps a second or two
between them, against a loop that is already fast enough — noted here so the
next person measures rather than rediscovers.

**The settle went the other way, and the paragraph above is why it had to.**
Following frames stops at the first frame the entry does not ask for, and an
entry waiting on a timer asks for none — so a demo that sleeps before it decodes
was disposed 100ms in with its timer pending, which `flutter_test` reports as
the entry leaking one. The audit now spends its whole budget
(`Settle.elapse(5s)`, `lib/src/previews/harness.dart`) rather than following
frames. Measured on a quiet tree: 42µs a settle following frames against 990µs
spending five fake seconds, so ~0.95ms an entry — 0.13s across a 133-entry
catalog, against the ~10s bring-up. The cost of *not* photographing is what pays
for this: an audit may hold the clock, a capture may not.

## Why not `flutter test`

Because it cannot measure text. `flutter test` passes `--use-test-fonts` and
`--disable-asset-fonts` unconditionally
(`flutter_tools/lib/src/test/flutter_tester_device.dart:119`), with no flag to
turn them off. `FontLoader` still registers the families a project declares, so
those are real — but text with no explicit family falls back to the test font,
and a catalog measured in it reports overflows that never happened.
`lib/src/scenarios/fonts.dart` names that failure in its own doc comment.

Spawning the tester ourselves is the only way to omit those flags, which is what
`ScenarioRunner` had been doing all along. So the audit does not shell out to
`flutter test`; it does what scenarios do.

## The shape

**`TesterHost`** (`app/lib/src/embedder/tester_host.dart`) is the extraction:
the flag list, the resident `frontend_server`, the asset-bundle sync, the two
refresh lanes (incremental compile + `reloadSources`, versus restart on a
changed source set), the respawn, the teardown. `ScenarioRunner` went from 551
lines to 238 and keeps only `list`/`run`/`onStep`; `app/test/scenarios/runner_test.dart`
passes unchanged, which is what made the extraction safe to do first.

A `TesterProgram` says the five things that differ: `name` (which names the dill
and the bundle), `readyLine`, `eventStream`, `sources()` and `writeEntrypoint()`.

**The harness** (`lib/src/previews/harness.dart`, exported from
`flutter_test.dart`) declares one `testWidgets` per entry. Two lanes off one
generated file, told apart by `Declarer.current`:

- nobody declaring → launched bare in a tester we spawned, so it declares into
  its own `Declarer`, registers `ext.flutterware.previews.audit` and waits. Real
  fonts. This is where a verdict comes from.
- something declaring → `flutter test` is running the file as an ordinary test.
  Shardable, needs no flutterware, and inherits the test font.

**What is deliberately identical to the guest**, because otherwise the two
backends would drift into disagreeing about the same catalog:

- the tree — each entry mounts under `CatalogGuest` and its annotation's
  `wrapper`, the same two the guest entrypoint mounts, so knobs answer and the
  axes, errors and logs reset per entry
- the errors — collected into `GuestErrors`, the same buffer with the same dedup
  key and the same counts, so `_asRenderError` maps them unchanged
- the rectangle — `previewPanelWidth`/`Height` in `lib/src/canvases.dart` is one
  constant that `CaptureViewport.panel` and the harness both read

That last one was found by the parity check rather than by design. A harness
that simply left the test surface alone judged entries on `flutter_test`'s
800×600 where the guest gives 900×700, and invented two overflows.

## A bug the parity check found in the old audit

`overflows.dart#overflows` came back at 476 pixels where the guest audit had
been saying 576. The demo is 8 boxes of 160 plus 8 margins of 8 — 1344 wide,
less 32 of padding — so 576 means it was judged at **800** wide and 476 means
**900**. Asked directly, `previews inspect` reports the guest rendering that
entry at 900×700 and overflowing by 476.

So the guest *audit* was framing entries at the wrong size, and had been all
along; the single-entry path never was. Nothing else caught it because an audit
row said which device an entry was framed as, not how wide it actually came out.

## Compile errors

The harness imports every entry, so one broken demo fails the compile for all of
them. `PreviewTestRunner._bringUp` reads the compiler's own diagnostics through
`CompileBlame` — the same parser the catalog daemon uses — quarantines the
entries declared in the files it blamed, regenerates and tries again, bounded at
ten rounds. A blamed entry becomes `compiles: false` with the diagnostics
verbatim. Errors nobody declares an entry in stay fatal, because dropping
something cannot fix them.

## Two things that got quietly cheaper

`motion_core` and `tool/catalog/motion_shots.dart` both called `auditAll()` to
get the entry *list* — rendering an entire catalog to look up one id. Both use
`check()` now, which needs no guest at all.

## What this leaves

The embedder guest keeps everything that needs a real frame: `compare`'s pixel
diffs through `captureAll`, `screenshot`, `inspect`, and the panel. Findings 3
(a discarded PNG encode per entry) and 4 (waiting for animations an errors-only
audit never photographs) were both about the guest audit and went with it.

The `flutter test` lane's font caveat is real and is written into the generated
file's own header, so somebody who runs it and gets a surprising overflow finds
out why in the file they ran.
