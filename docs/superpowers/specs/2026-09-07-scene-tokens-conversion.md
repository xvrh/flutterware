# Tokens have two owners, and a scene group is a folder

A conversion plan for what M5–M7 built (`2026-09-05-scene-master-plan.md`),
after the first read of it on 2026-09-07. Two decisions change everything
below. **A token is owned either by the editor or by the app, and the two
are different things with different UI.** And **the unit of configuration is
a scene group: one folder, one declaration file, everything else discovered
or generated.** M5 built one kind of token and put it on the wrong side, and
the demo folder shows what the configuration story had become: five support
files for one set of scenes.

## 1. What is wrong with what exists

M5 made `scene_tokens.dart` a file the user writes by hand and the editor
only reads. That forced the value into the file as a literal
(`SceneColor(0xFFE8632B)`), because the editor has to draw the value and the
reconciler has to compare against it, and the editor never compiles the app.
Two consequences, both unacceptable:

- **A user with an existing palette cannot re-export it.** Their colours are
  `AppColors.brand`, a `Color` in a file they own. The only way in was to
  copy the number. The literal was the design.
- **The editor has no UI for the thing it is supposed to manage.** No panel,
  no add, no rename, no value editing, no mode columns. Everything built is
  read-side: a picker, a mode switch, a generated class.

The opaque path (M5b) was the right shape for the wrong reason: a name and
a type the editor offers and the guest resolves. It was restricted to
non-value types because value types "needed" the literal. They do not; they
need an owner.

And the configuration grew by accretion. Today a package's scene directory
holds, beside the scene files: `scene_externals.dart` (hand-written),
`scene_tokens.dart` (hand-written), `scene_args.dart` (generated),
`scene_host.dart` (hand-written, the guest) and `scene_canvas.dart`
(hand-written, the two `@Preview` entries the guest boots from), and
`tool/flutterware.dart` names the directory. Five support files, three of
them boilerplate, one library per package, one set of widgets per package,
and no way to say that one set of scenes sees one thing and another set
sees another.

## 2. The split

| | **Library token** | **External token** |
|---|---|---|
| owner | the editor | the app |
| file | a `*.tokens.dart`, editor-owned, editor-written | the group's `scenes.dart`, hand-written, beside the widgets |
| spelled | `Token<SceneColor>('brand', SceneColor(0xFF…), modes: {…})` | `Token<Color>('brand', AppColors.brand)` — any type, any expression |
| the editor knows | name, kind, value per mode | name, type |
| the editor draws | the value | nothing; the preview shows the result |
| modes | yes, columns in the panel | no; the app's expression is what it is |
| on an edit of a bound property | detach (unchanged) | detach is impossible; unbind only |
| in the generated class | a const field with the literal as default, one static per mode | a getter that resolves the declaration and converts |
| import from a design file | lands here, merged by name | never |

The literal stays, and stops being a problem: it is the editor's spelling in
a file the editor writes, exactly as a `.scene.dart` node is. Nobody types
it. A user who wants a literal token creates it in the panel; a user who has
the value already re-exports it as an external token by naming it, once.

**The split is by owner, not by type.** A colour can be either. From the
library the editor draws it and compares against it; from the app the editor
names it and the guest renders it. The generated `SceneTokens` class carries
both, so a scene file spells `tokens.brand` the same way whichever it is.

## 3. Configuration: a group is a folder

### 3.1 Three kinds of file, and the tool asks for nothing else

```
lib/marketing/scenes/
  scenes.dart               hand-written: the group's declaration
  scene_args.dart           generated: Args classes, SceneTokens, the host entries
  store_banner.scene.dart   editor-owned
  story_card.scene.dart     editor-owned
lib/design/
  brand.tokens.dart         editor-owned: a library, shared by any group that imports it
```

**A scene group is a folder with a `scenes.dart` in it.** The scenes are
the `*.scene.dart` files below that folder. The declaration says what those
scenes may use — the app's widgets, the app's exported values, and which
token libraries — and gives the guest its wrapper. It is ordinary Dart the
app compiles; the tool reads it as text the way it reads the externals file
today, skipping the closures.

```dart
//@flutterware:scenes
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';
import '../../design/brand.tokens.dart';
import '../../shop/shop_app.dart' as app;

final scenes = SceneGroup(
  libraries: [brandTokens],
  widgets: [
    ExternalWidget('OrderButton',
      args: [Arg<String>('label', 'Order now'), Arg<ButtonStyle>('style')],
      build: (a) => app.OrderButton(label: a.text('label') ?? 'Order now',
                                    style: a.raw('style') as ButtonStyle?)),
  ],
  exports: [
    Token<Color>('shopBrand', app.brandColor),
    Token<TextStyle>('shopTitle', app.textTheme.title),
    Token<ButtonStyle>('cta', app.ctaStyle),
  ],
  wrap: (child) => MaterialApp(theme: app.theme, home: child),
);
```

**A token library is a `*.tokens.dart` the editor owns.** Its symbol is
derived from its file name (`brand.tokens.dart` declares `brandTokens`), so
a group names the libraries it sees by importing them and listing the
symbols. The tool resolves each listed symbol through the declaration file's
imports to a marker file — a lookup over import URIs, not a resolver. A
symbol no import provides, or two imports provide, is refused by name.

**Everything else is discovered or generated.** Groups are found by marker,
the way scenes are: walk the package, read first lines. `tool/flutterware.dart`
keeps `Scene(packages: [ScenePackage(app)])` and the optional `directory:`
as a scan scope for a large package, nothing more. The generated
`scene_args.dart` gains the two `@Preview` entries the guest boots from,
written against the group's declaration, so `scene_host.dart` and
`scene_canvas.dart` are deleted from the demo and never written by a user:

```dart
@Preview(name: 'Scene canvas host') Widget sceneCanvasHost() => SceneCanvasHost.of(scenes);
@Preview(name: 'Scene player')      Widget scenePlayer() => ScenePlayerHost.of(scenes, pair: …);
```

The guest boots the entry that lives in the group's own folder rather than
the one entry named `sceneCanvasHost` in the package, which is what lets two
groups coexist. The player entry an export walks is chosen the same way.

### 3.2 Several libraries, several groups

A group's `SceneTokens` is the union of the libraries it lists plus its
exports. A name declared twice across them is refused at scan and the class
is not written until it is fixed. Modes are unioned too: a library with a
`dark` mode and one without give a group a `SceneTokens.dark` in which the
second library's tokens keep their defaults.

Two groups may list the same library; a library edit in the panel reaches
every group that lists it, and regenerates each group's `scene_args.dart`.
A scene nests a scene of its own group only; cross-group nesting is refused
by name, and can be reconsidered when a real file wants it.

The scenes list in the studio groups by group. The outline's Tokens section
(§4.4) shows the group's union, with a divider per library and one for the
app's exports.

### 3.3 What a user writes, in one paragraph

Make a folder for a set of scenes and put a `scenes.dart` in it saying which
of your widgets and values they may use, with your app's theme around them.
Create tokens in the editor; it keeps them in a `*.tokens.dart` you can put
wherever every group that needs it can import it. The tool generates one
file beside your `scenes.dart` and never asks for anything else.

### 3.4 Discovered, not listed — and how the GUI shows it

**Groups and libraries are discovered by marker, never listed in
`tool/flutterware.dart`.** The same walk that finds scene files reads the
first line of every `scenes.dart` and `*.tokens.dart` under the package's
scan scope (`lib`, or `directory:` when a large package narrows it). A list
in the config would repeat what the folder already says and drift from it;
the previews plugin took the same position ("found wherever they were
written") and it has held. The config's whole job is `Scene(packages:
[ScenePackage(app)])`.

**The sidebar keeps one row per package. The package page is where groups
live.** Today that page is a flat list of scenes; it becomes a list of
groups, each a section: the folder name as its title, its path, its scenes
beneath, and one line of what it sees (*2 libraries · 3 widgets · 4
exports*). *New scene* sits on each group; *New group* sits on the page
header. Opening a scene keeps the page's shape in the header crumb: *group ›
scene*, and the `fw://` address gains the group segment, so a deep link
names the folder.

**Libraries have a section on the same page**, after the groups: every
`*.tokens.dart` found, with its token count and which groups list it. A
library no group lists is still there — not lost, just unused — with *Attach
to group…* beside it. That is the whole answer to "where is my library":
the page lists what the walk found, wherever it was written.

**Creating from the GUI writes files where the story says they go.**

- *New group* asks for a folder, rooted at the package, defaulting to
  `lib/scenes/<name>/`, and writes a `scenes.dart` skeleton there: empty
  `widgets`, `exports`, `libraries`, and a `wrap` that mounts a bare
  `MaterialApp`. The generated file follows on the next scan. Discovery
  picks the folder up at once; nothing else to register.
- *New library*, from a group's Tokens section, writes
  `<name>.tokens.dart` **in that group's folder** and attaches it to the
  group. From the package page it asks for a folder, defaulting to the
  package's `lib/`. Either way the file is a marker file the walk finds, so
  where it sits only decides who can import it.
- *Attach to group* adds the import and the list element to that group's
  `scenes.dart` — the one edit the tool makes to a hand-written file
  (§7). Detaching removes them. Moving a library file is an IDE refactor
  that fixes the imports; the tool's next scan finds it in its new place.

**No migration.** Nothing shipped on the old shape, so a `.scene.dart` with
no `scenes.dart` above it is simply not a scene the tool knows; the package
page says how many such files the walk passed, in one line, and that is all.

**Entries the generator writes are the guest's, not the previews plugin's
audience.** The two `@Preview` entries in each `scene_args.dart` carry a
group of their own (`group: 'Scene guests'`) so the previews listing folds
them together rather than scattering one *Scene canvas host* per folder
through the catalog.

## 4. Decisions on tokens

### 4.1 A library file is editor-owned, like a scene file

Same header discipline as `.scene.dart`: a marker line, a comment that says
the editor writes the whole file and hand edits inside the grammar are
welcome, ordinary Dart that compiles. The grammar gains one thing the current
file cannot say — **a mode with no differing value yet**:

```dart
//@flutterware:tokens=1
const brandTokenModes = ['dark'];

final brandTokens = [
  Token<SceneColor>('brand', SceneColor(0xFFE8632B), modes: {'dark': SceneColor(0xFFFF8A5C)}),
  Token<double>('radius', 28),
  Token<SceneTextStyle>('title', SceneTextStyle(fontSize: 54, weight: SceneFontWeight.w700)),
];
```

Modes are a library-level list; a token holds a value per mode it differs
in. Styles take modes like any other value: the value per mode is a whole
`SceneTextStyle`.

Written by the editor through the same door as scenes: parse → document →
emit, autosaved, disk-watched, an external change adopted as a journal
entry. A library is one document, shared by every open scene of every group
that lists it, which is new: today each `SceneDocument` holds its own copy
of the list.

### 4.2 External tokens are the group's exports

`SceneGroup.exports` is a list of the same `Token<T>` class, any `T`, any
expression. The reader records the name and the spelled type argument and
never looks at the expression. The type argument decides where the editor
offers the token:

| declared type | offered on |
|---|---|
| `Color` | every colour property, and `Arg<Color>` |
| `double`, `String`, `bool` | properties of that kind, and args of that type |
| `TextStyle` | the style slot of a text |
| anything else | external widget arguments of that type only (today's opaque path) |

A `Color` on `fill` travels the wire as the same marker the opaque path
already uses, `{'token': 'shopBrand'}`, in place of the ARGB. The guest
resolves it in `bindExternals` against the real objects, which it holds
because it compiled the declaration. The marker stops being an argument-only
convention and becomes a value the wire can carry wherever a value goes;
the decoder gains one case per value kind.

**A `TextStyle` export is applied under the node, not read into it.** The
editor does not know which properties it sets, so the inspector shows
`style ← tokens.shopTitle · from the app` and no per-property chips; the
emitter writes every text property the node spells and infers nothing; the
parser applies nothing from the style. The guest lays the app's `TextStyle`
under the spelled properties. The equal-means-inherited rule (§7.1 of the
master plan) applies to library styles only, where the value is known.

### 4.3 The generated class converts at the getter

A library token is a const field with the literal as its default and one
static set per mode, as today. An export is a getter that reads the
declaration at the moment a scene asks (today's `_token(name)` lookup) and
converts to the editor's type when the scene needs the editor's type:

```dart
SceneColor get shopBrand => sceneColorOf(_export('shopBrand') as Color);
SceneTextStyle get shopTitle => sceneTextStyleOf(_export('shopTitle') as TextStyle);
ButtonStyle get cta => _export('cta') as ButtonStyle;
```

`sceneColorOf` and `sceneTextStyleOf` live in the Flutter bridge
(`lib/scene.dart`), not in the authoring core, which stays free of `dart:ui`.
The generated file may import the bridge: it is in the app. A
`TextStyle`→`SceneTextStyle` conversion takes the properties the table knows
and drops the rest; the renderer in the guest sees the full `TextStyle`
anyway, so the app's letter spacing is on the canvas even though the editor
cannot name it.

### 4.4 The library gets first-class UI, in the outline

A **Tokens** section under Motions in the outline, because the outline is
where the one-verb rule already lives: one click opens the thing in the
drawer. It shows the group's union: one divider per library the group
lists, one for *from the app*.

- Each library's tokens with a swatch or value; the exports with their type
  and no value. A `+` on a library adds a token: the kind menu (colour,
  number, text, switch, style), a free name, the default of the kind. A `+`
  on the section creates a library: a name, a file written in the group's
  folder and listed in `scenes.dart` — the one edit the tool makes to a
  hand-written file, an added import and an added list element, refused if
  the file does not parse.
- The drawer pane for a library token: name (inline rename), kind, one
  value editor per mode column (default first), *read by* as the list of
  readers across every group that lists the library, delete. Refusals: a
  name in use, a keyword, a delete while read anywhere.
- The drawer pane for a library (opened from its divider): the mode list —
  add, rename, delete a mode — and the import button.
- An export opens read-only: its type, where it is declared, its readers.

Editing a library value in the pane moves every reader in every open scene
at once and regenerates each listing group's `scene_args.dart`; every
canvas follows because the library is one shared document.

### 4.5 Editing a bound property still detaches

§4.1 of the master plan, *an edit reaches its source*, holds for parameters
because a parameter is scene-local and its default is the mockup. A library
token is shared across scenes. Typing over a token-bound colour on one node
and moving every banner in the package is the surprise design tools avoid by
detaching, and the panel is where the token's own value is edited.
Unchanged, and now stated for the reason it holds rather than the reason M5
gave (the file being hand-written).

### 4.6 In-file sharing is a parameter; the two moves

Decided 2026-09-07: **no in-file token library.** Inside a scene, a value
several nodes share is a parameter — it has the panel, the drawer pane, the
readers list and the bind menu already, and editing it moves every reader
(§4.1). The cost, that the value is also an argument of the scene, is
accepted: the default is the mockup, and a value worth naming inside a
scene is a value a caller may want to set. Across scenes, a shared value is
a library token. The reading rule is one line: a bare name is this scene's,
`tokens.` is the group's.

Two moves, one verb each, from the drawer pane:

- **Share** on a parameter: creates a library token in a chosen library
  with the parameter's default, rebinds this scene's readers from `tint` to
  `tokens.tint`, removes the parameter. Refused if the name is taken in the
  group's union.
- **Make local** on a library token, from inside a scene: creates a
  parameter with the token's default value, rebinds this scene's readers,
  leaves the token in the library for the other scenes. Modes do not come
  along, and the pane says so.

If a value shared inside one scene without exposing it ever hurts, a
`private` marker on a parameter is the smallest fix. Not planned.

### 4.7 Rename and delete reach every scene file that reads the library

New capability. A parameter rename touches one file; a token rename touches
every scene file that reads it, across every group that lists the library.
The library document knows its readers only for scenes that are open, so a
rename or delete first **scans those groups**: parse every scene file,
collect `TokenRef`/`StyleRef` by name. Rename rewrites each reading file
through parse → rename → emit and reports the files it touched; delete is
refused while any file reads the name, with the list. A scene file that
fails to parse blocks the rename by name rather than being skipped.

### 4.8 Import merges into a library

The importer stops owning a file. `scene importTokens --file --library`
merges by name into the named library: an existing token takes the imported
value and modes, a new one is added, a library token the file does not know
is left alone and listed in the report as *not in the design file*. Modes
are unioned. `--force` and the *imported file* marker go away; the refusals
list stays.

## 5. Milestones

Each shippable alone, in this order. The configuration comes first because
every later piece writes into the folder it defines.

**C1 — a group is a folder.** `SceneGroup` in the authoring library;
`scenes.dart` read as text (widgets, exports, libraries, and the wrapper
skipped); groups discovered by marker; `scene_args.dart` gains the host
entries and the guest boots the entry in the group's folder. The package
page as §3.4 draws it: groups as sections, the libraries section, *New
group*, *New library*, *Attach to group*; the
`fw://` address gains the group segment. The
tokens reader learns the `*.tokens.dart` marker and the derived symbol, and
the generator takes a list of libraries. Demo:
`scene_externals.dart`, `scene_tokens.dart`, `scene_host.dart` and
`scene_canvas.dart` become `demo/scenes.dart` and `demo/brand.tokens.dart`;
`tool/flutterware.dart` loses `directory:`. Lands: **the demo folder has
one hand-written support file, and a second group can exist.**

**C1 landed 2026-09-07.** As above, with three things the build settled:

- The generated file's two entries share their symbols across groups and
  are told apart by folder (`isGroupHostEntry`); the guest and the video
  export both pick the entry in the open file's folder.
- `importTokens` takes `--library` (a `*.tokens.dart` path, default
  `imported.tokens.dart` in the first group's folder) and, when no group
  lists the file it wrote and it sits in a group's folder, attaches it there
  — the one-step import the plan wanted from T4, brought forward because
  an unlisted library is a library nobody reads.
- The skeleton emitters live in `skeletons.dart`, apart from the readers,
  because the purity guard reads import lines even inside a string.

Two things it did not do: the `fw://` address does not carry the scene or
the group yet (it never carried the scene either — the panel holds it), and
the demo's declaration keeps `ctaStyle` as an export with today's opaque
rule, which T1 widens.

**T1 — the split in the reader, the wire and the generator.**
`SceneTokenDecl` gains an owner; value types are allowed on exports; the
marker travels on core properties and the guest resolves it; the generated
class converts at the getter; the context menu lists exports under *from
the app*; an export binding never auto-detaches. Demo: `ctaStyle` becomes
an export, one re-exported app colour and one app `TextStyle` join it, the
store banner reads one of them. Lands: **a user re-exports an existing
palette by naming it, and sees it on the canvas.** This is the part the
2026-09-07 feedback was about.

**T2 — the library document and its panel.** `TokensFile` beside
`SceneFile` in the workspace, one per library, shared by every open scene
that lists it, autosaved and disk-watched. The outline section, the token
pane, the library pane minus modes, *new library*. Add, rename, retype,
value editing, delete, readers, refusals. The two moves (§4.6). Rename and
delete across groups (§4.7). Lands: **tokens are managed in the editor.**

**T3 — modes in the panel.** Add, rename, delete a mode; a value per mode
for every kind including styles; the canvas picker reads the union's mode
list. Lands: light and dark authored in the editor rather than in a file.

**T4 — import merges.** §4.8, with the report shown in the library pane.
Lands: a design file's variables refresh a library the user has also edited,
without losing either side.

**Not planned, welcome when cheap:** the guest reporting each export's
resolved value on connect, so an app colour gets a swatch in the menu. A
bonus, never a dependency.

## 6. What this deletes

- `scene_externals.dart`, `scene_tokens.dart` as fixed names;
  `scene_host.dart` and `scene_canvas.dart` as things a user writes;
  `ScenePackage.directory` as the way a group is named.
- The single `sceneCanvasHost` symbol as the guest's registration; the
  entry in the group's folder replaces it.
- The premise in `tokens_file.dart`'s header that the tool only reads the
  file, and every consequence written from it.
- `isImportedTokensFile`, `--force`, and the *imported* marker.
- The opaque-only restriction on export types.
- `describeTokens`, once no host describes a hand-held list.

## 7. Hazards

- **One library, many editors.** Every `SceneDocument` today carries
  `tokens` as its own list; reconcile and `applyTokenMode` read it. It has to
  become a reference to the group's live union, with a change notification
  the scene editors subscribe to. The undo stacks stay per scene; a library
  edit is undone in the library, not in a scene.
- **The tool edits `scenes.dart` once.** Creating a library adds an import
  and a list element to a hand-written file. Do it through the parser with
  offsets, refuse when the file does not parse, and never touch anything
  else in it.
- **Symbol resolution through imports.** `libraries: [brandTokens]` resolves
  by reading the declaration file's import URIs and the marker files they
  point at. A `package:` import into another package of the workspace is
  fine; a library outside the workspace is refused by name.
- **Regeneration on every keystroke.** A value edit in the pane regenerates
  every listing group's `scene_args.dart`. Debounce it the way autosave is,
  and never mid-drag.
- **The marker in a value slot.** A map with a `token` key is now meaningful
  wherever a value is expected. The decoder must reject a marker that names
  no declared token rather than render a hole; a refusal, not a blank.
- **A `TextStyle` export under a library style.** A text holds one style
  binding. Export and library styles are the same slot; mixing is not a case.
- **Cross-file rename on a file the user has open elsewhere.** The disk
  watcher adopts the rewrite as an external change in that scene's editor,
  which is the existing behaviour; check that an unsaved edit there is not
  lost — refuse the rename while any reading scene is Unsaved.
- **Two guests for two groups.** The guest session selects one entry; a
  group switch selects another and pays a boot. Acceptable; a warm guest per
  group is a later optimisation if it hurts.

## 8. Open, for the reader of this plan

1. The name `scenes.dart` for the declaration file, and `SceneGroup` for
   the class. A folder is the group; the file is what it says about itself.
2. `wrap:` versus `theme:` on the group. `wrap` is one callback and covers a
   `MaterialApp`, a `CupertinoApp`, a `Directionality`; `theme` is sugar over
   the common case. Proposed: `wrap`, with `theme` added when three groups
   have written the same wrapper.
3. Whether `double`/`String`/`bool` exports are worth offering in T1, or
   only `Color` and `TextStyle`. Proposed: all, since the rule is one rule.
4. ~~Where a library created from the panel is written.~~ Answered in §3.4:
   the group's folder from inside a group, an asked-for folder from the
   package page, and *Attach to group* is how a second group reaches it.
5. Whether a group may carry a `label:` in its declaration, or the folder
   name is always the name. Proposed: the folder name, until one is ugly.
