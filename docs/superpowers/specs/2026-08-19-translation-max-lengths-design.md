# Translation max lengths — how long a translation can get, measured before it exists

> **Built 2026-08-19**, then **reworked the same day after the owner's read**
> — the review renamed the deliverable, deleted the user-facing input, and
> gave the measurement its own device. What changed and why is in *What the
> review changed*; the mechanics underneath survived intact. The measured
> numbers from both builds are at the end.

2026-08-19. Gated on a spike run the same day against `examples/example`
(throwaway, deleted; every number below says how it was measured). Builds on
`2026-08-18-translation-index-design.md` — the index, the funnel, the export
and the panel are all assumed.

## The goal

The most common localization defect is a translation that does not fit:
written against a spreadsheet, shipped, and discovered clipped in one
language's QA — per language, per revision. The index already *observes* this
after the fact, and the P4 findings audit cut that report for noise: 37% of
sightings on a real suite ellipsize, and nothing can tell a designed ellipsis
from a bug.

This feature inverts the question. Instead of asking "did this clip?" after a
translation exists, it asks **"how long can this string get?"** — measured on
the real screens, once, in the source language, and true for every language
and every future revision at once. The deliverable is the field every
translation platform already has and almost none can fill honestly:

**`maxLength`, in characters, per key — with the experiment that proved it.**

## Decision 1 — intervention, not observation (owner, 2026-08-19)

Everything the translation tooling does today is observational, and the index
design rejected every inference mechanism (template matching, source reading)
because inference has a false-positive rate. A max length cannot be observed
at all — no run of the real catalog says what *would* have fit — but it can
be **measured by experiment**: pad the value, render, see what breaks. An
intervention is causal, so every answer stays a fact, which is the bar
everything in this design has to clear.

The instrument already exists. Every read goes through the funnel
(`wrapValue` → `TranslationIndex.record`), so padding applied in `record`
reaches every rendered string with **zero changes in consumer catalogs** —
the padded value gets its own token, and identity resolution works on it
unchanged (spike-verified, including on a composed string that identity
itself cannot resolve).

Two facts about the funnel, both owner corrections, shape everything below:

- **Targeting reads through the funnel too.** Scenarios are written to run
  under every language — `tap(translations.addToCart)`, never a literal — so
  padding applied *before the run* changes the finder's needle and the
  rendered text together, and the whole suite runs padded, unchanged.
  A probe pass is just another locale.
- **Imperative reads only see pass-scoped padding.** A dialog reads its
  string at call time; nothing re-reads it on a later frame. Padding armed
  before the run reaches it (the funnel is hit at the natural moment); a
  mid-step mutation does not. So every probe is **per pass, never per step.**

## Decision 2 — a ladder of batch passes, not a per-key search (owner, 2026-08-19)

Two ways to find a limit:

- **Bisect one key**: at a captured step, binary-search the padded length
  until the clip signal flips. Character-exact, and priced per key.
- **Batch a level**: pad *every* key by the same percentage in one pass-scoped
  run, and read which sightings flipped. Priced per pass, **independent of
  key count** — and each global percentage still tests a *specific character
  count per key* (a 25-char string at +20% renders at 30), so a ladder of
  levels gives every key a character bracket whose width is ~one rung.

The spike measured the bisect so the choice is on numbers rather than taste
(`examples/example`, menu screen, automated test binding, wall clock):

| | measured |
|---|---|
| override + reassemble + pump, per cycle | **9.1ms** (mean of 30) |
| locate paragraph + read flip signal | 0.14ms |
| full bisect of one key | 7 iterations, **64ms** |

64ms per (key, box) is fine for 22 keys and is not fine at scale: it
multiplies by key count *and* by reassemble cost, which grows with tree
size. A batch pass costs one captureless suite run whatever the catalog
holds — measured at **~0.2× the export pass**. So the build is batch-only;
the bisect is shelved with its numbers (see *Deferred*) until someone needs
character-exactness the ladder's rung width does not give, and two of its
traps are pinned for whoever picks it up: `reassembleApplication()`'s future
completes only after a frame renders, so it must be pumped *while* awaited —
awaiting first deadlocks the test binding — and the restore guard works
(after five probes, clear + reassemble reproduced every paragraph's text,
size and offset exactly).

Batch has one more property the bisect lacks: it is the *honest* whole-app
measurement. Everything grows at once, exactly as a verbose language would,
so keys competing for the same Row are measured competing.

## Decision 3 — the user gives no numbers (owner, 2026-08-19)

The first build took expansion levels as input (`budgets: 15,35,70`) and
reported per-key brackets in those terms (`clipsAt: 35`). The owner's read
killed both, for the same reason: **the percentages are implementation, and
they leaked.** "Budget" is nobody's vocabulary and "+35%" answers a question
no reader asked. What a translator, a push script and a reviewer all want is
the field the platforms already have: a max length in characters.

So the surface is now:

- **Input: a flag.** `max-lengths` on the export action, no value. The tool
  runs its own internal ladder (ten even rungs of each key's ceiling — see
  the 2026-08-21 amendment below — a constant in the code, not API) and
  **stops early** once every measurable key has clipped or the ladder is
  exhausted.
- **Output: characters.** Per key, `maxLength.chars` — defined precisely as
  **the longest string proven to fit this key's tightest box**: a padded
  string of exactly that length actually rendered there without clipping.
  Proven-fits is the conservative bound, which is the right direction to be
  wrong in, and the rung width (~10% of the string) is visible in the
  evidence rather than hidden in rounding.
- A key that never clipped up to the cap still gets its proven bound — the
  block carries `chars` with no `clips` half, and every surface reads it as
  "at least N", never as a limit. Unmeasured stays absent: blank must never
  read as room.

Percentages survive on exactly one surface: `findings.expansionBreaks`, the
screen-level report ("this screen breaks when text grows ~40%"), because a
whole screen has no single string length to count in characters.

### Amendment: the ceiling scales with the string (owner, 2026-08-21)

The first ladder topped out at +100% for every key, and the owner caught what
that buys on a short string: an 11-character label reported "at least 22" —
a bound far below where its real limit plausibly sits, since localisation
guidance is unanimous that short strings expand disproportionately (a
6-character button can triple; a 70-character sentence grows by a third).

The fix is not more rungs — every rung is a suite pass, and stretching the
ladder to +300% for *everything* would also blow up whole screens with
sentences at triple length, drowning the per-key signal in expansion breaks.
Instead **the ceiling is a function of each value's own length**
(`TranslationIndex.expansionLength`): at the top rung a value ≤10 characters
is padded +300%, ≤20 → +200%, ≤30 → +150%, ≤50 → +120%, longer → +100%. The
ten rungs each take a tenth of the key's own ceiling, so the pass count — and
the cost — does not move, and every key is probed about as far as *it* can
plausibly go. The wire's `expand` argument is accordingly a **rung in
[1, 100]**, not a literal percentage; `record`, the report's reconstruction
and the tests all size the padding through the one shared function.

First run on the example: the 11-character `placeOrder` moved from "≥ 22" to
"≥ 33", and two real limits surfaced that the flat ceiling could never
reach — `menuTitle` ("The menu", 8 chars) clips at 23 on `iphone-se` and
`yourOrder` ("Your order", 10 chars) clips at 28, both beyond the old
ladder's maximum stretch. Cost moved from 17.0s to 21.6s on the example,
because more rungs now do real work before the early stop.

## Decision 4 — the number carries its experiment (owner, 2026-08-19)

A bare `29` invites "says who?". The runs *are* the receipts, and the padding
is deterministic, so the report reconstructs character-for-character what
each pass rendered. The block per key:

```json
"maxLength": {
  "chars": 29,
  "fits":  { "text": "Warm spices, creamy milk. wor",      "chars": 29 },
  "clips": { "text": "Warm spices, creamy milk. word le…", "chars": 34 },
  "screen":  { …baseline shot of the box, probe device… },
  "clipped": { …shot of the padded string actually clipping… },
  "measuredOn": "pixel-4a"
}
```

`fits` and `clips` are the literal strings that were drawn; the viewer
renders them as a sentence — *"29 characters fit on Menu (pixel-4a); 34 were
cut off"* — which states the whole inference method where the number is.

**The clip screenshot is captured, under the flag only.** The ladder is
captureless, so the clipping frame is never written by it; after aggregation,
one *captured* pass runs per distinct level at which keys first clipped, and
the constraining cells' frames become `clipped` shots. The exporter copies
only referenced frames, so the extra pass costs its run time and nothing in
the output directory beyond the evidence itself.

## Decision 5 — the measurement has its own device (owner, 2026-08-19)

A max length measured on a roomy device is a *wrong* number, not a less
precise one: it over-promises and the small phone clips anyway. The export's
`device` chooses what the translator's screenshots look like; the probe's
geometry is a different question with a different right answer, so it is a
separate axis:

- **`max-length-device`**, when the user names one, applies to every probe
  pass.
- **Default: the narrowest device each scenario's folder profile declares.**
  Not the smallest phone in the device table — probing a device the project
  never claims to support would manufacture false-tight limits, the same trap
  the representative-ranking work documented from the other side. The folder
  profiles are the project's own statement of what it runs on (declared
  vocabulary, never guessed — the flavor rule again), and per-folder means a
  desktop-only folder probes at its own smallest window rather than at a
  phone it never claims. On the wire this is `deviceChoice: narrowest`,
  honoured by the harness where the folder-profile framing already happens.

**The probe therefore runs its own baseline, on its device.** The exclusion
rule below compares probe against baseline *on the same geometry* — a string
clean on the screenshot device may already ellipsize on the probe device, and
pairing against the wrong baseline would misread that pre-existing clip as a
flip at the first rung. The probe baseline is one captured pass (it also
supplies the `screen` evidence shots, so the box and the clip are pictured on
the same device).

Deferred on this axis, deliberately: probing several devices and taking the
per-key minimum (the machinery allows it; "narrowest declared" already is the
binding device in almost every real layout, and `measuredOn` means a
single-device number never lies about its scope), and a text-scale axis (a
user with large system fonts is the other "representative worst case"; same
knob family, measured when someone asks).

## The flip signals, and what each is worth

- **`didExceedMaxLines`, per paragraph.** Already captured on the walk
  (`InspectNode.textOverflowed`), already attributed to its key by identity —
  which the padded token preserves. The comparison is *clean at the probe
  baseline, clipped under padding*: that key's limit is at that rung, on that
  screen. A sighting clipped **at the probe baseline** is excluded from its
  key's measurement — it ellipsizes today by someone's choice, and the audit
  already established no signal can litigate that choice.
- **RenderFlex overflow, per screen.** Catchable by swapping
  `FlutterError.onError` for the probe's duration (spike-verified: caught
  "overflowed by 1144 pixels", leaked nothing into the test, restored
  cleanly). It is a *screen-level* fact — under batch padding many keys moved
  — so it reports as an `expansionBreaks` finding with its step, not as any
  key's limit. Two spike measurements say why it is never a per-key signal: a
  363-char CTA **fit** both an 800×600 surface and a 390×844 phone (the
  button wrapped to 1552px and a Spacer absorbed it; overflow needed 1452
  chars). Vertical flex is a far laxer constraint than an ellipsis.
- **A scenario red under padding** is the third signal, not a broken run:
  "this suite cannot complete under +40% growth" is fragility the report
  states with the failing scenario. The harness's probe mode downgrades
  overflow-triggered failures to per-step data; any other failure reports as
  itself.

## The mechanics

**Padding, in `record`.** `TranslationIndex.expandPercent`, armed by the
harness per request from `ScenarioRunArgs.expandTranslations` (wire:
`expand`). The padded token is minted like any other, so identity attributes
it; **the padded value must never reach `TranslationIndex.read`** — that map
is what the export's `disagrees` compares against the files (same shape as
the existing `expansion: true` rule). Expansions pad too: the built string is
the one on screen. Padding is `ceil(len × level / 100)` with a floor of 2,
sliced from a fixed alphabet at an offset hashed from the key (FNV-1a —
`String.hashCode` is not promised stable and the padding must be, because
determinism is load-bearing: two probed exports are byte-identical, pinned by
diff). Per-key-distinct padding costs nothing and is the one provision the
attribution follow-up needs from this build.

**Captureless passes.** `format: none` on the run action →
`ScenarioRunArgs.capturePixels: false` → the step emits with no
rasterization and no encode; tree, keys and texts are written as ever.
Measured at ~0.2× the capture pass it rides beside.

**The run, under the flag.** One captured probe baseline (probe device), the
captureless ladder with early stop, then one captured evidence pass per
distinct first-clip level. All source-language; the translator-screenshot
run is untouched.

**Aggregation** (`app/lib/src/translations/max_length.dart`). The pairing
unit is a sighting cell — (scenario, step index, key) — sound because
FakeAsync determinism makes two runs capture the same steps. A cell flips
when the probe shows more clipped sightings in it than the probe baseline
did (so a step with one designed ellipsis and one clean sibling still
measures the sibling). A cell the probe never reached — a diverged scenario
— pairs with nothing and attributes nothing; fail closed, never "fits". The
constraining pick is order-independent (sorted, the representative-ranking
rule). `fits`/`clips` texts are reconstructed from the value the catalog
answered plus the rung's padding — for a key that substitutes, that is the
template value, which is approximate by construction and documented as such.

**The export.** Root `maxLengths: {devices: […]}` (present only when the
probe ran — absence of a probe must stay distinguishable from a probe that
found room), the `maxLength` block per measured key, `expansionBreaks` in
findings. Version stays 1; added fields do not bump it.

**The panel.** A `Max length` column behind the same gate as the picture
column (probed or no column): `≤ 29 ch` for a proven limit, `≥ 43 ch` muted
for an open bound, blank for unmeasured — and **amber when an existing
translation already exceeds the proven limit**, which is a finding only the
measurement can produce. The `fragile` filter selects keys with a proven
limit. The open row's detail states the evidence sentence and shows the
`clipped` shot beside the baseline one.

**The panel's Export button is a split button** (owner, 2026-08-21 — same
anatomy as the scenario panel's Run button): the primary segment exports
with whatever is ticked, the chevron holds one toggle, *Measure max
lengths*. The setting follows the export on disk until the user says
otherwise (`TranslationsCore.measureOnExport`), so by default the button
**reproduces what the panel is showing** — before this, one click on a
probed table re-ran the plain export and silently wiped its own Max length
column. The label says which export a click buys (`Export` vs
`Export + measure`), because the two differ by minutes; while it runs, the
strip narrates the core's busy line ("measuring max lengths — +40%…")
instead of a silent spinner.

## The gates

1. **Sanity on the example.** The one tight drink description gets a
   character limit with its menu shot; freely-wrapping copy reports an open
   bound; deliberately-ellipsized baseline sightings are excluded rather
   than measured.
2. **Consistency with the observed clips.** Any existing translation longer
   than its key's proven limit must be one that actually clips — the
   self-validation only this mechanism can run.
3. **Cost.** The flag's total (baseline + ladder + evidence) on the example
   stays within ~3× the plain export; the ladder's captureless discount is
   re-measured, not assumed.
4. **Determinism.** Two probed exports byte-identical, by diff.
5. **Usefulness, eyeballed by the owner on a real consumer suite** — is the
   max-length column the number you would paste into a translator's brief,
   and does the evidence sentence answer "how do you know" without a second
   question. The ladder constant is blessed (or resized) only after this.

## Open, deliberately

- Whether the roomy keys' `≥ N ch` cells should render at all, or only the
  proven limits — the first build showed a wall of open bounds reads as
  noise; the consumer reading decides.
- The ladder constant (currently +10%…+100% step 10) and the early-stop rule
  are internal and expected to move with measurement.

## Deferred

- **The exact-character bisect.** Proven and priced by the spike (9.1ms a
  cycle, 64ms a key; scales with key count × tree size; pump-while-awaiting
  or it deadlocks). Ships only if a rung-width bracket is ever not enough,
  runs on the proven-limit subset only.
- **Attribution — naming the keys identity loses.** The same probe passes,
  read for text *diffs* instead of clip flips: a node whose words changed
  under padding is catalog-derived through any transformation, and
  per-key-distinct padding names which key — causally, no template matching.
  Its own design and its own audit (marker survival under transforms,
  ambiguity fail-closed, provenance for experiment-deduced occurrences).
  This build's only obligations — distinct padding, probe artifacts a second
  reader can consume — are in the mechanics above.
- **Multi-device minimum and a text-scale axis** — see Decision 5.
- **Step-scoped injection generally** (a playground row-editor, live
  edit-and-see): needs the reassemble machinery; nothing here blocks it.
- **Glyph-realistic padding per target language.** The fixed alphabet
  measures Latin-ish growth; a CJK or Thai limit wants different metrics.

## What the review changed (owner, 2026-08-19)

The first build shipped the engine right and the surface wrong, and the
owner's read corrected the surface in three moves, each recorded because
each is a rule worth keeping:

1. **"Budget" and brackets-of-percentages died; characters won.** The
   deliverable is the field the platforms have — max length, in characters —
   and the implementation's percentages are as invisible as the capture
   scale. *Do not let the mechanism name the deliverable.*
2. **The input died.** `budgets: 15,35,70` asked the user to tune the
   experiment; the tool now picks its own ladder. *A measurement tool that
   asks for its parameters is shipping its internals.*
3. **The number gained its experiment and its device.** A viewer is "dying
   to know how you inferred that" — so the tested strings ride the block,
   the clip is photographed, and `measuredOn` scopes the claim to the
   geometry it is true for, which the probe now owns (narrowest declared per
   folder, its own same-device baseline). *A measured claim states its
   method and its frame, or it reads as an opinion.*

## What the builds measured

First build (levels API, `15,35,70`, no evidence shots), through the shipped
action on the example:

| | |
|---|---|
| export, no probe | 4.6s |
| export + 3 captureless probe passes | 7.2s — ~0.9s a pass, ~0.19× the export pass |
| keys measured | 20 of 22 (the two unseen keys correctly absent) |
| the one real limit found | `drink.chai`, constraining shot the menu |
| determinism | two probed exports byte-identical, by diff |

The chai row was the feature in one line, twice over: its English is 25
characters in a box with ~15% of slack; its French is 30 — and the French
*does* ellipsize on the menu today. The measurement, run on English screens
alone, predicted the observed French clip (gate 2, passing on the shipped
path). The exclusion rule also showed its face: the other drink descriptions
ellipsize on the menu *at baseline*, so their measurement came from the
drink screen where the text wraps, and read as open bounds — correct, and
the reason the roomy-cells question is in *Open*.

The rework, through the shipped action on the example (`max-lengths: true`,
no device named):

| | |
|---|---|
| export, no probe | 4.6s |
| export + probe baseline + full ladder + evidence | **17.0s** — ~3.7× |
| keys measured | 20 · **1 real limit**, 19 open bounds |
| devices, picked per folder | `iphone-se` (mobile), `windows-window` (desktop) |
| determinism | two probed exports byte-identical, by diff |

Slightly over the gate's ~3× guess, and honestly so: 19 of 20 keys never
clip, so the ladder ran all ten rungs (the early stop only fires when
everything has clipped), plus two captured passes — the probe baseline and
one evidence level. The ladder constant is the knob if this ever matters.

**The device axis earned itself on its first run.** The narrowest-declared
default picked `iphone-se` for the mobile folder — narrower than the
`iphone-16` the first build measured on — and the chai limit tightened from
"~28 fits" to **"only the current 25 characters fit; 28 clips"**. Its French
is 30. So the panel's amber cell, the sentence — *"Measured: 25 characters
fit on Menu (iphone-se); 28 were cut off. The fr text is already longer than
the limit."* — and the photographed clip all fired on a real defect the
looser geometry had understated: exactly the over-promise Decision 5 exists
to prevent, caught by its own first measurement.

One reading worth pinning: an open bound's `measuredOn` names whichever
clean cell the deterministic order picked (the example's desktop scenario
sorts first), which is honest — the key fit everywhere it was seen — but
means only *bounded* rows carry a device worth reasoning about.

One trap for whoever touches `index.dart`: the token map's separator is a
literal NUL (`'$catalog\0$key\0$value'`), invisible in most editors and
skipped by `grep -I`-style sweeps — an edit that respells it with a space
changes every token key and no test says why.
