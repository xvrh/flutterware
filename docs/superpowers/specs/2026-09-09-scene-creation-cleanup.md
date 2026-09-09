# Making a scene, a folder and a library: one model, one verb

Decided 2026-09-09, after the library moved to its own page
(`2026-09-07-scene-tokens-conversion.md` §9). That round fixed what a library
*is*. This one fixes how you get one, where it goes, and what the tool writes
into your files while you are not looking.

## 1. What was wrong

### 1.1 A scene's home is its position; a library's was a list

| Noun | What it is | Where it may live | How you made one |
|---|---|---|---|
| group | a folder with `scenes.dart` | any folder | "New group" → type a path |
| scene | `*.scene.dart` | under a group — nearest above wins | "New scene" → name + size |
| library | `*.tokens.dart` | **anywhere at all** | "New library" → name + folder + group |

Two rules answering one question — *who can read this?* — and only the scene's
rule is a rule you can see. A library's answer lived in `libraries: [brandTokens]`
in the group file, maintained by hand through an Attach/Detach menu behind a `⋯`.

The measured consequence, found in this worktree: `examples/example/lib/machin.tokens.dart`,
one token called `color`, drawn in amber as *listed by no group* — a file the tool
offered to make and then let you not use. Nothing about the flow suggested the
second step existed until the row turned amber.

### 1.2 The create buttons had no order, but the model does

You cannot have a scene without a group; a library reaches nothing until a group
lists it. The header offered **New library** and **New group** as equals, and
**New scene** was not there at all — it sat on a group row, reachable only after
pressing one of the other two. On an empty package the only two buttons that
could be pressed were the two that produce nothing you can look at.

### 1.3 The forms

- **New library**: three fields, no labels between them — a hint reading `Brand`,
  a mono field reading `lib`, a picker reading *Listed by no group yet*. The
  folder field and the group picker contradict each other: picking a group
  silently overwrites what you typed.
- **New group**: a path in a text box, prefilled `lib/scenes/` — and that prefill
  is *also* the sentinel for empty, so Create with nothing typed does nothing and
  says nothing.
- **All three anchors** are `FwActionButton`, which flips its label to **"Done"**
  when its `onPressed` future completes. Opening a popover completes instantly, so
  every one of the three announced success at the moment you started.

### 1.4 The words were the implementation's

*group*, *listed by*, *attach*, *export*, and on every group row
`1 library · 3 widgets · 3 exports` — which is called the vocabulary in the code
and reads like it.

### 1.5 The tool wrote an essay into every file

9 comment lines into `scenes.dart`, 7 into every `.scene.dart`, 5 into every
`.tokens.dart`, 7 into the generated `scene_args.dart`. `machin.tokens.dart` was
five lines of explanation over one line of content. `scene_args.dart` spent seven
lines describing itself *after* saying "Do not edit."

## 2. The decisions

### 2.1 A library goes where a scene goes

A `*.tokens.dart` is **read by the scenes below it**. Inside a group's folder it
is that group's; in a folder above several groups it is read by all of them — the
same nearest-above walk that already assigns a scene to a group, run in the other
direction.

Formally, group `G` reads library at `P` iff `dirname(P) == G.directory` or
`G.directory` is within `dirname(P)`.

`libraries:` stays in `scenes.dart`, because the app process has to import the
values to render them — but it is **derived, not authored**. Attach, Detach, the
`⋯` menu, `listedBy` and the amber *listed by no group* all delete.

The rule is now one sentence you can say out loud, and it is the same sentence for
both file kinds: **where it sits is who reads it.**

**Reconciling, and why not on every scan.** The derived set is written when the
tool already has reason to touch the group — a library created, deleted or moved
under it. It is *not* written from the scan, because a scan runs on every disk
change and `scenes.dart` is hand-written code. A drift the tool did not cause
(you moved a file in your editor, or hand-listed something that is not below)
shows on the group row as one line with one affordance that fixes it. Silent
rewriting of a file the human owns is the thing this design is trying to stop, not
a tool to reach for.

**Migration.** A library that is listed but not positioned below gets that drift
line, naming the folder it would have to move to. `brand.tokens.dart` already sits
in `demo/` and is already listed by `demo`: the example conforms untouched.

### 2.2 New scene is the only creation verb

A group stops being something you make and becomes what it is: a folder that has
scenes in it. **New scene** takes a name, a size, and a *where*; if the folder is
not a group yet it writes `scenes.dart` too, and says so afterwards in the note
line. The empty state's one button is New scene, and it lands you on a canvas
rather than in an empty folder.

**The "where" is the part that has to be good**, because it is the only place the
model is still visible. It is a choice list, not a text field:

```
New scene
  Name   [ PromoBadge                    ]
  Size   [ Banner 1024 × 500          ▾  ]
  Where
    ●  demo                 examples/example/demo · 8 scenes
    ○  marketing            lib/marketing · 2 scenes
    ○  A new folder…        [ lib/scenes                    ]

    Writes  lib/scenes/scenes.dart
            lib/scenes/promo_badge.scene.dart
                                            [ Create ]
```

Three things earn their place there:

- **Every existing home is offered by name**, with its path and how many scenes it
  already holds — so picking one is recognition, not recall.
- **"A new folder…" is the last row of the same list**, not a separate mode. It
  reveals one path field. When the package has no group at all, this row is the
  only row and starts expanded.
- **The paths that will be written are printed before you press Create.** That is
  what makes the implicit `scenes.dart` honest: the second file is named, not
  sprung on you.

This needs a control that does not exist: a vertical single-choice list with a
title and a caption per row. It goes in `app/lib/src/ui/` as `FwChoiceList`, built
from tokens, with a catalog demo in `app/tool/catalog/demos/` — light and dark —
the way `FwPicker` was extracted. A dropdown is wrong here: with two to five homes
a list is the whole answer at a glance, and the last row has to expand.

**New library moves onto the group row.** Not a top-level button competing with
New scene, but an affordance on the folder it belongs to, plus the library page's
own empty state. It loses the folder field and the group picker entirely: it takes
a name. There is no other kind of library to make.

### 2.3 The tool writes one line into a file it owns

`.scene.dart`, `.tokens.dart` and `scene_args.dart` carry their machine-readable
marker and nothing else. Discovery stays a walk and a first line; the prose moves
to the panel and the docs, where someone who has not opened the file can read it.

`scenes.dart` is the exception, because it is the only file in the system a human
hand-writes: it keeps about four lines, one clause per slot, and loses the essay.

About 28 emitted comment lines become about 5.

### 2.4 The screen stops speaking the implementation's language

*library* and *scene* stay — they are the words in use. *group* mostly disappears
in favour of the folder's own name, and the internal terms go:

| Was | Is |
|---|---|
| `1 library · 3 widgets · 3 exports` | `8 scenes · reads brandTokens · 3 widgets and 3 values from the app` |
| `listed by demo` | `read by demo` |
| `listed by no group` (amber) | `in lib/ — no scenes below it` |
| `No scene groups` / *a scene group is a folder with a scenes.dart in it…* | `No scenes yet` / *New scene makes one, and the folder to keep it in.* |
| `3 scene files outside any group — not scenes the tool knows` | `3 .scene.dart files the tool doesn't read — nothing above them says they're scenes` |
| `none yet — a library is a *tokens.dart the editor owns` | (deleted — the section says it) |

## 3. The work

**P0 — the words, and the button that lied. Landed 2026-09-09.** Every string on
the index page per §2.4, composed in `app/lib/src/scene/ui/listing_words.dart`
rather than inline in the panel, so the empty cases can be read and tested
without mounting one. `FwActionButton` gained `acknowledges` — false for a button
that opens rather than does; a failure is still reported, since an open that
throws is worth knowing about. The three scene anchors pass it. No model change.

The empty state still names New group, because in P0 that button still exists;
P2 collapses that sentence with the button.

**P1 — position decides. Landed 2026-09-09.** `readsLibrary` in
`discovery.dart` is the rule, with `librariesFor` and `groupsReading` the two
walks over it; `listedBy` is gone from the panel. `SceneCore.driftFor` /
`reconcileLibraries` are the gap and the one action that closes it — `createLibrary`
and `importTokens` reconcile because the tool caused the write, and nothing else
does. Attach, Detach and the `⋯` menu delete; the menu's one survivor, Import
variables, is now its own icon.

Two things the writing turned up that §2.1 had not said:

- **A moved library breaks the declaration outright**, because the import it
  leaves behind resolves to nothing and `parseGroupFile` refuses the whole file
  — so there is no vocabulary to read the stray entry out of. `driftFor` parses
  the declaration itself, resolving a symbol by *name* rather than by what the
  scan found, which is what lets the fix name the entry that has to go. Without
  that, the commonest drift showed as a red refusal about symbols and had no fix
  at all.
- **A listed library that is below but no longer exists is stray too.** One
  clause covers both: readable from here means below this folder *and* still
  there.

The New library form loses its group picker as an attachment and gains it as a
folder shorthand — "In demo's folder" / "Somewhere else…" — under a live read-out
of who would read the file, amber when that is nobody. That read-out is the
position rule made visible at the one moment it matters, and the seed of P2's
where-list.

**P2 — one verb. Landed 2026-09-09.** `FwChoiceList` is in `app/lib/src/ui/`
with a catalog demo in both themes, looked at before it shipped. The New scene
popover has labelled fields (`fieldLabel`, which the old forms used for nothing —
they were three hints in a column), the where-list, and the written-paths
preview. `_createScene` writes the declaration on the way when the folder is not
a group yet. `_NewGroupButton` is gone, and so is the panel's `_createGroup`.

The header is now `New library` and `New scene`, the latter primary; each folder
row keeps its own `New scene`, which passes `allowNewFolder: false` and so shows
no where-list at all — the row *is* the where.

**One deviation from §2.2, deliberate: New library stays in the header.** The
spec moved it to the group row on the grounds that a top-level library button
competes with New scene. P1 removed the reason: the form now says who would read
the file, live, amber when that is nobody. Moving it onto a row would also delete
the only way to make a library that several groups share, since a row can only
ever mean its own folder — and the position rule exists precisely so that case is
expressible. Two buttons that both name a noun and both say where the file lands
are not the old problem; the old problem was three buttons with no order between
them, one of which produced nothing you could look at.

The `newGroup` **action** survives even though the button does not: an agent
asking for a folder on its own is a reasonable primitive. See P4.

**P3 — the prose. Landed 2026-09-09.** A `.scene.dart` and a `*.tokens.dart`
now open on their marker and then their content; `scene_args.dart` keeps the one
line a generated file owes its reader, that it is generated. `scenes.dart` keeps
four, one per slot:

```
//@flutterware:scenes=1
// widgets   the app's widgets a scene may place, with their arguments
// exports   the app's own values, named for the scenes — any type
// libraries the *.tokens.dart these scenes read, imported above
// wrap      what the canvas is mounted under — the app's theme
```

28 emitted comment lines became 5. The fixtures under `app/test/scene/` and
`examples/example/demo/` were stripped to match, and the example's own
`scenes.dart` — the file that stands in for a consumer's — lost sixteen lines of its own.

One fixture keeps its comment on purpose: `app/test/scene/scenes.dart` explains
what that group is *for the reader of the test suite*, which is repo
documentation and not something the tool ever wrote.

**P4 — the action surface. Landed 2026-09-09.** The wording pass deferred through
P0–P2: `list`, `video`, `newLibrary` and `importTokens` stopped saying "scene
group" and "the group's folder", and `newGroup` is now titled *New folder of
scenes* and describes itself as the low-level half.

Writing those descriptions turned up the hole they were papering over: **the
panel's one verb had no action at all.** An agent could make a folder and a
library — neither of which is worth having on its own — and not the thing they
exist for. So `newScene` exists now, taking a name, an optional folder (defaulting
to the folder that already keeps scenes) and an artboard, writing the declaration
on the way exactly as the form does and naming it back as `alsoWrote`.

Scene creation moved into `SceneCore.createScene` for it, which is the same door
the panel now goes through — the panel and an agent cannot drift apart on what
making a scene means, and the class-name refusal is written once.

Result keys were left alone. They are what an agent's code reads, and `groups`
is still exactly what the walk returns; renaming a key to improve prose is a
break for no reading gained.

## 4. What this does not change

The file grammar, the markers, the generated `SceneTokens`, the override door for
dark mode, and the rule that a library holds a design system. Nothing here touches
the published half.
