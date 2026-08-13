# Run knobs: the config declares, the signature receives, the wrapper delivers

**Date:** 2026-08-12
**Status:** Decided with the owner in conversation. **Every mechanism is
measured** (§ What was tested) on macOS, the iOS simulator and the Android
emulator; web is not, and none of the UI is built. Supersedes the
define-scanning design this file held earlier — § What came before records what
was built, reverted, and explored-then-rejected, so none of it is rediscovered.

**Lineage:** `2026-08-11-computed-define-sources.md` (the computed source, which
survives with a new noun), `2026-08-11-run-drive-design.md` (the guest wrapper
this hangs off), `2026-08-12-run-knobs-spike-findings.md` (E1: the wrapper
recompiles on hot restart — the delivery mechanism),
`2026-08-11-devbar-run-bridge-design.md` § Decision 4 (devbar variables, which
keep the *other* half of the job and are not touched here), and above all
`2026-07-27-knobs-static-and-runtime.md` — **which is this same mechanism,
worked out for demos**: a parameter list as the declaration, a generated wrapper
passing values in, "callable with no arguments" as the contract, defaults that
must be constant. Read it before building; its open questions are ours (§ K7),
and its conclusion — the static and runtime paths coexist rather than one
migrating to the other — is why devbar variables are untouched here.

## The report

A client wired a server URL as a `--dart-define`, declared it in
`tool/flutterware.dart`, and came back with two complaints:

1. The `String.fromEnvironment` lived in a config file rather than the entry
   point, and they ended up restating it in `tool/flutterware.dart`.
2. Switching the URL costs a full rebuild. Their previous workflow — an inline
   value in the source — cost a hot restart, two orders of magnitude cheaper.

Complaint 2 is not a defect of ours: `--dart-define` is baked into the frontend
server's invocation at process start, and hot restart reuses that server, so the
value cannot move. **The defect is that we made a compile-time constant the way
to express a knob.** Everything here follows from undoing that.

## The shape

Every design needs two halves — somewhere the knob is **declared**, and
somewhere the app **reads** it — and a long exploration kept improving one while
the other moved. The landing gives each half to the thing that is good at it:

```dart
// tool/flutterware.dart — declared once, shared by being a variable
final devKnobs = [
  Knob('serverPort',
      from: ValueSource.script('tool/local_env.dart', args: ['port', 'server'])),
  Knob('apiHost', from: ValueSource.hostAddresses),
];

Entrypoint('lib/main.dart', name: 'App', knobs: devKnobs),
Entrypoint('lib/main_staging.dart', name: 'Staging', knobs: devKnobs),
```

```dart
// lib/main.dart — just the socket. No annotation, no flutterware import.
void main({int serverPort = 8086, String apiHost = 'localhost'}) =>
    runApp(App(port: serverPort, host: apiHost));
```

```dart
// .dart_tool/flutterware/run/main_guest.dart — regenerated, never edited
runGuest(() => entry.main(serverPort: 8186, apiHost: '192.168.1.24'));
```

- **The config declares** — names, options, and the command that computes a
  value. Sharing across entry points is a Dart variable, because
  `tool/flutterware.dart` is Dart. No per-package list, no new field for
  sharing.
- **The signature receives** — matched by name. It carries no annotation and no
  dependency on us; a plain Dart `main` with optional named parameters.
- **The wrapper delivers** — a literal in generated code, so a change is a **hot
  restart, not a rebuild**.

## What was tested

Everything below the design line was measured before it was designed around,
because it all turns on whether Dart and Flutter accept that signature.

| what | result |
|---|---|
| `dart run app_main.dart` (unwrapped) | defaults apply, enum included |
| `dart run wrapper.dart` | named args arrive, enum included — *hand-written; discovery is § K7* |
| enum behind a prefixed barrel (`export … show`), value with ctor args | `main(Backend.staging, 9)` — K4 and K7 compose |
| `dart analyze` | `No issues found!` |
| `flutter run -d macos -t lib/main.dart --dart-define=SERVER_URL=…` | the define reaches the parameter's default |
| iOS simulator, launch → wrapper rewrite → restart | `https://ios-from-the-wrapper / staging`, **263 ms** |
| Android emulator, same | `https://android-from-the-wrapper / prod`, **3067 ms** vs **38.6 s** to rebuild |
| macOS, three consecutive wrapper rewrites | **262 / 343 / 237 ms** vs **29.6 s** to rebuild |

Optional named parameters on `main` are legal: the VM and the embedder require
only that `main()` be callable with zero arguments. A parameter default may be a
`String.fromEnvironment`, because defaults must be constant expressions and that
is one — which is how a knob and a release-configurable value can be the same
line.

## K1. The config declares, and sharing is a variable — **built 2026-08-13**

`Entrypoint` gains `knobs:`. A `Knob` carries only what a signature cannot:

- **`from:`** — `ValueSource.script(…)` runs a script the project owns;
  `ValueSource.hostAddresses` offers this machine's addresses, each named by the
  interface it was found on. This is `2026-08-11-computed-define-sources.md`
  intact — including that **a script which cannot answer refuses the launch**,
  because the value ends up compiled in and an app built against the wrong port
  is indistinguishable from a correct one until it is talking to another
  worktree's database.
- **`options:`** — values worth offering for a knob whose type cannot enumerate
  itself. An `enum` needs none: § K7 reads its values off the declaration.
- **`label:` / `description:`** — `serverPort` is a fine identifier and a poor
  explanation.

It carries **no default**: the signature has one, and repeating it is the
two-places-to-be-wrong this whole exercise is about.

Sharing needs no API. `final devKnobs = [...]` referenced from several entry
points is the whole feature, and it works because the config is a Dart file.
A per-package `parameters:` list was proposed and rejected for exactly this
reason.

## K2. The signature is the list — **built 2026-08-13**

**The parameter list is what the entry point takes. The config annotates it by
name.** No authority rule, because the two halves are no longer answering the
same question — a signature cannot be wrong about what its own `main` accepts.

Two mismatches, both reported rather than guessed:

- **A knob no parameter has** — the config names `serverPort`, `main` does not
  take one. Reported the way a declared-but-unread define is today: the control
  would appear and do nothing, which looks exactly like a broken feature.
- **A parameter no knob annotates** — offered anyway, with its name, type and
  default read off the signature. That is the zero-config case and it should
  stay free.

This is why the B1/B2 tension disappears rather than being resolved: there is no
longer a scan whose results compete with a declaration. It also fixes the
`Studio (dev)` embarrassment by construction — `main_dev.dart` takes no
parameters, so it offers no knobs, where the package-level scan offered four
constants belonging to a different entry point.

## K3. Delivery: rewrite the wrapper, hot restart — **built 2026-08-13**

Unchanged from E1, and the reason this design exists. `writeGuestEntrypoint`
already regenerates `.dart_tool/flutterware/run/<name>_guest.dart` on every
launch; rewriting that one file is picked up by hot restart.

Two facts from the spike carry straight over:

- **Hot reload is not enough.** A value passed to `main` moves only when `main`
  runs again, and reload does not re-run it. Restart is required, and **restart
  loses the app's state**.
- **Launch also writes the wrapper** (`launch.dart:99`), so its content must
  come from one function called both there and by whatever applies a knob change
  between launches, or the two drift.

And one that only shows on a phone: **the ratio does not travel.** 113x on
macOS, 12.6x on Android — 3 seconds rather than a quarter of one. Worth having,
worth not describing as "instant".

## K4. The wrapper copies the entry point's imports — **built 2026-08-13**

Found by testing, and it would have broken most real apps. The wrapper names the
values it passes, so `entry.Backend.staging` fails whenever the enum lives
anywhere but the entry point file itself:

```
wrapper_naive.dart:4:31: Error: Undefined name 'Backend'.
```

`main.dart` does not export what it imports. The fix is to copy the entry
point's import directives into the generated wrapper — measured working,
including a shared `const defaultPort` from another file. Three rules:

- **Relative imports must be rewritten, not copied.** The wrapper lives at
  `.dart_tool/flutterware/run/`, so `import 'src/config.dart'` resolves against
  the wrong directory — measured, it is the real layout. Mechanical to fix: the
  entry point is under `lib/` already, so every relative import maps to
  `package:<name>/…`, and `writeGuestEntrypoint` already computes that prefix.
- **A private identifier cannot be named at all.** The wrapper is a separate
  library, so `_localPort` is invisible even when it is declared in the entry
  point file. Caught without resolving anything — a leading `_` is refused with
  "make it public; the generated wrapper is a separate library".
- **Import our own guest with a prefix**, so the app's namespace cannot collide
  with `runGuest`.

Unused imports in the generated file are harmless: it lives outside `lib/`
precisely so that, as its own doc comment says, no analyzer or tool of the
project's ever meets it.

## K5. Where you change it — **built 2026-08-13**

**This decides whether the measurement is ever felt by a human.**

The launch form lives on the New run page, and once an app is running the only
route back is **Stop** — which is a relaunch, which is the rebuild this design
exists to remove. Shipping K1–K4 without this would leave the improvement
measurable and unreachable.

So the running app's own view — the tab strip beside Screen / Steps / Logs /
Network / App, which already carries **Hot reload** and **Hot restart** — gains
the knobs of the run it is showing, editable, with **Restart to apply** beside
the changed one.

- **Not auto-restart.** Losing the cart because somebody typed in a field is a
  surprise a cockpit should not spring.
- **Not applied live.** A parameter reaches the app only through `main`; showing
  a new value while the process holds the old one would look correct and be
  wrong.
- **The New run page keeps the same fields** for the first launch. One widget,
  two hosts.
- **`setKnobs` is the agent's half of the same button** — same validation, same
  rewrite-and-restart, and it reports everything the app is now running with
  rather than only what the call changed.

**Built and driven.** A `Knobs` tab beside Screen / Steps / Logs / Network /
App; `KnobField` is the one widget both hosts render, so a knob cannot look like
a text field in one place and a dropdown in the other. `RunCore.applyKnobs`
rewrites the wrapper, restarts, and rewrites the handle — which now carries
`knobs`, because a knob whose current value the tool had forgotten would be a
field you can only overwrite blind.

Driven in the cockpit rather than asserted: the New run page showed
`Defines — compiled in — changing one is a rebuild` above
`Knobs — passed to main — changing one is a hot restart`, with `apiHost`
(string), `serverPort` (integer), `verbose` (switch) and `backend` (a dropdown
of the enum's own constants). On the running app, **Restart to apply** stayed
disabled until the dropdown moved, the cost line appeared with it, and one click
put `localhost:8086/prod` on the app's screen. `setKnobs` moved a running app
from `first.example.com/dev` to `second.example.com/prod` in **313ms**.

**Two bugs the live run found, both about refusing early.** The action did not
call `computeAll`, so there were no entry points to validate against, the check
silently passed, and the restart failed on a wrapper that would not compile —
surfacing as `s1.hotRestart: (-32603)`, which says nothing to anybody. And a
failed restart left the app on its old code with the *new* wrapper on disk, so
every later reload would fail too, on a change nobody wanted any more. The
wrapper is now restored when a restart throws, and an entry point this worktree
does not declare is refused outright rather than written unchecked.

**And one the empty tab was hiding.** `knobEntriesFor` returned an empty list
for a run it could not read, which claims the app takes no knobs — a statement
about somebody else's source. It now returns a reason instead, and the tab shows
that rather than the "takes none" text. Chasing it found the real defect
underneath: **`applyKnobs` did not check whose run it was.** `absolutePathOf`
resolves in *this* worktree, so applying to another checkout's run would rewrite
this worktree's wrapper and restart that app onto this worktree's code. Another
checkout of the same repo has the same package paths and the same entry point
names, so every lookup succeeds and the knobs shown would have been plausible and
wrong. Both paths now check `isMine` first.

## K6. What stays a `--dart-define` — **built 2026-08-13**

Release configuration and flavors. A production build does not go through our
wrapper, so a value that must differ in a shipped artifact is a build input, not
a knob — and `int serverPort = const int.fromEnvironment('PORT', defaultValue: 8086)`
serves both in one line.

We stop **modelling** defines — no scan, no `DartDefine`, no `DefineSource`, no
define fields, no name validation — and keep **forwarding** them: a raw
`dartDefines:` map on the launch action, passed through verbatim, no UI, no
validation. Five lines, and it covers the three cases a parameter cannot reach:
a define read by a package you do not own (a library has no `main`), a define
the native build consumes (`Info.plist`/Gradle substitution, which no Dart code
reads), and anything needed before the Dart entry point runs at all.

The principle: modelling a standard Flutter flag was the mistake; refusing to
forward it would be a different one.

**Done.** `defines.dart` deleted; `DartDefine`, `DefineSource` as a noun,
`DartDefineEntry`, `Entrypoint.defines:`, `definesFor`, `_defineEntry`,
`optionsFor`, `_checkDefineNames`, `_resolveDefines`, the Defines block and
`_KnobField`'s define renderer all gone, and B1's union with them. The launch
action's `defines` parameter is now `dartDefines`, forwarded verbatim.

**Kept and re-hosted rather than deleted**: `define_scripts.dart` (the script
runner) and the host-address enumeration, which now serve `ValueSource` on
knobs. The four script-source tests were *ported*, not dropped — the mechanism
survives, so its coverage should: a source this build cannot read leaves the
knob usable, a script computes the value a launch uses, a script that cannot
answer refuses the launch, and a value the caller gave launches past a script
that failed.

**This repo's own config went with it.** `examples/example`'s `FW_MARKER` was
the last `DartDefine` anywhere; it is now `void main({String fwMarker =
'<none>'})`, annotated with a label and a description in
`tool/flutterware.dart`. Verified end to end after the deletion: `entrypoints`
reports the knob and no `defines` key at all, and a launch carrying both
`--knobs=fwMarker=after-K6` and `--dartDefines=SOMETHING_UNMODELLED=x` put
`FW_MARKER: after-K6` on the screen.

## K7. Enums: bounded syntactic lookup — **built 2026-08-13**

**An overclaim, corrected, then decided.** E2 proved the wrapper can *pass*
`entry.Backend.staging` — but that wrapper was hand-written by someone who knew
`Backend` was an enum and what its values were. Discovery is a different
question, and `2026-07-27-knobs-static-and-runtime.md` had flagged it for demos:

> *"a syntactic scan sees the type name, not that it is an enum or what its
> values are. The generated wrapper could emit `Severity.values` and let the
> compile fail if it is not an enum — fragile. Resolving properly means the
> scanner stops being purely syntactic."*

**Decided: look the enum up syntactically, in a bounded scope.** Not resolution
(E4 measured that at 5.5s cold), and not config-supplied options, which would
restate the enum's values in `tool/flutterware.dart` — the drift this design
exists to remove.

The scope is the one thing that makes it honest:

- **The entry point's own file, plus the exported namespace of each direct
  import.** `export` is followed transitively, because a barrel — `export
  'src/backend.dart';` in `models.dart` — is what people actually write.
  `import` chains are *not* followed: that is the bound.
- **`show` / `hide` are honoured.** They are cheap syntax, and honouring them
  removes the only case that could produce a false ambiguity.
- **Found exactly once** → a `picker` whose options are the enum's value names.
  **Found nowhere** → the knob is omitted with a stated reason, following
  `KnobKind`'s own doctrine: *"a knob rendered as the wrong control is worse
  than a knob the panel admits it cannot show."* **Found more than once** →
  refused loudly rather than guessed.
- **Prefixes are preserved end to end.** A parameter typed `m.Backend` is
  emitted as `m.Backend.staging`, which works because K4 already copies
  `import 'models.dart' as m` into the wrapper.

It shares K4's import resolver — one helper, two consumers, and the reason both
sections are cheap is that neither needs anything the other does not.

**Measured 2026-08-13**, on the shapes people actually write rather than the
easy one: an enum declared in `src/backend.dart`, re-exported through a barrel
with a `show` combinator, imported under a prefix, including a value with
constructor arguments. Unwrapped it prints `main(Backend.dev, 1)`; through a
wrapper that copied the prefixed barrel import, `main(Backend.staging, 9)`.

**Built** as `app/lib/src/utils/enum_lookup.dart` — `EnumLookup.lookup(file:,
name:, prefix:)` returning values-or-a-problem, with a per-scan parse cache so N
parameters over one import list cost one pass. 15 tests. Two corrections the
build made:

- **The analyzer moved the AST.** `EnumDeclaration` in 13.x has no `.name` or
  `.constants`; it is `namePart.typeName` and `body.constants`, because a name
  part can now be a primary constructor. Nothing warns you — it is a plain
  compile error, and only once you write it.
- **A file that will not parse still answers.** `enum Backend { dev,,,` recovers
  into `Backend` with constants `[dev, '', '']`. Answering from a file the
  compiler will reject is fine — it will say so, loudly, seconds later — but a
  picker with two blank options is not, so empty constant names are dropped.
  Measured rather than assumed; the first version of that test asserted the
  opposite and was wrong.

**This must be settled for demos and entry points together.** The two scanners
face the identical question, and answering it twice differently is how `Knobs`
stops being one word all the way down — so the lookup lands somewhere both can
call, and `2026-07-27-knobs-static-and-runtime.md`'s open question closes with
this one.

## What is out, and why

| | why |
|---|---|
| `DartDefine`, `DefineSource`, `Entrypoint.defines:` | replaced by `Knob` / `ValueSource` / `knobs:` |
| `scanDefines` and the whole scanning subsystem (~180 lines + 102 mentions in `run_core.dart`) | the signature is the list |
| **B1**, the declaration/scan union — *in the tree, comes out* | it fixed a defect in a mechanism that no longer exists |
| **B2** `onlyDeclared:` | narrowing is what a parameter list is |
| **B3** dependency-closure scan | built and reverted the same day; see below |
| entry-point import following | only needed to scope a scan that is gone |
| `@Knob` marker | restates what a parameter list already says |
| `@Value(command: sharedConst)` | the tool must read the value at build time; copying imports cannot do that, and a probe importing `package:flutter` will not compile |
| `Knob` the *runtime class*, the override map, `runGuest(knobs:)` | the wrapper passes arguments; there is no lookup to seed |
| per-package `parameters:` / `RunParameter` | a Dart variable shares it |

## Costs and limits

- **The app must be edited.** Adding parameters to `main` is a real change, per
  entry point, and nothing infers it.
- **Dev-loop only.** Release builds take the defaults.
- **Encodable types only.** The wrapper writes a literal: `String`, `int`,
  `double`, `bool` and enums are in (§ K7); `Duration` and simple const constructors
  probably; arbitrary objects are not. **E3** settles the set, and v1 refuses the
  rest loudly rather than generating a wrapper that will not compile.
- **A restart loses app state** — K5 exists so that is a choice, not a surprise.
- **A value read deep in a widget still wants a devbar variable.** Parameters are
  threaded from `main`; that is explicit and right for startup wiring, and a
  refactor for anything else.

## Naming: `Knob`, and it is not a collision

An earlier draft of this section said "knob" already meant three things and this
would add a fourth. That was wrong, and the repo says so out loud:
`lib/channels.dart:10` — the panels protocol reuses the catalog's knob
vocabulary, *"reused, not redefined"*; `lib/previews.dart:23` — *"One word, all
the way down: it is what `--knobs=` sets and what `KnobDescriptor` carries."*

There is **one** abstraction — a named, typed, editable value with a descriptor —
already hosted in two places: preview parameters, and devbar variables surfaced
over the panels channel. A launch knob is a name, a kind, a default and some
options. It is the third host, not a fourth meaning.

Which means the wire shape exists and should be reused rather than invented.
`KnobDescriptor` (`lib/src/ui_catalog/knob.dart`) already carries `name`,
`kind`, `value`, `defaultValue`, `options`, `min`, `max`, `step`,
`description`; `KnobKind` is `string | boolean | integer | number | picker`,
which is exactly the set a launch knob needs. Its own doc comment describes this
design before it existed: *"A declaration read straight off a demo's parameter
list would produce the same descriptors without running anything… The panel
should not be able to tell the difference."*

Consequences: `Entrypoint(knobs: …)`, the config class is `Knob`, the wire is
`KnobDescriptor`, and the panel renders it with the existing `KnobControl`.
`_KnobField` in `run_plugin.dart` stops being misnamed and starts being correct.
The declaration/descriptor split mirrors `DartDefine`/`DartDefineEntry` exactly.

`ValueSource` keeps its own name rather than becoming `KnobSource`: it reads as
"this knob's value comes from a script", which is what it does.

## Dogfood — **done 2026-08-13**

`main_dev.dart`'s `FLUTTERWARE_APP_ROOT` is now a parameter: `void main({String
appRoot = const String.fromEnvironment('FLUTTERWARE_APP_ROOT')})`. Launched as
*Studio (dev)* it is a knob on the run's own Knobs tab; launched by hand it takes
the define, so an IDE run configuration that predates this still works.
`CLAUDE.md` moved with it.

**A correction the dogfood forced.** This spec said the four `FLUTTERWARE_*`
constants belonged to `main_catalog_dev.dart` and that `main_dev.dart` never
reached them. `main_dev.dart` reads `FLUTTERWARE_APP_ROOT` itself — the
package-level scan attributed it to `main_catalog_dev.dart` because that file
sorts first and `scanDefines` keeps the first occurrence. Three of the four were
genuinely misplaced; that one was the scan being imprecise in a way that also
misled the person reading it.

Still defines, and not this design's case: `FLUTTER_SDK_ROOT`,
`FLUTTERWARE_ROOTS` and `FLUTTERWARE_PROJECT`, read only by
`main_catalog_dev.dart` and `main_embedder_dev.dart` — IDE-only entry points not
declared in `tool/flutterware.dart`, untouched since #73, and worth asking
whether they still earn their place before converting them.

**The bug the dogfood found, which no test would have.** `RunHandle` had three
hand-written field-by-field copies — `withKnobs`, `withService` and the one
`publish` *returns*. `knobs` was added to one. So a launch wrote the file
correctly, `publish` returned a handle without them, and the first
`refreshFromLog` a second later saved that back: the cockpit showed empty fields
for an app plainly running with values. Sixteen fields is too many to copy by
hand more than once, so there is now a single `_copy` and the three are one line
each.

## Order

1. ~~**K1 + K2 + K3 + K4, and the `RunCore` wiring**~~ — built 2026-08-13, and
   driven end to end. `Knob`/`ValueSource`/`Entrypoint(knobs:)` in the config;
   `entrypoint_knobs.dart` reads the signature and the imports;
   `writeGuestEntrypoint` writes the call; `RunCore.knobsFor` merges the two
   halves, `entrypoints` reports them and `launch` takes `knobs=name=value`.

   Measured against `examples/example` with a real `main({String apiHost, int
   serverPort, Backend backend})`: launched with
   `--knobs=apiHost=192.168.1.24,serverPort=8186,backend=staging` and the app
   showed `192.168.1.24:8186/staging`; rewriting the wrapper and restarting put
   `staging.example.com:9000/prod` on screen in **744ms**.

   **The end-to-end found what the unit tests could not.** Every value from the
   CLI or MCP is a `String`, and the wrapper wrote its literal from the
   *value's* runtime type — so `int serverPort` was handed `r'8186'` and the
   build died on *String can't be assigned to int*. The literal is now written
   for the type the **signature** declares, which is the only thing that knows.
   A value that does not fit its kind is refused by the action before anything
   is built (`serverPort takes a whole number, not "eight"`,
   `backend takes dev, staging, prod — not "nope"`), because otherwise the
   failure points at a generated file the user never wrote.
2. ~~**K5**~~ — built 2026-08-13.
3. **K7's lookup**, placed where the demo scanner can call it too — decided, and
   the one piece that must not be built twice.
4. **E3**, before the refusal message is designed around a guess.
5. **Dogfood** the catalog's four; update `CLAUDE.md`.
6. **K6's passthrough**, and delete the define subsystem.
7. **Web**, or a written statement that it is unmeasured.

## Measurements that outlive the design

- **E1/E2 — wrapper rewrite + hot restart:** 262/343/237 ms macOS, **263 ms**
  iOS simulator, **3067 ms** Android emulator, against **29.6 s** and **38.6 s**
  rebuilds. The iOS simulator is desktop-fast; Android is not.
- **E4 — analyzer resolution:** **5.5 s** cold on a Flutter-importing entry
  point, **9.9 s** on the GUI's own, **215 ms** warm in the same context. The
  price of ever wanting resolved types here.
- **`p.isWithin(x, x)` is false** — the workspace root is itself a package, in
  this repo and most monorepos.
- Optional named parameters on `main` are legal in Dart and Flutter, and a
  parameter default may be a `String.fromEnvironment`.

## What came before

- **B1 — declaration annotates the scan rather than replacing it.** Built
  2026-08-12 and currently in the tree. The old rule made the config authority,
  so declaring one define to attach a picker silently dropped every other one
  off the launch form and `_checkDefineNames` refused them at the CLI. Correct
  for its world; that world is deleted here, and it comes out with the rest.
- **B3 — scanning the dependency closure.** Built and reverted the same day: too
  much machinery for an unconfirmed case, and dogfooding took
  `examples/example` from one define to five by picking up flutterware's own
  scenario-runner internals.
- **The `Knob` runtime class.** Designed in full, spiked (E1), never built. Only
  the measurement outlived it — and it is what this design rests on.
- **The open question** — why the client declared `SERVER_URL` in
  `tool/flutterware.dart` at all — is now moot. Declaring is how you attach a
  computed source or a label, and nothing else.
