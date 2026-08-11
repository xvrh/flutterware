# UI catalog — the entry model

**Date:** 2026-07-26
**Updated:** 2026-07-27 — four of the five open items resolved; axis enumeration,
the config split and the canvas boundary settled; the closure cut;
the evidence behind the problem statement corrected; the render path built.
**Status:** Decided. The locked decisions below are settled; the code sketches
are illustrative.
**Supersedes:** the variant-model draft from earlier the same day, whose
decisions survive but whose API shape does not.
**Context:** master plan § "Where to pick up → A".
**Evidence:** `2026-07-26-widget-previews-integration-findings.md` (what
`@Preview` is, and the measurements), `2026-07-26-s3-hot-switch-findings.md`
(the compile loop this feeds), `2026-07-27-generated-wrapper-spike-findings.md`
(the render path, built and measured — it corrected four things below).

## Verified against SDK source

`widget_previews.dart`, SDK 3.45.0-0.1.pre. The sketches below compile against
real API, not against a reading of the docs:

| claim | line | status |
|---|---|---|
| `Preview` is subclassable outside its library | 72 — `base class Preview` | **yes**, provided the subtype is `base`/`final`/`sealed` — and it must be `base`, see below |
| `transform()` is the extension hook | 188 — `@mustCallSuper Preview transform()` | yes |
| `toBuilder()` / `build()` exist and are public | 192, 320 | yes |
| `MultiPreview` enumerates statically | 250 — `List<Preview> get previews` | **no** — a runtime getter returning arbitrary Dart (see *Identity*) |

## The problem, stated correctly

A widget has several states — empty, loading, populated, error, long-text, a
role variation. Three mechanisms existed, each wrong in a different direction.

**Nested maps** already gave tree-visible states:

```dart
'Avatar tile': {'Members': ..., 'External': ..., 'Empty': ...},
```

In the tree, searchable, walked by the catalog test, screenshot-able. **Nobody
used them for states**, because the declaration sits in a central file hundreds
of lines from the widget.

**`parameters.picker`** was the only way to declare states *in the demo file*. It
kept the map small and made those states invisible to the tree, to search, to the
`testWidgets` walk, and unaddressable for a screenshot.

**Stacked sections inside one demo** — and this, measured, is the actual
incumbent. In the reference project, `parameters.*` appears in **9 of 168 demo files** and
`parameters.picker` in **6 usages total**; an earlier draft of this doc claimed
pickers were "what everyone reached for", and that was wrong. What people
actually write is `avatar_tile.dart`: one demo whose body is a scrolling `Column`
of `_Section('Members')`, `_Section('Shared Patients')`, `_Section('Long
content')`, each a header over a card of live widgets.

That correction does not weaken the case; it sharpens it. Stacked sections carry
every flaw pickers do — invisible to tree, search, test-walk, unaddressable for a
screenshot — **plus one more: they only work for component-sized widgets.** It is
why full-screen entries have no declared states at all today. Two consequences
follow, and both are load-bearing:

- Migration is ~168 demo files exploding into ~400 entries, not a rename pass.
- The **contact sheet is the replacement for the dominant idiom**, not a nicety
  for parent folders.

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

5. **Flat variants, with stable identity.** No axes-as-cross-product. Every
   variant has an identity distinct from its display name, so renames do not
   break agent-held references or screenshot baselines. That identity is
   **derived** (`path` + `symbol`) and `id:` overrides it — see *Identity*. An
   earlier wording ("every variant carries an `id`") read as mandating the field;
   it did not, and open item 5 settled the other way.

6. **Hierarchy is path-derived.** Display name from `name:`. the reference project's folder
   layout already reproduces its hand-written tree.

7. **Discovery is syntactic, never resolved, and registration is the whole
   mechanism.** 478ms for 778 files against 17.3s for a *single* resolved unit.
   Annotation classes are recognised by **registration** — `previewAnnotations`,
   defaulting to `['Preview', 'Demo']`. The class-hierarchy closure is **cut from
   the design** (2026-07-27); see *Discovery* for why it turned out to buy
   nothing.

8. **No auto-expansion of finite parameters. Diagnostic only.** A finite
   `picker`/`bool` is never silently promoted to a tree node.

9. **Axes are runtime, and flutterware supplies no shell and no vocabulary.**
   Projects write their own wrapper with whatever concepts they have — theme,
   flavour, feature flags, auth. Our obligation is only that axes are
   *enumerable* and *settable by name*.

10. **`FormFactor` keeps its name and gains a meaning.** Stated earlier as "the
    existing published enum, extended"; that was continuity-washing. Today
    `enum FormFactor { mobile, desktop, all }` carries no size at all — it
    selects **which device-choice bucket** an entry uses. The new enum adds a
    **layout size**, and the bucket job survives alongside it. See *`FormFactor`
    and the device picker, reconciled*.

11. **`group` is derived when absent, declared when it matters.** New,
    2026-07-27. Directories give folders; `group` gives one further node;
    `name:` gives the leaf. **A file holding more than one entry derives its
    group from the filename** — so variants get a parent with zero ceremony —
    and `group:` overrides that. One concept, sometimes derived, exactly the
    shape decision 5 takes for `id`. It is one of `@Preview`'s eight inherited
    fields, so it costs nothing and works in both hosts.

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

// `base`, not `final`: `final` would forbid a project writing
// `Tablet extends Demo`, which is what `previewAnnotations` exists to support.
base class Demo extends Preview {
  const Demo({
    this.formFactor,          // null → the project-level default fills the gap
    this.id,
    this.figma,
    super.name, super.group, super.size, super.wrapper,
    super.theme, super.brightness, super.localizations,
  });

  final FormFactor? formFactor;
  final String? id;
  final String? figma;

  @override
  Preview transform() {
    final b = super.transform().toBuilder();   // @mustCallSuper
    b.size ??= formFactor?.size;               // an explicit size still wins
    return b.build();
  }
}
```

**`formFactor` has no hardcoded default.** A shipped package cannot know that
`mobile` is right — a desktop-only project would write `formFactor: desktop` on
every entry. `transform()` therefore leaves `size` null when the annotation is
silent, and the **project-level fallback** already described under *Render order*
fills it. Same mechanism, one fewer wrong guess. This is what settles open item 2
(see *Resolved*).

```dart
// demo/src/desktop/developer_console/list/environments_table.dart
@Demo(name: 'Environments table', formFactor: FormFactor.desktop, figma: 'node-id=1:234')
Widget environmentsTable() => EnvironmentsTable(rows: mockRows);

@Demo(name: 'Empty')
Widget environmentsTableEmpty() => EnvironmentsTable(rows: const []);
```

Variants are **stacked annotations or separate zero-arg functions** — whichever
reads best. Each is a real, independent tree leaf: addressable, searchable,
screenshot-able, walked by the test loop. A `MultiPreview` subclass was a third
offered spelling and is **withdrawn**: `previews` is a runtime getter returning
arbitrary Dart, so neither the tree nor the generated file can enumerate it
without running it (see *Identity* and *Enumeration in `flutter test`*).

The parent node is an ordinary folder that additionally renders a **contact
sheet** of its children. Note this is not a new design: `IndexView` already
renders `GridView.count(crossAxisCount: 5)` of live `_IndexPreview`s with device
frames and `FittedWidget`, recursing into folders. So the mixed-size question is
observable today rather than hypothetical — see open item 3.

The const-constructor restriction is why the `FormFactor` → `Size` mapping lives
in `transform()`. That is exactly what the hook exists for, per the SDK's own
rationale, and **both** of Flutter's code-gen paths call it.

## `FormFactor` and the device picker, reconciled

**What it actually does today**, read from `app.dart` rather than assumed:

```dart
enum FormFactor { mobile, desktop, all }
typedef FormFactorPicker = FormFactor? Function(String path);

DeviceChoice deviceForEntry(TreeEntry entry) {
  var formFactor = widget.formFactor?.call(entry.path) ?? FormFactor.all;
  return switch (formFactor) {
    FormFactor.mobile || FormFactor.all => mobileDevice,
    FormFactor.desktop => desktopDevice,
  };
}
```

It carries **no size**. It picks one of two stateful `DeviceChoice` buckets —
each holding a device, an orientation, `showFrame`, an available-device list, and
a single/mosaic toggle. `all` is not "render every frame" (an earlier revision of
this section claimed that; wrong): the mosaic lives in `DeviceChoice.useMosaic`,
orthogonally. `all` simply means *unclassified*, and falls into the mobile
bucket.

The bucket's statefulness is the whole point: pick "iPhone SE, portrait, framed"
once and every mobile entry uses it until you change it.

**So there are two jobs, and the new enum serves both:**

| job | consumer | new mechanism |
|---|---|---|
| default layout size | `Preview.size`, both hosts | `FormFactor.size` via `transform()` |
| device-bucket key | toolbar, our host only | the resolved `FormFactor` |

**`FormFactorPicker` survives, demoted from primary to the project-default
layer.** Precedence, first non-null wins:

1. `size:` on the annotation — explicit, both hosts;
2. `formFactor:` on the annotation — both hosts, via `transform()`;
3. the project's `FormFactorPicker` — our host and `flutter test` only;
4. host fallback — ours picks the mobile bucket, Flutter's previewer uses its own.

Layer 3 is why the reference project's ~50 desktop entries need no annotation. Its cost is
stated plainly rather than buried: **an entry that relies on layer 3 is sized by
the previewer's default in the second host**, because the previewer cannot read
project config. That is a per-entry trade, not a per-project one — annotate the
entries you care about seeing correctly in the IDE tab.

**One migration detail that will bite:** the string handed to the picker changes
meaning, from a display-name breadcrumb to a source path.

```dart
// today — breadcrumb of map keys
bool isDesktopCatalogEntry(String path) =>
    path.startsWith('Desktop/') || path.startsWith('Shared/Themes');

// tomorrow — source path
FormFactor? projectFormFactor(String path) =>
    path.startsWith('demo/src/desktop/') ? FormFactor.desktop : null;
```

Note what the rewrite loses: `Shared/Themes` mapped to `demo/src/ui/theme.dart`,
which is not under `desktop/`. Those entries need an explicit
`@Demo(formFactor: FormFactor.desktop)` — the path rule cannot express them. The
catalog test shares this function today, so its viewport rule moves with it.

**`all` is kept and redefined** as *no size opinion* (`size == null`) — the way to
override a project path rule back to nothing for a component that is not pinned
to a device. It keeps routing to the mobile bucket. The name now reads slightly
wrong (it suggests a mosaic, which it never meant); renaming it to `any` would
cost nothing measurable, since the reference project writes `FormFactor.desktop` and `null` and
never writes `all` or `mobile`. Left alone for now, recorded so the choice is
deliberate.

## Addressing

```
entry           →  path + symbol           (derived identity)
id:             →  optional; overrides the derived identity
duplicate       →  hard error, not a diagnostic
variant         →  a sibling entry, not a sub-concept
axes            →  applied assignment, e.g. {theme: dark, locale: fr}
```

### Identity

**`id:` is optional, and a colliding derivation is a hard error.** (Open item 5,
settled 2026-07-27.)

*Requiring it would pay for stability no consumer has yet.* Measured in the reference project:
`Figma(` — **0 usages**, so the `figma:` field is aspirational; **no golden
baselines** keyed on entries; and **no per-entry URLs** — the catalog app's
identity is `TreeEntry.path`, a breadcrumb of *display names*, held in
`_selected` as in-memory state with no routing at all. So the
bookmarked-catalog-link-in-a-PR argument does not exist to be protected. Against
that, requiring 300 hand-written strings creates a failure mode absent today:
copy a demo file, forget to change the id, silently shadow an entry.

*The rename risk is smaller than it reads.* Path and symbol are both
IDE-refactor-visible, and the **checked-in generated file** decided under
*Enumeration in `flutter test`* turns a changed derived id into a **reviewable
diff** — for free, on machinery already in the design. That is most of what a
required `id:` was meant to buy.

*But one derivation is genuinely ambiguous, and it is exactly the variant case
decision 5 cares about.* Stacked annotations on a single declaration derive **the
same `path#symbol` for every variant**. Both fallbacks are worse than the
disease:

| fallback | why rejected |
|---|---|
| append the display name | display names churn most of all; reintroduces the exact fragility `id:` exists to prevent |
| append an ordinal | inserting a variant renumbers every sibling below it |

So: **derive when unique, error when two entries derive the same id.** Mechanical,
needs no discipline in the ~90% one-annotation-per-declaration case, and forces
an explicit `id:` precisely where identity is genuinely ambiguous — which catches
the copy-paste case for free.

This is the one place the design's standing posture escalates. Elsewhere the tool
notices and reports; here it stops. A duplicate id is not something noticed on
the side — it is a broken tree, and the second entry is unreachable.

> **The tool never guesses, but it always reports what it noticed — except where
> the ambiguity would silently delete an entry. Then it refuses.**

Global axes (theme, locale, device, text scale) are applied, never expanded into
the tree — expanding them would multiply every leaf by themes × locales.
`@Preview`'s `brightness:` and `localizations:` are read as **the entry's default
axis assignment**, not as immutable context, so the two models compose.

This is the entry address the manifest needs, and it answers master-plan open
question 5 for the catalog: *"screenshot an entry" is under-specified without the
variant and the resolved axis assignment.*

An axis assignment is `{axis name: option label}` — labels, not values — and an
assignment naming an axis the entry does not declare is **reported, not
rejected**. How the names get known before the first render: *Axis enumeration*.

## Discovery

One syntactic parse pass, **one output**: every annotation usage with its target
declaration. Entry recognition is that list, filtered by the registered
annotation names.

### The class-hierarchy closure is cut

Two earlier revisions kept a second output — every `class X extends Y` edge, 1177
of them in the reference project — for two stated purposes. Both dissolved on 2026-07-27.

**Purpose one: discard noise.** The claim was that a declaration-shape filter was
needed against 2180 `@override`s. But `@override` is not in `previewAnnotations`,
so **name-filtering has already discarded it** before any shape question is
asked. The noise never reaches the filter.

**Purpose two: recognise annotated constructors.** A revision noted, correctly,
that filtering to *top-level functions returning `Widget`/`WidgetBuilder`* would
drop **100% of the reference project's 168 entries** (every one a `class XDemo extends
StatelessWidget`), and proposed fixing it by checking the `extends` clause
against a Widget closure. The right fix was to delete the filter, not extend it:

- The **local** syntax is enough for a useful diagnostic — is this a top-level
  function, a static method, or a constructor? does a function's return type say
  `Widget`/`WidgetBuilder`? No closure required.
- The one question needing a closure — *is this class really a Widget subclass?*
  — does not need answering, because **if it isn't, the generated file does not
  compile.** Loud, immediate, and pointing at the offending symbol.

What is deferred with it is the unregistered-subclass diagnostic:

> `Tablet extends Preview` is used as an annotation on 12 declarations but is not
> listed in `previewAnnotations`.

With `Demo` the sole shipped annotation and `['Preview', 'Demo']` the default
registration, **nobody yet has a subclass to forget to register**. When a project
writes one, either it registers it or its entries do not appear — visible
immediately. The closure is the same traversal and can be added the day that
becomes a real complaint. Deferring it costs a diagnostic; keeping it cost a
second output, a transitive closure, and a filter that had already broken once.

Registration stays authoritative and deterministic. The design's posture is
unchanged, just with one fewer instance of it — unexpanded pickers and unmatched
form-factor globs still report:

> **The tool never guesses, but it always reports what it noticed.**

**Literal annotation arguments are parsed syntactically** (`name: 'Members'` is a
string literal); everything non-literal is deferred to the guest. So the tree has
display names before anything is compiled, and `size: kSomething` still works
without any resolution.

## Render order, in the guest

**Built and measured** — `2026-07-27-generated-wrapper-spike-findings.md`.

Semantics are never interpreted statically. The generated per-entry wrapper emits
the annotation's source text and evaluates it. **Two values, not one:**

```dart
const fwDemo = Demo(name: 'Long text', wrapper: catalogShell, size: kWideSize);
```

1. `fwDemo` → the annotation: `id`, `figma`, `formFactor`.
2. `fwDemo.transform()` → a real `Preview`, which **drops all three** —
   `toBuilder().build()` returns a plain `Preview`, so the wrapper must keep both.
3. `preview.size` → configure the view / `MediaQuery`.
4. `preview.wrapper` → wrap.
5. `preview.theme` / `brightness` / `localizations` → apply as axis defaults.
6. build the widget from the annotated declaration.

All before the first frame, and costing only the entry's compile — which
rendering requires regardless. `size` is nullable, so a **project-level fallback
default** applies when the annotation is silent; Flutter's previewer has its own
fallback, and the two never conflict because ours only fills a gap.

**Mechanism note.** The annotation is written in the demo file's import scope, so
generated code must see `Demo`, `FormFactor`, and any project-local wrapper. A
small **per-entry wrapper file** carries that demo file's imports verbatim, with
**relative imports re-relativised** to the wrapper's own location — demo files
live outside `lib/` and have no `package:` URI, so `../utils/test_app.dart` must
become `../../demo/src/utils/test_app.dart` or the wrapper does not compile.

The accumulating entrypoint imports one wrapper per entry ever visited. **This
makes S3's fresh-prefix rule structural rather than a rule to enforce**: every
switch imports a *new file* under a *new prefix*, so a prefix is never rebound
and the trap is unreachable by construction. The entrypoint selects the live
entry through a **getter**, never a top-level `final`.

Two operational constraints the spike hit:

- **Ids must be project-relative.** An absolute path makes the committed
  generated file machine-specific, so the no-diff CI check fails for everyone.
- **The generator must not own the directory holding the entrypoint.** Clearing
  its output directory takes the live entrypoint with it.

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

## Axis enumeration

**Settled 2026-07-27.** Decision 9 obliges axes to be *enumerable* and *settable
by name*, and nothing enumerated them: `EditableParameters._addParameter` fires
its `onAdded` callback the first time a demo **asks** for a picker, during build.
An axis existed only after rendering the entry that declared it — which blocks an
agent from requesting "screenshot E with `Language=fr`" before it knows the axis
is there.

**1. Declaration stays where it is.** No registry, no second declarative API.
`topBar.picker` and `parameters.*` remain the only place an axis is declared —
requiring a project to also list its axes somewhere would duplicate the
declaration, and would need its own degradation story in the two hosts where the
picker call already returns `defaultValue`.

**2. Enumeration is a probe, and global axes need no entry at all.** The project
shell is a `WidgetWrapper` — `Widget Function(Widget)` — so it can be rendered
around nothing:

```dart
// enumerate every global axis without compiling a single demo
config.wrapper(const SizedBox());
```

Its `build` runs the `topBar.picker` calls regardless of the child. **One probe
per session yields every global axis.** Local knobs live in a demo body and need
that entry rendered — which the session is doing anyway before it can screenshot
it. So the cost is one extra render of an empty shell, once.

**3. The wire model is labels, never values.** `PickerParameter.options` is
already `Map<String, T>`, so the label set survives without `T` crossing the
boundary:

```
{ name: 'Language', kind: picker, options: ['en', 'fr', 'nl'], current: 'en' }
```

Setting is `param.value = options[label]`, which already calls
`notifyListeners()`. No API change on either side.

**4. What is addressable, from the existing sealed `Parameter`:**

| kind | addressed as | in an entry address? |
|---|---|---|
| `PickerParameter` | a label from a known set | yes |
| `BoolParameter` | `true` / `false` | yes |
| `StringParameter`, `NumParameter`, `DateTimeParameter` | a literal value | settable, not enumerable |
| `ActionButtonParameter` | — | no: an action, not state |

This also draws the line decision 8 needs. A finite picker or bool is an
*addressable axis*; a free-form knob is not, which is precisely why the design
refuses to promote either into the tree.

**5. The chicken-and-egg is answered by reporting, not blocking.** A request
naming an axis the entry has not declared renders with defaults and returns the
axes it *did* find:

> Rendered `…#memberListEmpty` with defaults. Unknown axis `Theme`. Axes
> available here: `Language` (en, fr, nl), `Edit mode` (bool).

First call teaches, second call sets. The posture is the same one used for
unexpanded pickers and unmatched form-factor globs; the alternative — failing the
request — would make the first screenshot of any entry impossible to write
blind.

**6. Re-probe on hot reload.** The shell is ordinary code and can gain or lose an
axis on any edit.

## Project configuration

**Settled 2026-07-27.** The design accumulated four pieces of project config —
`previewAnnotations`, the form-factor path rule, the default size, and the
default wrapper — with no home, and they do not all belong in the same one.

**The criterion:**

> **Must the tool know it before the first compile? Then it is static. Otherwise
> it is Dart.**

| config | needed by | when | home |
|---|---|---|---|
| `previewAnnotations` | discovery filter | before any compile | static |
| scan roots | the parse pass | before any compile | static |
| default wrapper / shell | the guest | at render | **Dart — it is a function** |
| default form factor, default size | the guest, the test | at render | Dart |
| the axes | the guest | at render | Dart, by construction — they live inside the shell |

**Decision: no static config file on day one.** Both static entries have working
defaults — `['Preview', 'Demo']`, and scanning `demo/`. A project that must
deviate gets a file then; stating the criterion now means its contents are
already decided. This is the same defer-until-evidence posture the rest of the
design takes, and it keeps the count of things a new project must write at zero.

**The Dart half is discovered the way entries are** — syntactically, by symbol
name, in the same 478ms parse. It needs no pointer and no registration.

**It must be a getter, not a `final`.** From the widget-previews findings:

> A top-level `final` is lazily initialised once, and **hot reload does not re-run
> the initialiser of an already-initialised static.**

```dart
// demo/src/catalog_config.dart

// WRONG — freezes the shell for the life of the session
final catalogConfig = CatalogConfig(wrapper: catalogShell);

// RIGHT — re-evaluated on every read, so editing the shell hot-reloads
CatalogConfig get catalogConfig => CatalogConfig(
  wrapper: catalogShell,
  formFactor: projectFormFactor,
);
```

Editing the shell — adding an axis, changing the theme — is exactly the edit a
developer makes mid-session, and the `final` spelling would silently keep the old
one live. This is the second API shape that measurement has decided; the first
was the annotation itself, which is `const` and re-evaluated per render for the
same reason.

## What the guest renders — the canvas boundary

**Settled 2026-07-27.** This was open item 1, and it is an architecture decision
rather than a layout one: in the flutterware GUI the demo renders in the
**embedder guest** while the tree and chrome render in the **GUI process**, so
"show ten demos at once" asks whether there are ten guests, one guest rendering
ten views, or no live rendering at all.

> **The guest renders the canvas, live — one entry or many. The GUI renders the
> tree and the chrome around it.**

### Corrects an earlier answer in this document

An earlier revision of this section decided the opposite: that the guest renders
exactly one entry and every multi-view surface is a cache of captured images.
That was wrong twice, and both errors are worth keeping visible.

**The evidence did not support the conclusion.** It argued from the fact that
both existing multi-view surfaces already suppress interaction — the folder index
wraps each live entry in `AbsorbPointer`, `_Mosaic` wraps the repeated demo in
`IgnorePointer` + `ExcludeFocus`. That establishes the sheet need not be
*interactive*. It says nothing about whether it need be *live*.
**Non-interactive is not the same as static.**

**The cost argument ran backwards.** It claimed filling a sheet costs
N × (compile + reload). The compile term is real and unavoidable either way — a
demo must be compiled to be shown at all. The reload term is not, because of a
figure S3 had already measured:

> **Reload cost is flat in subtree size.** 718 new libraries reloaded in 45ms.
> Compile dominates; reload does not.

The accumulating entrypoint already imports every entry ever visited. So showing
N demos is **one incremental compile, one reload, one frame** — not N switches, N
captures and N PNG encodes. Live rendering is *cheaper* than capturing, not more
expensive.

The empirical check settles it: today's in-process catalog already renders the
whole recursive index live — `IndexView` → `_Folder` → nested `IndexView` — with
the reference project's ~300 entries. Many demos live in one tree is current shipping
behaviour, not a hypothesis.

### The boundary

| guest — the canvas | GUI — around it |
|---|---|
| the demo | tree, search, breadcrumb |
| the project shell (`catalogConfig.wrapper`) | toolbar: axis pickers |
| device frames, orientation | knobs panel |
| the contact sheet, the folder index, mosaic | Figma panel, error surfacing |
| scrolling within the canvas | |

This is almost exactly today's `Menu` versus `DetailView`/`IndexView` split, which
is the point: **`_Mosaic`, `IndexView`, `FittedWidget` and `DeviceFrame` move
rather than get rewritten.** They live in `package:flutterware`, which the project
already depends on, so they are in the guest closure for free.

### What follows

- **One guest process**, rendering one texture. The N-guests question does not
  arise.
- **Device frames render in the guest**, reusing the vendored `device_frame`.
  Changing device is guest-side state — a message and a rebuild, **not a
  recompile and not an engine resize**.
- **No cache, no invalidation, no staleness, no LRU.** Editing a demo hot-reloads
  the whole sheet at once, because every entry in it is in the same tree.
- **The sheet is interactive in exactly one way**: clicking a thumbnail selects
  that entry. Today that is an `InkWell` outside an `AbsorbPointer` — tap the
  card, not the demo. The guest handles the tap and reports the selection to the
  GUI, which moves the tree.
- **A demo that throws is contained** by Flutter's per-subtree error widget, as
  it is today.

### Where captures still earn their keep

Two places, neither of which is the rendering architecture:

1. **Entries this session has never compiled.** Live means compiling everything
   you display, so a root index of ~300 entries is the full **12.9s** catalog
   compile — precisely what lazy compilation exists to avoid. A persisted
   thumbnail lets the index show something real without paying for it. This is an
   optimisation layered *on* live rendering, and it is where the "cached, very
   fast" goal actually cashes out.
2. **CI baselines and per-PR screenshots** — already deferred, and capturable
   from the live path when wanted.

If captures are added, the key is the entry address this document already
defines — `{id, axis assignment, size}` — and source edits invalidate precisely,
since the generator maps file → entries.

### Still open

- **Sheet layout** — the original open item 1: arranging a sheet that mixes
  component-sized and screen-sized children. Now purely a guest-side widget
  problem, with `IndexView`'s `FittedWidget` + `AspectRatio(1)` as the treatment
  to beat.
- **The cold-index policy.** What a folder shows for entries not yet compiled:
  placeholders, persisted captures, or names only. This is the one place the
  laziness goal and the live-rendering model genuinely pull against each other.

## The same catalog, written both ways

Every capability the reference project exercises today, before and after. Written against real
files, not invented examples — this is the section to check the design against.

### 1. Declare an entry

```dart
// TODAY — demo/src/mobile/team/avatar_tile.dart
void main() => runApp(const AvatarTileDemo());

class AvatarTileDemo extends StatelessWidget {
  const AvatarTileDemo({super.key});
  @override
  Widget build(BuildContext context) => TestApp(child: Scaffold(body: ...));
}

// …plus, 200 lines away in demo/src/ui_catalog.dart:
import 'mobile/team/avatar_tile.dart';          // one of 128 imports
'Team': {'Avatar tile': AvatarTileDemo(), ...}  // one of ~300 map lines
```

```dart
// TOMORROW — demo/src/mobile/team/avatar_tile.dart
void main() => runApp(const AvatarTileDemo());  // unchanged: the real-device path

class AvatarTileDemo extends StatelessWidget {
  @Demo(name: 'Avatar tile')
  const AvatarTileDemo({super.key});
  @override
  Widget build(BuildContext context) => TestApp(child: Scaffold(body: ...));
}
```

The import and the map line are gone; `demo/src/mobile/team/` supplies
`Mobile / Team`. Nothing else in the file moves — notably `TestApp` stays in the
body, where it works in all three hosts with no configuration.

**The annotation site is not restricted to constructors.** `@Preview` accepts
top-level functions, static methods, and public constructors or factories with no
required arguments; this example annotates a constructor only because the reference project's
168 demos are already Widget classes, making it the zero-churn migration. §2
annotates top-level functions. Dart's forthcoming primary constructors collapse
the distinction anyway — `@Demo(...) class AvatarTileDemo(...)` will read as the
class being annotated.

### 2. Variants — the migration that matters

```dart
// TODAY — demo/src/mobile/team/member_list_view.dart
class MemberListViewDemo extends StatelessWidget {
  const MemberListViewDemo({super.key});
  @override
  Widget build(BuildContext context) {
    final items = context.uiCatalog.parameters.picker('Items', {
      'Empty': const <MemberItem>[],
      'Few': _few,
      'Many': _many,
    }, _few);
    return TestApp(child: Scaffold(body: MemberListView(items: items)));
  }
}
```

One tree leaf. Three states reachable only by a human clicking a knob: not
searchable, not screenshot-able, not walked by the test.

```dart
// TOMORROW — same file, three real leaves, no group: anywhere
@Demo(name: 'Few')
Widget memberListFew() => _view(_few);

@Demo(name: 'Empty')
Widget memberListEmpty() => _view(const []);

@Demo(name: 'Many')
Widget memberListMany() => _view(_many);

Widget _view(List<MemberItem> items) =>
    TestApp(child: Scaffold(body: MemberListView(items: items)));

void main() => runApp(_view(_few));   // real-device path, still one line
```

Tree: `Mobile / Team / Member list view / {Few, Empty, Many}`, and the
`Member list view` node renders the contact sheet.

**Nothing declares that folder.** The file holds more than one entry, so its
group is derived from the filename (decision 11). A file with one entry derives
nothing and its entry sits directly in the directory — which is why §1 needed no
group either. The dominant migration case therefore costs exactly one annotation
per state and no structural bookkeeping.

Two consequences worth stating, since the rule is implicit:

- **Adding a second entry to a file restructures that file's subtree.**
  `Mobile / Team / Avatar tile` becomes `Mobile / Team / Avatar tile / {…}` the
  moment a variant is added. Mechanically harmless — ids are `path#symbol` and do
  not move — and arguably the point: the parent appears exactly when there is
  something to parent. It does show up as a diff in the generated file.
- **The derived name is a humanized filename**, which is a weaker name than a
  curated one. the reference project's map says `'Tiles sizes'` where the file says
  `tiles_size.dart`, and `'Image comparison — empty'` where the file says
  `image_comparison.dart`. When the derived name is wrong, `group:` overrides it.

### 2b. When `group:` is still worth declaring

The override earns its keep in one case the implicit rule cannot reach:
**a group spanning several files in one directory.** Implicit groups are
file-bounded; the reference project's real tree is not.

| tree node today | comes from | implicit rule gives |
|---|---|---|
| `Mobile / Case / Tiles` (5 entries) | 5 files in `mobile/case/`, one entry each | 5 flat leaves under `Mobile / Case` |
| `Mobile / Case / Upload` (4 entries) | `upload_capture.dart` (1), `upload_progress.dart` (3) | one leaf, plus a separate `Upload progress` folder |

Two honest ways to recover them, and the project picks:

```dart
// (a) declare the group — several files, one node
@Demo(group: 'Tiles', name: 'Tiles sizes')

// (b) make it a directory — mobile/case/tiles/tiles_size.dart, no annotation
```

Upstream semantics agree with (a): Flutter documents `group` as *"previews with
the same group name will be displayed together"* — a flat grouping key, not a
path segment. Sharing one across files is what the field is for.

**Mechanism wart.** `Preview.group` is a non-nullable `String` defaulting to
`'Default'`, so there is no null to mean "unset". `group == 'Default'` is the
sentinel that triggers derivation. It matches what upstream means by the value,
but it does mean a project cannot declare a group literally named `Default`.

### 3. App-wide axes — the top bar

Unchanged in spirit. Decision 9 deletes a flutterware-supplied *shell and
vocabulary*, not the picker API — "axes are enumerable and settable by name" is
precisely `topBar.picker`.

```dart
// TODAY — inside UICatalog(appBuilder:) in demo/src/ui_catalog.dart
appBuilder: (context, child) {
  var locale = context.uiCatalog.topBar.picker('Language', {
    for (var language in Language.values) language.name: language.toLocale(),
  }, Language.defaultLanguage.toLocale());
  return TestApp(child: DefaultLocale(locale: locale, child: child));
},
```

```dart
// TOMORROW — demo/src/catalog_shell.dart, the project's own file
class CatalogShell extends StatelessWidget {
  final Widget child;
  const CatalogShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final locale = context.uiCatalog.topBar.picker('Language', {
      for (final l in Language.values) l.name: l.toLocale(),
    }, Language.defaultLanguage.toLocale());
    return TestApp(child: DefaultLocale(locale: locale, child: child));
  }
}

/// `WidgetWrapper` is `Widget Function(Widget)` and must be static and public.
Widget catalogShell(Widget child) => CatalogShell(child: child);
```

Applied per entry with `@Demo(wrapper: catalogShell)`, or — for the 168 entries
that all want it — as the project-level default wrapper, declared once:

```dart
// demo/src/catalog_config.dart — a getter, never a final; see Project configuration
CatalogConfig get catalogConfig => CatalogConfig(wrapper: catalogShell);
```

Same layer-3 caveat as `formFactor`: the project default is invisible to
Flutter's previewer. And because the shell is a plain `Widget Function(Widget)`,
it is what the host renders around a `SizedBox` to enumerate global axes without
compiling a demo — see *Axis enumeration*.

The degradation is already shipped and already relied on: outside our host,
`topBar.picker` returns `defaultValue`, so the same file renders in
`flutter test` and in the previewer with the default language.

### 4. Knobs that stay knobs

Not everything is a state. `group_info_view.dart` today:

```dart
final showLeave = context.uiCatalog.parameters.bool('Show leave', true);
final showDelete = context.uiCatalog.parameters.bool('Show delete', true);
```

**Unchanged.** Two booleans are four combinations; expanding them into four
sibling entries is worse than a knob. Per decision 8 the tool does not promote
them silently — it reports:

> `Show leave` (bool) and `Show delete` (bool) are finite and were not expanded
> into entries. If these are states rather than knobs, declare them as `@Demo`s.

### 5. Form factor

```dart
// TODAY
formFactor: (e) => isDesktopCatalogEntry(e) ? FormFactor.desktop : null,

// TOMORROW — project default (layer 3), plus explicit where it matters
FormFactor? projectFormFactor(String path) =>
    path.startsWith('demo/src/desktop/') ? FormFactor.desktop : null;

@Demo(name: 'Environments table', formFactor: FormFactor.desktop)
Widget environmentsTable() => EnvironmentsTable(rows: mockRows);
```

Full precedence and the path-vs-breadcrumb trap: *`FormFactor` and the device
picker, reconciled*.

### 6. Figma

```dart
// TODAY — a widget wrapping the demo (0 usages in the reference project; the API exists)
Figma(links: ['https://figma.com/…node-id=1:234'], child: ...)

// TOMORROW — a field, visible to the tree without rendering anything
@Demo(name: 'Environments table', figma: 'node-id=1:234')
```

### 7. The generated file, and the test walk

```dart
// demo/src/catalog.g.dart — committed, `fw catalog gen`, CI-diff-checked
import 'mobile/team/member_list_view.dart' as e17;

const entries = <CatalogEntry>[
  CatalogEntry(
    id: 'demo/src/mobile/team/member_list_view.dart#memberListEmpty',
    group: 'Member list view',                 // derived: the file holds 3 entries
    name: 'Empty',
    path: 'demo/src/mobile/team/member_list_view.dart',
    demo: Demo(name: 'Empty'),                 // annotation source text, verbatim
    builder: e17.memberListEmpty,
  ),
  // …
];
```

```dart
// TODAY — test/ui_catalog_test.dart walks the map recursively
testMap(catalog);

// TOMORROW — a flat loop over the same list every other consumer uses
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadExtraFonts();
  });

  for (final entry in entries) {
    testWidgets(entry.id, (tester) async {
      final preview = entry.demo.transform();
      if (preview.size case var size?) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      await tester.pumpWidget(RepaintBoundary(
        child: UICatalogStateProvider(
          state: UICatalogState.empty,
          child: (preview.wrapper ?? _identity)(entry.builder()),
        ),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
```

Two things improve without being asked for. The bespoke
`isDesktopCatalogEntry(path)` viewport rule in the test is replaced by the
entry's own declared size — **one source of truth instead of two that can
disagree** — and the test name becomes the stable id rather than a display name,
so a failure names something that survives a rename.

### What the user loses

Honest inventory, so the trade is visible:

- **Curated tree order.** Alphabetical, per *Resolved 1*.
- **One-glance state comparison.** Today `avatar_tile.dart` shows Members, Shared
  Patients and Long content stacked in one scroll. Tomorrow they are three
  entries and the comparison lives in the contact sheet — which is open item 1.
  Until that is measured, this is a real regression, not a wash.
- **Two ways to spell a variant.** `MultiPreview` is withdrawn, and finite
  pickers are diagnosed rather than promoted.
- **`Preview`'s restrictions become the project's.** No required arguments;
  const-only annotation values; wrappers static and public. The
  parameterised-demo idiom has to become zero-argument functions.

## What this deletes

- **The catalog map.** Hierarchy comes from paths; existence from declarations.
- **`@CatalogEntry`.** Folded into `Demo`.
- **Path-glob form-factor config as the primary mechanism.** It solved verbosity
  but is invisible to Flutter's previewer, so it cannot carry render-affecting
  defaults for the second host. **Demoted, not deleted**: it becomes layer 3 of
  the precedence chain, which is what keeps the reference project's ~50 desktop entries
  unannotated. See *`FormFactor` and the device picker, reconciled*.
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

**This is what withdraws `MultiPreview` as a variant spelling.** Stacked
annotations are statically countable — N annotations, N rows in the generated
file. A `MultiPreview` subclass is not: `previews` is a runtime getter (SDK line
255) returning arbitrary Dart, so the generator cannot know how many entries it
yields or what to name them without executing it. Emitting one row for the
declaration and discovering three previews at render time would make the tree,
the generated file, and the running host disagree — so the spelling is dropped
rather than partially supported.

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

- **The class-hierarchy closure and its unregistered-annotation diagnostic.** Cut
  2026-07-27 — same parse traversal, addable the day a project defines its own
  `Demo` subclass and is bitten by forgetting to register it. See *Discovery*.
- Axes swept as independent dimensions (`4+4` leaves rather than `16`).
- A typed axis vocabulary, for deterministic consumers such as a CI screenshot
  matrix. Waits for evidence.
- Auto-expansion of finite pickers as a per-demo opt-in migration bridge.
- Moving `Demo` to a companion package if `@Preview`'s instability starts to
  hurt. Nothing in the design depends on where it lives.

## Resolved

Four of the five open items, settled 2026-07-27.

**1 — Ordering: alphabetical, no ordering file.** The premise that "the old map's
order was deliberate" does not survive reading it. the reference project's order is *creation*
order — Mobile → Login, Legal, Settings, Dashboard, Case… — with `'Update
required'` a leaf stranded among folders. Nobody maintains it. The one genuinely
meaningful bit is Mobile-before-Desktop-before-Shared at the root, which
alphabetical would scramble; that is a single root-order decision, not a file. In
practice **leaves-before-folders will matter more for scanning than alpha order
does**, and search is the real navigation for both humans and agents. Revisit
when someone complains.

**2 — `FormFactor` does not split into `phone` / `tablet`.** `formFactor` appears
**twice in 168 the reference project files**; the concept is barely exercised, and `size:` says
"tablet" more precisely than an enum value that invites "which tablet". The
question underneath it was the real one — *`mobile` is the wrong hardcoded
default for a shipped package* — and that is answered by making the default a
project setting (see *The shape*), which stops the enum needing to grow.

**5 — `id:` stays optional; colliding derivations are a hard error.** Full
reasoning under *Identity*.

**Plus one not on the list:** `MultiPreview` is withdrawn as a variant spelling —
statically unenumerable. See *Enumeration in `flutter test`*.

## Open

1. **Sheet layout, and the cold-index policy** — the architecture is settled
   under *What the guest renders*; what remains is arranging a sheet that mixes
   component-sized and screen-sized children (anchored on the group node, with
   `IndexView`'s `FittedWidget` + `AspectRatio(1)` to beat), and deciding what a
   folder shows for entries this session has not compiled.
2. **Migration** for the ~168 demo files / ~400 resulting entries: diagnostic-driven,
   or a codemod? (Owner, 2026-07-26: "we'll see.") Note the corrected shape of
   the job — it is not a rename pass but a decomposition of stacked `_Section`s
   into sibling entries, and it converts Widget-class demos into annotated
   constructors.
