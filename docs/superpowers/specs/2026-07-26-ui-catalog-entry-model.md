# UI catalog — the entry model

**Date:** 2026-07-26
**Status:** Decided. The locked decisions below are settled; the code sketches
are illustrative.
**Supersedes:** the variant-model draft from earlier the same day, whose
decisions survive but whose API shape does not.
**Context:** master plan § "Where to pick up → A".
**Evidence:** `2026-07-26-widget-previews-integration-findings.md` (what
`@Preview` is, and the measurements), `2026-07-26-s3-hot-switch-findings.md`
(the compile loop this feeds).

## The problem, stated correctly

A widget has several states — empty, loading, populated, error, long-text, a
role variation. Two mechanisms existed, each wrong in a different direction.

**Nested maps** already gave tree-visible states:

```dart
'Avatar tile': {'Members': ..., 'External': ..., 'Empty': ...},
```

In the tree, searchable, walked by the catalog test, screenshot-able. **Nobody
used them for states**, because the declaration sits in a central file hundreds
of lines from the widget.

**`parameters.picker`** is what everyone — and every agent — actually reached
for, because it was the only way to declare states *in the demo file*. It kept
the map small and made those states invisible to the tree, to search, to the
`testWidgets` walk, and unaddressable for a screenshot.

> **The requirement was never expressiveness. It was locality: declare next to
> the widget, appear in the central tree.**

Everything below follows from taking that literally, and from the finding that
nobody — including Flutter — interprets a preview annotation statically.

## Locked decisions

1. **Entries are declared by annotation. The map is gone.** Existence comes from
   the declaration, not from registration in a central file, so "wrote a demo and
   forgot to register it" becomes structurally impossible.

2. **`Demo extends Preview`**, shipped in `package:flutterware`. It inherits
   Flutter's eight fields and adds ours. `transform()` maps the richer fields
   down to Flutter's, so **both hosts read one declaration** — Flutter's
   previewer gets a correct `Preview`, our guest gets the full instance.

3. **Named `Demo`**, not `FwPreview`. It is the vocabulary already in use — the
   directory is `demo/`, the classes are `*Demo`, `starting-ui-task` says "demo
   entry", "demo dir", "demo file". Nobody has to learn it. `CatalogPreview` was
   the fallback if collisions ever bite.

4. **One annotation, not two.** A `@CatalogEntry` companion was designed and then
   deleted: since we define the subclass anyway, `id`, `figma` and `skipInTests`
   are fields on `Demo`.

5. **Flat variants, with stable ids.** No axes-as-cross-product. Every variant
   carries an `id` distinct from its display name, so renames do not break
   agent-held references or screenshot baselines.

6. **Hierarchy is path-derived.** Display name from `name:`. rimbaud's folder
   layout already reproduces its hand-written tree.

7. **Discovery is syntactic, never resolved.** 478ms for 778 files against 17.3s
   for a *single* resolved unit. Annotation classes are recognised by
   **registration** — `previewAnnotations`, defaulting to `['Preview', 'Demo']`
   — and the class-hierarchy closure is retained as a **diagnostic only**.

8. **No auto-expansion of finite parameters. Diagnostic only.** A finite
   `picker`/`bool` is never silently promoted to a tree node.

9. **Axes are runtime, and flutterware supplies no shell and no vocabulary.**
   Projects write their own wrapper with whatever concepts they have — theme,
   flavour, feature flags, auth. Our obligation is only that axes are
   *enumerable* and *settable by name*.

10. **`FormFactor` is the existing published enum, extended** — not a second
    concept.

## The shape

```dart
// package:flutterware
enum FormFactor {
  mobile(Size(390, 844)),
  desktop(Size(1440, 900)),
  all(null);
  const FormFactor(this.size);
  final Size? size;
}

final class Demo extends Preview {
  const Demo({
    this.formFactor = FormFactor.mobile,
    this.id,
    this.figma,
    super.name, super.group, super.size, super.wrapper,
    super.theme, super.brightness, super.localizations,
  });

  final FormFactor formFactor;
  final String? id;
  final String? figma;

  @override
  Preview transform() {
    final b = super.transform().toBuilder();   // @mustCallSuper
    b.size ??= formFactor.size;                // an explicit size still wins
    return b.build();
  }
}
```

```dart
// demo/src/desktop/developer_console/list/environments_table.dart
@Demo(name: 'Environments table', formFactor: FormFactor.desktop, figma: 'node-id=1:234')
Widget environmentsTable() => EnvironmentsTable(rows: mockRows);

@Demo(name: 'Empty')
Widget environmentsTableEmpty() => EnvironmentsTable(rows: const []);
```

Variants are stacked annotations, a `MultiPreview` subclass, or separate zero-arg
functions — whichever reads best. Each is a real, independent tree leaf:
addressable, searchable, screenshot-able, walked by the test loop. The parent
node is an ordinary folder that additionally renders a **contact sheet** of its
children's screenshots — thumbnails, which works for full-screen entries where
stacking ten live `Scaffold`s would not.

The const-constructor restriction is why the `FormFactor` → `Size` mapping lives
in `transform()`. That is exactly what the hook exists for, per the SDK's own
rationale, and **both** of Flutter's code-gen paths call it.

## Addressing

```
entry           →  path + symbol           (identity; the id: field pins it)
variant         →  a sibling entry, not a sub-concept
axes            →  applied assignment, e.g. {theme: dark, locale: fr}
```

Global axes (theme, locale, device, text scale) are applied, never expanded into
the tree — expanding them would multiply every leaf by themes × locales.
`@Preview`'s `brightness:` and `localizations:` are read as **the entry's default
axis assignment**, not as immutable context, so the two models compose.

This is the entry address the manifest needs, and it answers master-plan open
question 5 for the catalog: *"screenshot an entry" is under-specified without the
variant and the resolved axis assignment.*

## Discovery

One syntactic parse pass, two outputs from the same traversal:

1. every annotation usage with its target declaration;
2. every `class X extends Y` edge.

Entry recognition uses (1) filtered by the registered annotation names. Filtering
to top-level functions returning `Widget`/`WidgetBuilder` discards the noise
immediately — 2180 `@override`s in rimbaud, against a handful of candidates.

(2) feeds a transitive closure from `{Preview, MultiPreview}`, used **only** to
report omissions:

> `Tablet extends Preview` is used as an annotation on 12 declarations but is not
> listed in `previewAnnotations`.

Registration stays authoritative and deterministic; inference exists so a
forgotten registration does not silently delete entries. This is the third use of
the same posture in this design — unexpanded pickers, unmatched form-factor
globs, unregistered annotations — and the rule it encodes is worth stating
plainly:

> **The tool never guesses, but it always reports what it noticed.**

**Literal annotation arguments are parsed syntactically** (`name: 'Members'` is a
string literal); everything non-literal is deferred to the guest. So the tree has
display names before anything is compiled, and `size: kSomething` still works
without any resolution.

## Render order, in the guest

Semantics are never interpreted statically. The generated per-entry wrapper emits
the annotation's source text and evaluates it:

1. `const Demo(...).transform()` → a real `Preview`.
2. `preview.size` → configure the view / `MediaQuery`.
3. `preview.wrapper` → wrap.
4. `preview.theme` / `brightness` / `localizations` → apply as axis defaults.
5. build the widget from the annotated function.

All before the first frame, and costing only the entry's compile — which
rendering requires regardless. `size` is nullable, so a **project-level fallback
default** applies when the annotation is silent; Flutter's previewer has its own
fallback, and the two never conflict because ours only fills a gap.

**Mechanism note.** The annotation is written in the demo file's import scope, so
generated code must see `Demo`, `FormFactor`, and any project-local wrapper.
Cleanest route: a small **per-entry wrapper file** carrying that demo file's
imports verbatim, imported by the accumulating entrypoint under a fresh prefix —
which preserves the fresh-prefix rule S3 established.

## Axes, knobs, and degradation

`parameters.*` keeps its honest role: **free knobs for exploration** — `string`,
`num`, `dateTime`, `button`, transient interactive flags. Cases where rendering
every value at once is impractical. It stops being where states live.

The degradation that makes multi-host work **already ships**: `Parameters`
returns `defaultValue` from every method, and `UICatalogState.of()` falls back to
`UICatalogState.empty`. `ui_catalog_test.dart` already relies on it.

| | our host | Flutter previewer | `flutter test` |
|---|---|---|---|
| entry, size, wrapper, theme | yes | yes | yes |
| knobs / axes | interactive | no-op defaults | no-op defaults |
| device frame, orientation, mosaic | yes | no | no |
| `id`, `figma` | yes | ignored | available |
| screenshots, driving, tree dump | yes | no | partial |

## What this deletes

- **The catalog map.** Hierarchy comes from paths; existence from declarations.
- **`@CatalogEntry`.** Folded into `Demo`.
- **Path-glob form-factor config as the primary mechanism.** It solved verbosity
  but is invisible to Flutter's previewer, so it cannot carry render-affecting
  defaults. Retained only as a convenience for projects that do not want the
  second host.
- **The resolved analyzer pass**, and with it the `byteStore` persistence and
  multi-root sharing designs. `package:analyzer` is needed as a *parser* only.
- **A flutterware-provided `DemoApp` shell** and any typed axis vocabulary. The
  consumer is an LLM, which reads names: an axis called `Language` with values
  `en/fr/nl` is self-describing.

## Preserved

- **The existing catalog app is kept, not replaced.** It is the published API,
  it is what compiles to web for per-PR catalog links, it is the real-device path
  (each demo file already has its own `main()`), and it is the fallback wherever
  the embedder has no port. The flutterware GUI is an *additional* renderer.
- **The catalog stays enumerable from a plain `flutter test`** — see below.

## Enumeration in `flutter test`

**Discovery is not the blocker; invocation is.** Dart has no runtime reflection
over annotations and no dynamic import, so knowing that `environmentsTable` lives
in some file yields a string that cannot be turned into a call. A scanner
embedded in the test would buy nothing — and a scanner in `package:flutterware`
would violate decision 9 besides, since every user's app inherits its
dependencies.

Generated code is therefore the only mechanism, which is why Flutter generates
`generated_preview.dart` and widgetbook generates
`widgetbook.directories.g.dart`. Neither found a way out.

**The cost is smaller than it first appears, because the artifact already
exists.** With the map gone, the per-PR web build needs exactly what the test
needs: every entry, imported and invocable. So the test adds no generator — it
reuses one:

| consumer | entrypoint |
|---|---|
| daemon inner loop | accumulating, lazy — only visited entries |
| web PR build | full — every entry |
| `flutter test` | full — the same file |

**Decision: commit the full generated file**, produced by a CLI command
(`fw catalog gen`) that CI also calls before the web build, and guard it with a
regeneration-produces-no-diff check — reusing the guard rail
`dart tool/prepare_submit.dart` already establishes in `.github/workflows/`.

Rejected alternative: generating on demand into a gitignored `.dart_tool/` path.
It is never stale, but bare `flutter test` stops working, the IDE's per-test run
button breaks, a fresh clone fails, and the failure surfaces as a compile error.
The CLI command is wanted either way; committing its output is a decision about
the artifact, not the mechanism.

The staleness window is narrow: the file lists `(id, name, path, () => fn())` and
changes only when an entry is **added, removed, or renamed** — never when a demo
body is edited. It stays out of the way during normal UI work, which is where
diff noise would actually hurt.

*Later convenience, not part of the design:* the test could assert its own
freshness by comparing the generated list against a syntactic scan at test time
(scanner as a project **dev**-dependency — dev-only, syntactic, ~478ms), failing
with "run `fw catalog gen`" instead of quietly covering fewer entries than exist.
Redundant with the CI check, which catches the same thing one step later.

## Deferred

- Axes swept as independent dimensions (`4+4` leaves rather than `16`).
- A typed axis vocabulary, for deterministic consumers such as a CI screenshot
  matrix. Waits for evidence.
- Auto-expansion of finite pickers as a per-demo opt-in migration bridge.
- Moving `Demo` to a companion package if `@Preview`'s instability starts to
  hurt. Nothing in the design depends on where it lives.

## Open

1. **Ordering.** Path-derivation is alphabetical; the old map's order was
   deliberate. Is a small ordering file worth it on day one, or does alphabetical
   survive?
2. **Does `FormFactor.mobile` split into `phone` / `tablet`?** Additive, and much
   cheaper before projects have written it a few hundred times.
3. **Contact-sheet layout** for parent nodes mixing component-sized and
   screen-sized children.
4. **Migration** for the ~300 existing rimbaud entries: diagnostic-driven, or a
   codemod? (Owner, 2026-07-26: "we'll see.")
5. Whether `id:` should be required rather than optional, given that without it
   identity falls back to the symbol name and renames break references.
