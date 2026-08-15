# `previews audit` is not an inner loop — findings

2026-08-14. An agent onboarding a consumer app onto previews adopted
`previews audit` as its edit-check reflex and the loop became unusable. The
project it replaced was a single `flutter test` that pumped every catalog entry
in one process.

Measured on that app: **133 previews, 970 sources in the compiler's program, 360
packages resolved.** Cross-checked against this repo's own catalog (100
entries), where the pipeline could be instrumented.

> **Status — superseded, and worth reading anyway.** Findings 1 and 2 were
> fixed in the embedder guest, taking this repo's 101-entry audit from 356s to
> 47s. Then the audit moved off the guest entirely: it renders under
> `flutter_tester` now, **17.6s** for the same catalog and the same six broken
> entries, and findings 3 and 4 went with the path they were about. The
> measurements below are why that move was made; the design is
> `2026-08-15-previews-audit-on-flutter-tester.md`.

## The gap

| loop | wall | per entry |
|---|---|---|
| `previews audit`, all 133, cold daemon | 184s | — |
| `previews audit`, all 133, **warm** daemon | **147s** | **1.10s** |
| `previews audit --path=…`, 3 entries | 7.1s | — |
| `previews check`, all 133, warm daemon | **1.0s** | — |
| `flutter test` catalog loop, cold | 41s | — |
| `flutter test` catalog loop, warm | **17.6s** (8.0s of it pumping) | **60ms** |

Warm and cold audit differ by 37s, which is the cold compile. It is not the
problem. **The problem is 1.10s per entry against the test's 60ms** — 18×, paid
133 times.

## Where the second goes

`auditAll` (`app/lib/src/previews/headless_catalog.dart:269`) instrumented per
phase, on this repo's 100 entries:

| phase | median | over 99 entries |
|---|---|---|
| `daemon.select` — incremental compile | 45ms | 4.7s |
| `guest.reload` — VM hot reload + reassemble | 302ms | 29.8s |
| `settle` + read errors | **3045ms** | **289.9s** |
| **per entry** | **3384ms** | 324s |

### 1. One entry poisons the settle deadline for the whole run

`_settle()` (`headless_catalog.dart:1311`) waits for
`imageCache.pendingImageCount == 0` **and** `transientCallbackCount == 0`, twice
running, and gives up after 3 seconds. Both counters are process-global and
cumulative across entries; the guest is reused for the whole audit.

So one preview that starts an image load which never completes leaves
`pendingImageCount` at 1 for the life of the guest, and **every entry rendered
after it burns the full 3 seconds** and is then reported `settled: false`.

Measured, in audit order:

```
 1  settle=  142ms  address_bar.dart#addressBarLive
 2  settle=   70ms  address_bar.dart#addressBarStates
 3  settle=   91ms  asset_inspector.dart#assetInspectorDetail
 4  settle=   61ms  asset_inspector.dart#assetInspectorList
 5  settle= 3042ms  asset_inspector.dart#assetInspectorPreviews   <- pending=1
 6  settle= 3033ms  avatar_tile.dart#avatarTileEmpty
 …  every one of the remaining 94, ~3045ms each
```

`counter`, `palette`, `tones` — static entries with no image and no animation —
all cost 3 seconds, because entry 5 rendered first. **282 of the audit's 324
seconds are this.** The reported counters at the deadline were
`pending=1 transient=0`, so it is a stuck image load, not an animation.

The 3-second deadline was designed as a backstop for a genuinely looping
animation. Keyed to a global counter, it became the common case.

**Fixed** — `SettleFloor` in `headless_catalog.dart`. The bar a settle clears is
learned rather than assumed: it rises only after a deadline has actually
expired with the count stuck above it, and drops back the moment a settle sees
a clean cache. Images only — `transientCallbackCount` is tied to mounted
tickers and an entry switch remounts, so giving an animation the same allowance
would report a demo that never stops moving as a still picture.

The stuck entry now pays the deadline **once**, to learn the floor, instead of
charging it to all 94 entries behind it.

### 2. The per-entry compile and hot reload buy nothing

The daemon's `registerAll` (`app/tool/catalog/compiler_daemon.dart:504`) imports
**every** entry's wrapper into the generated entrypoint at startup. Read the
generated file for this repo's catalog:

```
imports: 100
110:Preview get _preview => fw5.fwPreview.transform();
111:Widget Function() get _builder => fw5.fwBuilder;
112:String get _entryId => r'…#assetInspectorPreviews';
```

100 entries in the program; one hardcoded index selecting among them. The
compiled kernel the guest is already running **contains every preview in the
catalog.** The only thing `select` changes between entries is `fw5` → `fw6`
(`app/lib/src/previews/entrypoint_generator.dart:162`).

For that, the audit pays a frontend-server incremental compile (45ms) plus a VM
hot reload and a full widget-tree reassemble (302ms here, and it scales with the
app — the consumer's is larger). 347ms per entry to move an integer.

**Fixed** — `CatalogEntries` (`lib/src/ui_catalog/entries.dart`). The entrypoint
emits a lookup keyed by entry id instead of a hardcoded index, and the guest
registers `ext.flutterware.showEntry`. Switching is a message and a frame;
`select` stays for what it is actually for, which is sources that changed.
Measured on this repo: **347ms → 33ms** median.

Remount semantics were already safe — `_CatalogHost` keys the subtree on the
entry id, so a runtime switch remounts exactly as a reload does and
`CatalogGuest` resets the knobs, axes, errors and logs off the same change.

Two things the fix has to get right, both covered by tests:

- **A reload still wins.** The panel switches demos by regenerating the
  entrypoint and reloading — nothing sends `showEntry` — so the file has to
  outrank a runtime switch whenever it moves, and leave it alone when it does
  not (an ordinary source edit reloads naming the same entry). The rebase is a
  plain assignment in `didUpdateWidget`. It cannot be `reassemble()`, which
  runs before the rebuild and so still sees the *previous* widget's name.
- **A refusal is a value, not a throw.** An unknown id, a call that beat the
  first frame, and a guest too old to have the extension all answer with
  whatever is actually on screen. The host compares, and recovers with the
  compile and reload it would have done anyway.

### 3. `settle()` PNG-encodes a frame and deletes it

```dart
Future<void> settle() => _renderScratchFrame();

Future<void> _renderScratchFrame() async {
  var scratch = p.join(_workDir, 'knobs.scratch.png');
  await capture(scratch);
  var file = File(scratch);
  if (file.existsSync()) file.deleteSync();
}
```

`capture` runs `img.encodePng` and writes the file (`headless_catalog.dart:1251`).
Measured `img.encodePng` at the sizes the audit renders at:

| canvas | pixels | encode |
|---|---|---|
| panel 900×700 @1 | 0.6M | 17ms |
| iPhone 16 393×852 @3 | 3.0M | 89ms |
| MacBook Pro 1512×982 @2 | 5.9M | 173ms |

Per entry, for a file nothing reads. The consumer's catalog declares iPhone 16
and MacBook Pro canvases, so it is paying the 89ms and 173ms rows.

The scenarios half of this repo already learned this — its `format: raw` option
is documented as skipping PNG encoding, *"~80% of a capture's cost"*. The audit
needs a **frame**, not a **file**.

## What the numbers became

Measured on this repo's 101-entry catalog, same audit, identical findings — the
same six broken entries, by id, before and after:

| | before | after |
|---|---|---|
| per entry, median | 3384ms | **115ms** |
| · the switch | 347ms (45 compile + 302 reload) | **33ms** |
| · settle + read | 3045ms | **67ms** |
| whole audit | 356s | **47s** |

## What is left

**Finding 3 stands.** `settle()` still PNG-encodes a full-resolution frame and
deletes it — 17ms at the panel canvas, 89ms at iPhone 16, 173ms at MacBook Pro,
per entry, for a file nothing reads. It is now a visible share of a 115ms
entry rather than noise against a 3384ms one.

**And a fourth, which only became visible once the floor stopped hiding it.**
Nine entries still spend the full 3-second deadline, and eight of them are
right to: `counter` runs a 3-second `AnimationController` on purpose, and the
loading-state demos have spinners. They never settle, and `settled: false` is
the true answer.

But `auditAll` reads *errors*, not pixels. It has no picture to keep still, so
waiting for animations to stop buys it nothing — it spends 21 of its 47 seconds
on it. An audit wants a **built** frame, not a settled one; `captureAll`, which
does take pictures, is where settling earns its cost. Splitting the two is
worth more than finding 3 now.

## The larger point: the fast loop already exists here

Scenarios run under a directly-spawned `flutter_tester` with FakeAsync —
milliseconds, deterministic, one compile for the whole suite. That is precisely
the shape the consumer's `flutter test` catalog loop had, and precisely what
`previews audit` is not.

A preview is a widget with no interaction. Rendering all of them headlessly is
the scenario harness's exact job, and previews already share the screen grammar,
the device vocabulary and the canvas declarations with it.

**`previews audit` should have a headless mode that runs through the scenario
harness** — one compile, N pumps, fake clock, raw captures — and keep the
embedder path for what genuinely needs real rasterization. That makes the fast
loop and the audit agree by construction, instead of asking a project to keep a
hand-written test and a canvas list in sync.

## What to do today, with no flutterware change

For the agent onboarding right now:

1. **The inner loop is not `audit`.** Keep the `flutter test` catalog loop —
   17.6s warm, 8s of it real work, all 133 entries.
2. **`previews check` is the reflex after an edit**: all 133, **1.0s** against a
   warm daemon. It answers "does it all still compile", which is what most edits
   break.
3. **`previews audit --path=demo/src/<area>`** narrows to the subtree touched —
   7.1s for 3 entries.
4. **`previews inspect --entry=<id>`** for the one entry being worked on.
5. **Full `audit` is a pre-push or CI gate**, not an edit-check.

Worth saying in the onboarding docs, because an agent handed an action called
"audit every entry" with no cost attached will reach for it every time.

## One thing to fix on the consumer side

Their `canvases.dart` declares iPhone 16 / iPhone SE / MacBook Pro and its doc
comment says the catalog test reads it — *"One list, so the panel and the test
cannot disagree about what a directory is for."* The test does not read it yet:
it still sizes surfaces with a hand-written `isDesktopCatalogEntry` predicate
and the flutter_test 800×600 default.

So the fast loop and the audit currently judge each entry on different screens,
which is the failure the canvases exist to prevent, in the direction that hides
bugs. Making the test read the canvas list closes it — and is what makes
recommendation 1 above safe to rely on.
