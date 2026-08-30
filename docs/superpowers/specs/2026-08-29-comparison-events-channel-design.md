# The events channel — saying which field moved

The comparison's events channel compares a *masked string* and reports a
multiset difference over it. Everything a reader would act on — the status
code, the log level, the payload, the body — is dropped before the comparison
starts, and what survives is reported as `- gone` / `+ arrived`.

This note argues that the mask is not the mistake. **The shape is.** A multiset
over a whole-event key cannot express "one field of this event moved," so every
field folded into the key becomes all-or-nothing: fold in the body and a
4000-character JSON differing in one property prints twice, in full; leave it
out and a `200 → 500` on the same endpoint is silence. There is no setting of
that dial that behaves well, which is why every choice on it has looked
arbitrary.

The fix is the one the tree channel already made: **align, then diff.**

## What was specified, and what shipped

`2026-08-11-worktree-comparison-design.md` §5 said this from the beginning:

> FakeAsync makes the ordering deterministic, so alignment is
> `(method, url-template, ordinal)`.

Alignment. What landed in `08db2c68` was a multiset over `EventChannel.mask` —
channel plus title with digit-runs collapsed to `#` — and no alignment at all.
The table row beside it (`channel + title, digits masked`) records the pairing
key as though it were the comparison rule. §5 needs correcting on that point;
this note is the correction.

The same section also predicted the noise:

> Tokens, timestamps and request ids will make every event diff 100% noise
> without field masks.

Measured on a real 127-scenario suite by a consumer who diffed 1071 captured
event files leaf by leaf, run against run on one commit: the widget trees
differed in **0 of 1179** files and the pixel digests in **0 of 1189** steps,
unmasked, and the events channel had exactly three sources of run-to-run
difference.

| source | leaves | whose |
|---|---|---|
| `autofill.uniqueIdentifier` = `EditableText-<identityHashCode>` | 266 | the framework's |
| the project's own `Uuid()` calls | ~100 | the project's |
| the project's own wall-clock timestamps | 36 | the project's |

Two of the three are a project bug of exactly the kind this tool exists to
report — the same shape as a preview entry calling bare `DateTime.now()`. The
prediction was that determinism was unreachable. It is reachable, the rest of
the product already assumes it (FakeAsync, the pinned clock, `ShotKey.revision`),
and the events channel is the only place that hedges against it.

## What the mask costs, measured

Same suite, branch against base, 1325 shared steps:

| | steps |
|---|---|
| the mask reports changed | 104 |
| raw event data differs | 318 |
| **the mask says same, raw differs** | **214** |

Those 214 steps carried 293 hidden field-differences: 192 `system` chatter
(`TextInput.setClient`, differing only in the framework identity hash), 100 the
project's own uuids and timestamps, and **one** intentional behaviour change on
the branch under review — two `_logger.info` calls became `_logger.warning`.
The comparison reported those steps unchanged.

The hit rate reads well and it is the wrong measure. The channel exists to
catch what no picture can; a log level moving from INFO to WARNING is squarely
that, and it is the one thing in the set the mask was not entitled to drop.

## 1. Three prose channels, two shapes

`ChannelLines` draws all three side by side, and events is the odd one out:

| channel | how it compares | what a reader sees |
|---|---|---|
| `tree` | LCS-align on a signature, then diff per property | `Padding  all  12 → 20` |
| `texts` | multiset over the **exact** string | `- old` / `+ new` |
| `events` | multiset over a **lossy** key | `- masked` / `+ masked` |

`texts` gets away with a multiset because a visible text has no fields — the
string *is* the whole thing, so nothing can be lost by keying on it. An event
has seven fields, and the multiset forces a choice about all of them at once.

Worth knowing before designing around it: **the payload is already captured,
already written to `.events.json`, and already rendered.** The step's Events
pane expands `body` and `data` in full (`app/lib/src/scenarios/events_view.dart`).
The comparison is the only place that throws it away. When `EventChannel.mask`'s
docstring defers to "the detail-level diff a panel shows," it is reaching for
that pane — which shows one run, not two. Nothing under
`app/lib/src/comparison/ui/` renders `detail` or `level`. Under this design the
deferral becomes true, because the comparison itself is that diff.

## 2. Align, then diff

Per step, over the base and head event lists:

1. **Align** on the exact key — `channel` + `title`, verbatim — with the same
   longest-common-subsequence the tree and the scenario flow already use.
2. **Fuse** the unmatched runs, one-to-one, where exactly one leftover on each
   side shares the *collapsed* key (digits → `#`). This is `TreeDiff._fuse`
   applied to events, for the same reason and with the same refusal: two
   leftovers on a side is a real ambiguity and guessing is nonsense.
3. **Diff each pair** field by field, and emit one delta per leaf that moved.
4. **Unmatched after fusing** stay `added` / `removed`, as today.

The mask survives, promoted to the job it was always good at. Collapsing digits
is a *pairing* heuristic — it is how `/cases/case_0` finds `/cases/case_1` — and
it stops being the thing that destroys the payload. Exactly the split the tree
already draws between `_signature`, which matches, and `_label`, which reads.

Two consequences fall out of the shape rather than being special-cased:

- **A changed record is visible.** `/cases/case_0` → `/cases/case_1` fuses and
  reports `title  /cases/case_0 → /cases/case_1`. Under the multiset the two
  masked to one string and the difference did not exist.
- **Order is visible.** LCS is a sequence alignment, so an auth call that moved
  after a data fetch no longer aligns in place. §5 is right that FakeAsync makes
  ordering deterministic, which is what makes a reorder a real finding rather
  than a flake.

**Why the exact key first, and not the collapsed one.** Aligning directly on the
collapsed key is the cascade #297 removed from drift: an app that requests
`/orders/1 … /orders/5` has five events sharing one key, so inserting a sixth
pairs them all off by one and reports five title deltas for one insertion.
Aligning on the exact key pairs the five that are identical, leaves one
unmatched, and reports it as the addition it is.

## 3. Leaves, not events

`data` is a map whose values nest — `autofill.uniqueIdentifier` is two levels
down. A delta that says "`data` changed" repeats the multiset's failure one
level lower, so `data` flattens to dotted leaf paths (`autofill.uniqueIdentifier`,
`items[2].id`) and each leaf is its own comparison. That is also the vocabulary
the consumer's own forensics used, and the vocabulary the counts above are in.

`body` is a string and needs a rule of its own, because it is the field most
likely to be enormous:

- **Parses as JSON** → flatten to leaves like `data`, prefixed `body.`. A
  changed field in a response reads as `body.user.role  "member" → "admin"`.
- **Otherwise** → one `body` delta carrying a **first-difference excerpt**: the
  offset, and a window either side. Never two full dumps. This is the specific
  brittleness the current shape produces the moment anything large enters the
  key, and the excerpt is the answer to it.

## 4. What a delta looks like

```
network POST /login        detail   200 → 500
log     card declined      level    INFO → WARNING
db      select * from …    detail   3 rows → 0 rows
network POST /orders/#     title    /orders/1 → /orders/2
analytics checkout         data.cartId   "a1" → "b7"
network POST /pay          body.user.role  "member" → "admin"
system  TextInput.setClient  moved   #4 → #9
```

One line per thing that moved, which is what the tree channel gives and what
the events channel has never been able to.

`EventDelta` mirrors `TreeDelta` — `kind`, `title`, `property`, `base`, `head`
— because a reader learning one has then learned the other, and `ChannelLines`
already knows how to draw that shape.

## 5. Caps, and the app that is not deterministic

A project that has *not* normalised itself gets more lines here than it does
today. That is the intended direction — the lines are the bug report — but it
must not become a wall:

- **50 deltas per channel**, with `deltasDropped`, the way the tree caps —
  *per channel*, not per item. A shared budget is a filter's undoing: 400
  `system` deltas would eat the allowance `pixels` and `tree` needed, so a
  reader who filters to a quiet channel gets a truncated list of something that
  was never noisy. §6 is only free if each channel is complete on its own.
- **20 leaves per event**, with a drop count, so one huge payload cannot eat
  its channel's budget either.
- The summary line says what was dropped and on which channel, so a truncated
  list never reads as a complete one.

Cost is not a concern: `maxAppEventsPerStep` is 200, so the LCS table is at
worst 200×200 per step.

## 6. The choice belongs to the reader, and it is a lens

192 of the 293 hidden differences were `system` chatter. Nobody wants that by
default, and it is exactly what you want visible when the bug is a focus or a
keyboard bug. Today the comparison rule and the display default are the same
decision; they are two decisions.

**Compare every channel. Let the reader choose what to look at.** That is not a
new mechanism: `ObserveLens` (`app/lib/src/inspect/lens.dart`) settled this
question for the screen grammar, and its docstring closes with *"Only `run`
reads it today; that is adoption pending, not a different design."* The
comparison is the next adopter, and three of its decided rules transfer
unchanged:

- **Presets, not booleans.** *"Four presets rather than six booleans, because
  the booleans are the thing a caller will not read... A lens is the answer to
  'I am doing this kind of work' rather than to 'I want these fields'."* The
  request that prompted this note was literally six booleans — pixels, `+tree`,
  `+texts`, `+network`, `+db`, `+logs`, `+system`.
- **Explicit flags always win.** `{lens: 'review', system: true}` returns
  system. A preset is a default, and one that overrode what the caller said
  would be a trap.
- **It pins to disk.** `lensPathFor` keeps the choice beside the handle, so
  `fw`, the GUI and the MCP server all see the same one and an agent does not
  re-send it every call.

**The GUI gets chips; the MCP gets a lens.** A chip row is visible and costs
nothing to read, so six toggles are right there. An API parameter is six
decisions per call, so it needs presets. Same filter underneath, different
affordance, because the cost of a control differs between the two surfaces.

**The filter reads; it never shapes the comparison.** The reader cannot know in
advance which field will matter — the one real finding in the measurement above
was a log level, and nobody opts into `level` before seeing it. A tool whose
job is to show what changed must not have already decided what you would want
to see. And there is no cost on the other side: the events are captured, on
disk and read into memory before any of this runs, so diffing every leaf is
microseconds. A comparison-time switch would buy nothing and cost discovery.
`index.json` is published API besides, and a consumer's `tool/` script should
not get different answers because of how the run was invoked.

**This is not a gate, and gains no gating knob.** `fw compare` exits 0 whatever
it finds; the only `exitCode` it inspects is a subprocess's.
`ComparisonIndex.ok` is offered *to* a project's own script — the feature is
"show me what changed", never "fail if something changed". So there is no
policy layer here and no per-channel pass/fail setting. One lens, over a
complete artifact. A knob for what counts as failure would be answering a
question this feature does not ask.

Counts always show, whatever the lens, so a filtered channel still announces
that it has something to say:

```
events: 3 changed, 1 added  (+192 system, hidden)
```

This is what makes the extra sensitivity affordable. It is also worth being
honest that under the *current* masked shape the filter would buy almost
nothing — the 192 differ in `data`, which the mask already discards, so they
are invisible either way. The filter only becomes load-bearing once the channel
compares fields, which is why the two ship together.

**Nothing reaches an agent to filter yet.** `ComparisonCompareResult` carries
`findings` with `id`, `half`, `state`, `note` and a `delta` *string*
(`"0.38% · 2 regions"`), plus a **path** to `index.json`. No channel content
crosses the MCP boundary at all — an agent has to open the file itself. The
lens is meaningless until the reply carries deltas, which sets the build order
in §11.

## 7. Normalise where the value is made — there is already an organ for it

The sharpest structural point in the consumer's report, and it is right:

> Any derived field, any truncation, any length or hash taken over a payload
> has already absorbed the noise.

They normalised all three sources out of the raw captures and re-diffed; 11 of
1071 files still differed, every one on a truncation counter reading
`… (1429 more characters)` against `… (1432 more characters)`. Same root cause
— identity hashes of differing digit-length — surviving because `_capData`
computed the count from `data.toString()` at capture time, before any mask
could reach it. A comparison-time rule can never win that. **`_capData` must
cap per leaf, not per map**: today it replaces the whole map with
`{truncated: …}` past 4000 characters, which collapses a payload into a
stringified blob and defeats §3 exactly where payloads are largest.

### The long tail is real, and it is not the project's to declare

An identity hash embedded in a string is not one bug, it is a **class** of bug,
and this repository has been collecting entries for a while.
`withoutIdentityHash` (`lib/src/inspect/node.dart`) is the organ, and its
docstring is the history:

| shape | example | source | status |
|---|---|---|---|
| `Type#a1b2c` — `describeIdentity` / `shortHash` | `ScrollController#cf895` | framework | ✅ handled; cost 21 previews entries before it existed |
| `[#a1b2c]` — a bare `UniqueKey` | `[#a1b2c]` → `[#]` | framework | ✅ handled |
| `[GlobalObjectKey int#8cc0b]` | `go_router`'s `_CustomNavigator` | framework | ✅ handled; cost a consumer *every* scenario of a routed app, forever |
| `EditableText-<hashCode>` | `EditableText-873965551` | framework | ✅ added here |
| `'<fn>@<token>'` inside a closure | `'_imageBuilder@21460559'` | a package (`octo_image`) | ✅ added here |

The last two are the entries this note adds. The autofill one is deliberately
**literal** — `EditableText-\d+`, not a general `Type-<hashCode>` rule. A
decimal run after a capitalised word is the shape of a great many real values
(`SKU-4491`, `Contact-4491`) where five hex characters after one is the shape
of almost nothing else, and this is the only instance anybody has proven. Note that the closure one differs
in **kind** from run-to-run noise: base and head are two separate compilations,
so a token hash can differ even when the code is identical. That makes it a
*permanent* false positive on every comparison — precisely the failure mode the
`GlobalObjectKey` row cost somebody before it was fixed.

**Corrected by measuring it (2026-08-30).** The shape above was inferred and
was wrong in a way that mattered. What Dart actually prints is

```
Closure: (Object?, Object?) => Object? from Function '_imageBuilder@21460559':.
```

There is **no `line:col` in a closure at all**, so half the proposed rule was
addressing something that does not exist; an anonymous closure prints no name
either (`Closure: (Object?) => Object?`) and a public tear-off prints no token
(`from Function 'main': static.`). The `@21460559` is Dart's mangling of a
**private** member's name, derived from its library.

So the rule is the minimal one, and the same one every other entry follows:
**the token goes, and nothing else does.** `'_imageBuilder@21460559'` becomes
`'_imageBuilder@'`, exactly as `ScrollController#cf895` becomes
`ScrollController#`. The quotes on both sides are what make it safe — an `@`
between an identifier and a digit run, inside quotes the framework wrote.

Two rules govern additions to this list, both already written into
`withoutIdentityHash`'s docstring and both worth restating because they are what
keep it safe:

1. **Anchor on the exact syntactic shape the emitter produces**, never on
   "digits look like noise". That discipline is what keeps
   `ValueKey('build#a1b2c')` intact — the author's own value, and the only
   thing telling two of those apart.
2. **Every entry carries the bug it fixed.** The docstring reads as a list of
   incidents rather than a list of patterns, which is what makes the next
   reader able to judge whether a proposed sixth entry belongs.

### One normaliser, every channel

`withoutIdentityHash` ran on a widget's `properties`, its resolved `textStyle`
and its key — the tree channel only. Events never passed through it, which is
why `EditableText-<hashCode>` reached a comparison at all.

It now lives in `lib/src/utils/identity_hash.dart`, plain Dart, imported by the
inspect node, by scenario targets and by `AppEvent`. Its own file because the
sharing is the point: an identity hash is noise on a widget's properties, on a
scenario target and on an app event alike, and three copies of one rule is
three chances to fix only two of them.

Applied on the way *in* — to an event's `title`, `detail`, `body` and each
flattened `data` leaf — before `_capData` computes any length. That ordering is
§7's whole point: normalise, then truncate, then compare.

## 8. The origin of an event, recorded lazily

A filter worth the name has to answer *"exclude the db events coming out of
`lib/data/cache.dart`"*, and nothing an event carries today can. The cheap way
to give it one is `StackTrace.current` inside `recordAppEvent` — cheap only if
it is done the right way round, which the measurement decides.

JIT, by stack depth (a Flutter widget-test stack — build → element → gesture →
app → fake — is easily 100 frames):

| depth | capture only | capture + `toString()` + parse |
|---|---|---|
| 10 | 0.82 µs | 13.4 µs |
| 50 | 2.01 µs | 41.4 µs |
| 100 | 3.47 µs | 78.6 µs |

Resolution is ~20× the capture and scales with depth. At `maxAppEventsPerRun`
(5000), resolving eagerly costs **~390 ms per scenario** — on a 128-scenario
suite that is roughly 50 s, a third of a scenario half. Capturing without
resolving costs ~17 ms per scenario, ~2 s across the same suite.

So: **capture the object at record time, resolve it at write time.** Events are
dropped by `maxAppEventsPerStep` long before they reach disk, so resolution is
bounded by what actually lands in `.events.json` rather than by what was
recorded. And gate the capture on `appEventBuffer != null` — the null check is
already the first line of `recordAppEvent` — so a production app and a plain
`flutter test` pay nothing at all.

Two rules on what is kept:

1. **The origin is never compared.** A line number moves when anything above it
   moves, so an origin inside the compared set would report every event as
   changed on any edit — the same permanent false positive as the closure entry
   in §7, arriving through a field we added ourselves. It is its own field,
   excluded from the delta set by construction, and it exists to be *filtered
   on* (§9).
2. **File and symbol, never `line:col`.** The line contributes nothing to
   "exclude events from this file" and is the churn that would make the value
   worthless. Resolution walks the trace, skips frames whose URI is
   `package:flutterware/`, and keeps the first that is not — the app's own code,
   which is what a reader means by where an event came from.

An async gap truncates the trace and sometimes leaves no app frame at all, so
`origin` is nullable and a filter must treat "unknown" as its own value rather
than as a match.

## 9. The facet contract — what phase A must record

This is the seam between the model and the UI pass, and the one decision in
this note that cannot be deferred. A filter can only ever filter on facets the
comparison recorded; if the model ships without them, the UI reopens the model.

Every delta carries five, all derivable at diff time and all cheap:

| facet | values |
|---|---|
| `half` | `previews` · `scenarios` |
| `channel` | `pixels` · `tree` · `texts` · `events` |
| `subchannel` | events only — `network` · `db` · `log` · `analytics` · `platform` · `system` · a reporter's own name |
| `property` | what moved: `detail`, `level`, `size`, `offset`, `body.user.role` |
| `origin` | events only, nullable, from §8 — **never compared** |

`subchannel` is just `AppEvent.channel`, which the mask already puts at the
front of its key; naming it as a facet is what lets a reader ask for `db`
without parsing a string. `property` is already what `TreeDelta` carries, so
the tree channel satisfies this contract today.

Two fields are deliberately **not** compared, both found by building it:

- **`error`** is derived — from the status for a request, from the level for a
  log — so a delta for it restates the `detail` or `level` delta immediately
  above and doubles the two commonest findings the channel has. It tints a row;
  it is not a fact of its own.
- **`body`, when it folds to the title.** A db event carries its statement
  twice, folded into the title and raw in the body, so comparing both reports
  one changed query as two lines saying the same thing.

A filter is then a list of **rules**, each a conjunction over these facets, each
including or excluding. That is what a request like *"pixels and events, but not
db from `lib/cache.dart`, and no logs at all"* decomposes into with no query
language anywhere:

```
include  channel ∈ {pixels, events}
exclude  subchannel=db ∧ origin=lib/data/cache.dart
exclude  subchannel=log
```

The conjunction in the middle rule is why independent per-facet checkboxes are
not enough, and it is the whole reason this is written down before the UI: the
shape of the rule decides the shape of the record. How a rule gets *authored* —
never typed — is the UI pass's problem, not this note's.

## 10. Wire format

`EventChannel` gains `changed`, a list of `EventDelta`. `added` and `removed`
stay as they are.

```json
"events": {
  "added":   ["network POST /verify"],
  "removed": [],
  "deltas": [
    {"kind": "changed", "title": "card declined",
     "subchannel": "log", "property": "level",
     "base": "INFO", "head": "WARNING",
     "origin": "package:app/src/checkout/card.dart CardForm._submit"}
  ],
  "deltasDropped": 0
}
```

`half` and `channel` are already the delta's position in the document, so only
`subchannel`, `property` and `origin` are written per delta.

**Corrected while building (2026-08-30).** The list is `deltas`, not `changed`.
`EventChannel.changed` is a **bool** in the published reader, exactly like
`TreeChannel.changed` and `TextChannel.changed`, and turning it into a list
would have broken every script that reads one. `deltas`/`deltasDropped` is also
what `TreeChannel` already writes, so the two channels now spell the same idea
the same way.

Added fields do not bump `comparisonReportVersion` — `lib/comparison_report.dart`
says so explicitly, and `#297` set the precedent with the drift fields. An older
reader ignores `changed` and sees the same `added`/`removed` it sees today.

## 11. Decided — do not relitigate

1. **The mask is kept, as the fallback pairing key.** It was never wrong about
   what makes two events *the same event*; it was wrong as a comparison key.
2. **No `--events=raw` flag.** Under align-then-diff the channel compares
   everything, so there is nothing for a flag to turn on. It was a hedge
   against the wrong problem.
3. **`detail` and `level` are not added to the pairing key.** Proposed first,
   and it is actively wrong: keying on `detail` splits the very pair needed to
   report `200 → 500` as one line.
4. **The normalisation list is ours, and it grows.** A per-project regex
   config in `tool/flutterware.dart` was asked for and is not the shape. Every
   irreducible entry proven so far — `describeIdentity`, bare `UniqueKey`,
   `GlobalObjectKey`, `EditableText-<hashCode>`, `octo_image`'s closure — comes
   from the framework or from a published package, so it is the same entry for
   every consumer: one we take is one everybody gets, and one we test. A
   project's own `Uuid()` and `DateTime.now()` are not on the list and must not
   be, which is the consumer's own bar (*"only values no project can make
   deterministic"*) and what field-level deltas now make actionable — noise
   arrives as a **named leaf on a named event**, which is a bug report rather
   than a mystery.

   This is a claim with a falsifier: **zero project-specific entries have been
   proven to date.** Bring one that is genuinely irreducible, not shareable and
   not `system`, and the config becomes the right answer. Until then a regex
   list applied to arbitrary fields at capture time is a permanent API whose
   failure mode is silently blanking a real change — the outcome this note
   exists to remove.

5. **No gating knob.** See §6. The feature shows what changed; it does not fail
   a branch, so there is nothing for a pass/fail policy to configure.

## 12. Left open

1. **Is `moved` a finding by default?** §5's determinism argument says a
   reorder is real, not a flake, so it should count. The risk is a step whose
   events legitimately interleave reporting a diff on every comparison. Lean:
   report it, count it, and measure before deciding whether it ranks below
   `changed`.
2. **Is `system` hidden always, or only when another channel has deltas?**
   Always is simpler and the count still shows. Hiding conditionally means a
   step whose *only* finding is a focus change still surfaces it. Lean: always
   hidden, and let §6's count be the door — a reader who sees `+192 system`
   knows where to look.
3. **The excerpt window for a non-JSON body.** A constant to measure against a
   real branch rather than pick here, in the spirit of §14 of the comparison
   design.
4. **Which comparison lenses there are.** §6 settles that it *is* a lens and
   that presets beat booleans; it does not name the presets. `ObserveLens` got
   its four by measuring the real combinations, and that is the way to get
   these — after the deltas are in the reply and there is something to measure.

## 13. Build order — three shipments

The phases are cut so that each one is useful alone and none of them reopens
the one before it. **A and B are this note; C is
`2026-08-30-comparison-ui-pass-design.md`.**

### A — the model

1. ✅ `EventDelta` + leaf flattening + the align/fuse pass in
   `lib/src/comparison/channels.dart`, carrying the §9 facets. Pure model,
   testable with no runner.
2. ✅ `withoutIdentityHash` moved to `lib/src/utils/`, gained the two entries in
   §7, and is applied to an event's title, detail, body and every data leaf
   **before** `_capData`, which now caps per leaf. Recorder side, independent
   of 1 — and the piece with the widest reach, since the closure entry fixes a
   permanent false positive on the **tree** channel that has nothing to do with
   events.
3. ✅ `AppEvent.origin` per §8: `StackTrace.current` captured in
   `recordAppEvent` behind the `appEventBuffer` null check, symbolised in
   `AppEventBuffer.drain` so only events that survive the caps pay for it, and
   never read by the delta pass.
4. ✅ `ChannelLines` draws the deltas in the `TreeDelta` idiom it already has,
   with a `Channel lines` preview entry to look at it.

Ships as: the events channel tells you which field moved, and one class of
permanent false positive disappears from the tree channel.

### B — the artifact carries it

5. ✅ Facets and deltas into `index.json` (§10) and into
   `ComparisonCompareResult` — **before** any filter, since until this lands
   there is nothing on the MCP side to filter (§6).

Ships as: one complete, faceted record that the GUI, the MCP server, the export
and `comment.md` all read. Nothing filters yet; everything *can*.

**`ComparedItem.deltas` is the contract, built while doing it.** `index.json`
already carried the channels from A1, so what B actually needed was the *flat*
view over them — one list where a pixel fraction, a tree property, a text that
arrived and an event field that moved all wear the same five facets. A filter
asking for *events on `db` but not out of `lib/data/cache.dart`* is then three
predicates over one list rather than three predicates and a walk over four
differently-shaped ones. Two things fell out of writing it:

- **Pixels contribute one line**, carrying the fraction and the region count.
  Forced-looking until you count: without it the channel that fires most often
  is invisible to a per-channel count, and §1 of the UI note has no number to
  draw.
- **`channels` counts findings, `eventChannels` counts deltas.** A step whose
  `system` chatter moved four hundred times is *one* finding with something to
  say about events; counting deltas there would make one noisy step look like
  the whole branch. Volume is the point only in the per-subchannel breakdown,
  which is exactly where `system: 192` needs to be visible.

### C — the UI pass

Its own note. The lens presets, the verdict, the badges and the filter, all
reading B's artifact.

### Then

6. Correct §5 of `2026-08-11-worktree-comparison-design.md` in place: alignment
   is what it always specified, the mask row is a pairing key, and the
   100%-noise prediction is corrected against the measurement above.

**The rule that keeps the split honest:** C can only ever filter on facets A
recorded. That is why §9 is in this note and not in that one.
