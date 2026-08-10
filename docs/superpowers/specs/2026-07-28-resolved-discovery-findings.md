# Resolved discovery: findings

> **Outcome: rejected, and the need removed instead.** The measurements below
> stand and are worth keeping — the 17.3s that ruled resolution out was a
> cold-cache artifact, and that correction is real. It was still rejected, on
> the two costs a warm cache does not help: **~19s the first time a project is
> opened**, and **164MB of store per project root**, neither of which is shared
> between worktrees of the same repo. Against a tool whose promise is that
> opening a worktree gets you a running demo quickly, that is the wrong trade.
>
> What resolution was going to buy — dropping `@CatalogShell`, reading axis
> values statically, and killing the scope reconstruction in
> `_carriedImports` — was obtained instead by declaring axes at runtime and
> parsing the imports we already parse. See
> `2026-07-27-top-bar-axes.md`. Revisit this document if a future need
> genuinely requires resolved facts; do not revisit it for discovery.

Spike: `app/tool/catalog/resolve_spike.dart`. Run as

```sh
cd app
fvm dart run tool/catalog/resolve_spike.dart . tool/catalog/demos --store file --clear
fvm dart run tool/catalog/resolve_spike.dart /path/to/project demo --store file --edit
```

## The headline

**The 17.3s that ruled resolution out was a cold-cache artifact.**
`2026-07-26-widget-previews-integration-findings.md` measured
`AnalysisContextCollection` with its default `MemoryByteStore`, which links the
whole transitive closure from nothing on every run. Given a byte store that
survives the process, the same work on the same project costs **1.8s**.

`AnalysisContextCollectionImpl` takes a `byteStore:`; the public
`AnalysisContextCollection` constructor does not. That one implementation
import is the whole difference.

## Measurements

the reference project's web-app package, 40 units resolved — the same project and the same
order of magnitude as the original 17.3s.

| | first unit | remaining 39 | total |
|---|---|---|---|
| cold (empty store) | **18 815ms** | 3 693ms (95ms each) | 22 508ms |
| warm (own store, 164MB) | **1 823ms** | 448ms (11ms each) | 2 271ms |
| the IDE's `~/.dartServer` store | 19 761ms | 4 058ms | 23 819ms |

`app/tool/catalog/demos`, 9 units — a small closure, for contrast:

| | first unit | remaining 8 | extraction |
|---|---|---|---|
| cold | 5 290ms | 30ms | — |
| warm | **509ms** | 9ms | 62ms |

**Incremental, in one long-lived process** — edit a file, apply the change,
re-resolve *and* re-extract everything:

| project | edited file | round 1 | round 2 | round 3 |
|---|---|---|---|---|
| fixtures | `shell.dart` (7 dependents) | 10ms | 2ms | 217ms |
| reference | `demo/_main.dart` (leaf) | 79ms | 0ms | 2ms |

Every round reported the correct 9 entries / 2 shells and saw the edit.

So the shape is: **one warm-up of ~2s per session, then single- to
low-hundreds-of-ms per save.** The syntactic parse stays 14–89ms, which is what
the tree is drawn from.

## What resolution buys

Measured on the fixtures, with `@CatalogShell` never read:

- **Shells need no annotation.** `wrapper: wrapInApp` is a tear-off whose
  static type is `WidgetWrapper` = `Widget Function(Widget)`, which erases the
  named parameters. `DartObject.toFunctionValue()` recovers the
  `ExecutableElement` anyway, and its `formalParameters` *are* the axes. The
  spike found both fixture shells, with the same axes the annotated scan finds.
- **Axis values are known before anything runs.** `flavor: Flavor = dev [dev,
  staging, prod]`, `loudness: Loudness = quiet [quiet, loud]`. Today the type
  name is all the scan has, and `<Type>.values` has to be compiled into the
  guest and reported back. `EnumElement.constants` answers it statically, so
  the top bar can be drawn before the first compile.
- **Annotation arguments are values, not source text.** A demo written
  `@Demo(name: _kName)` — a private const in the demo's own library — extracted
  as `From a private const`. Today's generator copies the annotation's source
  into another library, where `_kName` does not exist and the wrapper does not
  compile.
- **`formFactor` is read, not guessed.** `_enumName` currently takes the last
  identifier of the argument's source text.
- **Recognition is by hierarchy.** `_isDemo` walks supertypes, so a project's
  `base class Tablet extends Demo` is found with no `previewAnnotations`
  registration list and no bare-name matching.
- **`_carriedImports` disappears.** Imports come from element library URIs
  under prefixes the generator mints, so there is no directive regex, no
  relative URI to rebase, and no prefix collision between the demo's imports
  and the shell's:

```dart
import 'tool/catalog/demos/avatar_tile.dart' as p0;
import 'tool/catalog/demos/shell.dart' as p1;

Widget Function() get fwBuilder => p0.avatarTileMembers;

Widget _fwWrapInShell(Widget child) => p1.wrapInApp(
  child,
  flavor: CatalogAxes.instance.pick('flavor', p1.Flavor.values, p1.Flavor.dev),
  compact: CatalogAxes.instance.flag('compact', false),
);
```

## Constraints the spike hit

These are not opinions; each one cost a debugging round.

- **Elements do not survive a file change.** A `LibraryElement` captured before
  an edit throws `Invalid argument(s): Missing library: …` when read after it.
  Resolution must therefore **extract to plain data inside the same sweep that
  produced it** — which is what `CatalogEntry` and `ShellDescriptor` already
  are. The existing scan → immutable descriptors → generator pipeline is the
  right shape; resolution is a better *source* for the descriptors, not a
  different architecture.
- **A broken demo does not poison the others.** A demo whose body is
  `ThisTypeDoesNotExist(count: nope)` still yielded a complete, correct entry —
  name, shell, axes — and the other 11 entries were unaffected. Resolution
  degrades per file, the same way the compiler does. The catalog's existing
  quarantine story survives.
- **`FileByteStore` does not create its own directory.** It writes a temp file
  straight into the path and swallows the failure, so a missing directory makes
  the store a silent no-op that looks exactly like a cache that never helps.
  This cost one full round of "the cache does not work".
- **Its writes are fire-and-forget.** `putGet` schedules the write and returns;
  nothing awaits it. A daemon outlives that. A one-shot process exits with an
  empty cache and concludes, wrongly, that caching does nothing. The spike
  waits for the store to settle (~0.5s for 33MB, ~2s for 164MB).
- **The IDE's cache is not reusable.** Pointing at
  `~/.dartServer/.analysis-driver` — 4.1GB, warm, same project — hit *nothing*:
  19 761ms, indistinguishable from cold. The keys carry the analysis server's
  own analyzer version. Worse, it wrote 164MB of our entries into the IDE's
  store. **Keep our own cache; do not touch that directory.**
- **Excluded files have no context at all.** `analysis_options.yaml` excludes
  `does_not_compile.dart`, so `contextFor` throws `StateError` rather than
  returning an empty result. The syntactic scan lists such a file happily, so
  the two passes disagree about what exists and the disagreement has to be
  designed for.

## The shape this was going to point at

Recorded as it stood before the decision above, because it is the design that
would be right *if* the two costs ever stop mattering:

1. **Listing stays `parseString`.** 14–89ms, total, tolerant, no cache needed.
2. **Resolution warms in the background at session start**, into a flutterware-
   owned store under `~/.flutterware/analysis-cache/<project>`.
3. **Running an entry waits for resolution** — no fallback to a syntactic
   generator, because two code paths producing subtly different wrappers is a
   worse failure than a progress indicator.
4. **Each sweep extracts to `CatalogEntry` / `ShellDescriptor` immediately**,
   because elements do not survive the next edit.

Never measured, and would have to be before any of it: memory held by a warm
context on a large project, and behaviour when the analyzer flutterware pins is
older than the project's SDK.
