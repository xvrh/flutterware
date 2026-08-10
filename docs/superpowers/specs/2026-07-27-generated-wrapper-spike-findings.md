# The generated per-entry wrapper — spike findings

**Date:** 2026-07-27
**Status:** Spike complete. **Succeeded**, with four corrections to the design
and one mechanism the earlier findings never mentioned.
**Tests:** the entry model's *Render order*, *Discovery* and *Enumeration*
sections, end to end.
**Follows:** `2026-07-26-s3-hot-switch-findings.md` (which proved switching with
hand-written toy libraries), `2026-07-26-widget-previews-integration-findings.md`.
**SDK under test:** `3.47.0-0.1.pre` — the reference project's current pin, two minors past the
`3.45.0-0.1.pre` the earlier findings measured.

## The question

*Render order* specified a mechanism that had never been run:

> a small **per-entry wrapper file** carrying that demo file's imports verbatim,
> imported by the accumulating entrypoint under a fresh prefix

Everything about it was designed and nothing was executed. Does a generated
wrapper compile, evaluate the annotation, render, and hot-switch?

## Verdict

**Yes, all three stages.** 16 tests green plus a live switching harness.

| stage | proves | result |
|---|---|---|
| A — `Demo extends Preview` | the annotation subclass is legal and `transform()` maps correctly | 10 tests |
| B — generated wrapper | imports carry, annotation evaluates, size/wrapper apply, entries render | 6 tests |
| C — hot switch | entries switch by reload; editing a demo mid-session works | harness |

## Corrections to the design

**1. `base class Demo`, not `final class`.** The entry model's sketch says
`final class Demo extends Preview`. `Preview` is `base`, which only requires the
subtype to be `base`/`final`/`sealed` — but `final` would **forbid a project
writing `Tablet extends Demo`**, which is precisely what `previewAnnotations`
registration exists to support. Verified: `base class Demo` compiles, and a
project subclass inherits `formFactor`/`id`/`figma` and transforms correctly.

**2. `transform()` erases Demo-ness.** It returns `super.transform().toBuilder()
.build()` — a plain `Preview`. `id`, `figma` and `formFactor` are **not readable
from the result**. The generated code must therefore hold both:

```dart
const fwDemo = Demo(name: 'Long text', wrapper: wrapInTestApp, size: kWideSize);
// fwDemo.id / fwDemo.figma          <- the annotation
// fwDemo.transform().size / wrapper <- the Preview
```

*Render order* reads as though one value carries everything. It does not.

**3. Ids must be project-relative.** The first generator emitted
`/Users/xavier/…/demo/src/team/avatar_tile.dart#avatarTileMembers`. Committing
that file would make it **machine-specific**, so the regeneration-produces-no-diff
CI check would fail for every developer. Now asserted by a test.

**4. The generator must not own the directory holding the entrypoint.** The
harness put generated wrappers and the live entrypoint in the same directory, and
regenerating cleared it — taking `main.dart` with it. The guest then threw
`NoSuchMethodError: No top-level getter 'activeDemo'` on every frame. Worth
noting the guest **kept running** while throwing 4×/second, consistent with S3's
"a broken demo does not kill the session".

## The mechanism nobody wrote down

**`reloadSources` must be given the incremental dill as `rootLibUri`.** Without
it, every reload failed:

```
{type: ReloadReport, success: false,
 notices: [{type: ReasonForCancelling,
            message: Error while starting Kernel isolate task}]}
```

The VM was trying to spawn its own kernel compiler, which `flutter_tester` has
none of. The fix is what `flutter_tools` itself does at
`run_hot.dart:1272` — pass the dill path:

```dart
await service.reloadSources(
  isolateId,
  rootLibUri: p.toUri(result.dillOutput!).toString(),
);
```

S3 reported reload timings without recording this, so it was rediscovered from
zero. It is the single most reusable line in the harness.

## The fresh-prefix rule is now structural

S3's trap was that **rebinding an existing prefix to a different library is
silently ignored**, so it mandated a fresh prefix per switch. With per-entry
wrapper files that rule stops needing enforcement:

> Each switch imports a **new file** under a **new prefix**. A prefix is never
> rebound, so the trap is unreachable by construction.

The accumulating entrypoint holds one import per entry ever visited and a
**getter** — never a top-level `final` — selecting the live one, for the reason
the widget-previews findings measured.

## Measurements

`flutter_tester`, resident `frontend_server`, SDK 3.47.0-0.1.pre.

| operation | compile | reload | result |
|---|---|---|---|
| cold compile, 780 libraries | **2043–2243ms** | — | renders |
| switch to a never-seen wrapper | 7–12ms | 66–82ms | tree changes |
| revisit a wrapper | 8–11ms | 72–76ms | `newSources=0` |
| **edit the demo while viewing it** | **5ms** | **244ms** | both the annotation *and* the widget body update |

The edit-in-place row is the real inner loop, and it was the point of the spike:
changing `name: 'Long text'` → `'Long text (edited)'` **and** a string inside the
widget both appeared after one regenerate + reload.

`size: kWideSize` — a **non-literal** annotation argument, never resolved
statically — arrived at runtime as `Size(900.0, 600.0)`, while entries with no
`formFactor` reported `size: null` for the project default to fill. That is
*Discovery*'s "literal arguments parsed syntactically, everything else deferred
to the guest", working end to end.

## Not proven

- **Not run against the reference project.** Its pub resolution is stale (June) and re-resolving
  needs a private SSH git dependency that fails in this sandbox; a `pub get`
  there would also rewrite its lockfile. The spike reproduces the reference project's *file
  shape* — a `package:` import, a relative import, demos outside `lib/` — but not
  its scale. S3 measured scale separately.
- **All three entries live in one demo file**, so a switch added one library, not
  a new demo closure. S3's +199-library case is the realistic figure.
- **`flutter_tester`, not the embedder guest** — the same gap S3 left.
- **Flutter's own previewer was never run.** The dual-host claim remains
  unverified; this spike only proves *our* host reads the annotation correctly.
- Unused carried imports produce lint noise — generated directories will need an
  analyzer exclusion. Not investigated.

## Incidental: `@Preview` churn, measured

the reference project has moved 3.45 → 3.47 since the integration findings. Diffing
`widget_previews.dart` across the two:

- **`Preview` is byte-identical.** All eight fields, `transform()`, `toBuilder()`,
  the `base` modifier — unchanged.
- **`PreviewThemeData` was rewritten**: a concrete holder of
  `materialLight`/`materialDark`/`cupertinoLight`/`cupertinoDark` became an
  `abstract base class` with `Widget apply(BuildContext, Widget)`, plus a new
  `MultiPreviewThemeData`. The library also dropped its `material.dart` and
  `cupertino.dart` imports.

So the instability the source warns about is **real and landed inside two
minors** — but it missed the extension surface entirely. The consequence lands on
*project* code that constructs a `PreviewThemeData`, not on `Demo`. The owner's
2026-07-26 call to accept the exposure now has a measured instance behind it.

## Harness

Scratchpad only; nothing committed, both repos left clean.

| file | role |
|---|---|
| `lib/demo.dart` | `Demo`/`FormFactor`, and a `Tablet extends Demo` subclass |
| `demo/src/team/avatar_tile.dart` | three `@Demo` variants, the reference project's file shape |
| `bin/gen.dart` | syntactic parse → per-entry wrappers + manifest, imports re-relativised |
| `bin/switch.dart` | resident compiler, `flutter_tester`, reload-to-switch, edit-in-place |
| `test/transform_test.dart`, `test/generated_wrapper_test.dart` | stages A and B |

Worth landing under `app/tool/` if reproducibility is wanted — the same note S3
made, now with two harnesses waiting.
