# Project identity: telling one running instance from another

**Status:** built. P0–P6 all landed; S1 and S2 answered and one of them changed
the design before it was written. What is left is in *Open questions* at the
bottom — none of it blocks anything.

A user runs one flutterware instance per repository, and several at once. #114
gave the app a real name and a per-project window title, which fixed *what the
app is called* but not *which repo this window is*: every instance now says
"Flutterware" identically in the Dock tooltip and ⌘-Tab, and the window title
only reaches the Window menu, Mission Control and the Dock icon's menu — never
the tile, never ⌘-Tab, never the window itself (`titleVisibility` is `.hidden`
so the shell can use that band).

So the surfaces a user actually scans first are all icon. This is about putting
identity there.

## What is already decided

Decided by rendering against three real repos — a 19-package monorepo, a
9-package one and a single-package project — not by argument. Details and the
rejected alternatives are in the session that produced them; the conclusions:

**The project's icon rides in a chip that replaces the cursor.** Not beside it —
*in its slot*. Beside it reads as two stickers; in its slot the lockup stays one
object, and the chip inherits a position the composition already accounted for.

It was also chosen so the chip could degrade into the flat cursor when too small
to resolve. That half turned out not to be reachable at runtime — see the size
ladder below and S2 — but the composition argument stands on its own.

**Chip geometry**, all derived from measured type metrics rather than eyeballed:

| | |
|---|---|
| size | 0.80 × the wordmark's ink height |
| vertical | **baseline-aligned** (centred makes it float — clearly worse at every size) |
| gap | 0.24em |
| corner radius | 0.225 × chip size — the tile's own ratio, which is what stops it reading as a sticker |
| edge | hairline white at 35%, 6px, **unconditional** |

The hairline is unconditional on purpose. The alternative was a plate for dark
icons, which needs a darkness classifier — and the first one written read the
wrong HSL channel and inverted its answer on the only two icons that mattered.
No classifier, no bug.

Reject 0.88: its top stops just short of the ascender and reads as a failed
alignment. Either align or be clearly short of it.

**Size ladder — and its limit, measured.** The chip needs 128px: at 64 a
detailed or dark icon collapses. A 64pt Dock tile on retina is 128 physical px,
so **the Dock gets the chip**.

There is no ladder below that at runtime, because there cannot be. S2 (below)
shows `applicationIconImage` ignores per-size representations: the Dock and the
switcher both take the largest and scale it themselves. So the runtime path
supplies **one image**, and the small contexts that would have got flat accent
art — menu bar, Finder list views — get a downsampled chip instead. Accepted.

The committed bundle art still has a real ladder (48px threshold, small art
below), because `.icns` genuinely carries per-size images. That is already
shipped in `app/tool/icon/generate.dart` and is unaffected — it just is not
per-project.

**Colour** is derived from the project icon: most saturated usable colour,
normalised to L=0.62 / S≥0.55. Normalisation is not optional — one of the icons
tested is near-black, and raw derivation makes it vanish into the tile.

**The colour registry is dropped for v1.** It existed to guarantee separation
when two projects derive similar hues (Chrome and Notes both landed on orange in
testing). With the chip primary and colour only serving ≤64px, that is not worth
shared mutable state under `~/.flutterware/` — see the `worktrees.json`
last-writer-wins problem in the worktree leak audit. Revisit if collisions are
reported.

**The tab border is rejected.** Colouring the active tab's outline was
prototyped live via hot reload and fails: a blue-ish project colour is
indistinguishable from the app's own focus accent (`#1a73e8`), and a red one
reads as an error. An outline on a control inherits whatever meaning the UI
already assigns to colour, and the project's colour is arbitrary by definition.
The chip has no such problem because it is a picture, not a semantic colour.

## Non-goals for v1

Status in the icon (build/test state on the cursor); per-worktree colour rather
than per-repo; the blurred-icon tile wash; the circular chip; the colour
registry. All explored, none rejected on merit — they are simply not needed to
make one window distinguishable from another.

## Phases

### P0 — Unblock — done

`#114` landed as `09612698`. The native-layer bundle path fix landed separately
as #113 and is rename-safe: it globs `.endsWith('.app')` and identifies the
bundle by which process is running, so #114 renaming `app.app` to
`Flutterware.app` did not break it. Nothing here is outstanding.

### P1 — The declaration — done

Mirror `fw.changes(...)`: a project-level declaration that is **not** a plugin,
and refuses a second call rather than merging.

```dart
fw.identity(ProjectIdentity(package: webApp, icon: 'assets/logo.png'));
```

Deliberately not an extension of the `LauncherIcon` plugin. `icon_core.dart`
states that plugin's independence as a feature — it reports what the OS shows and
reads no generator config — and hanging window identity off it would couple the
two.

Plumb through `FlutterwareConfig.toManifest()` and expose a resolved value on the
worktree session. Unit tests for: absent, present, double call, package that does
not exist.

### P2 — Bootstrap at `init` — done

The launcher already scaffolds `tool/flutterware.dart` when a project has none.
That is where the guess belongs — its output is a line the user reads and edits,
not a permanent silent inference.

Algorithm, verified to pick correctly on all three repos in ~1s across 29
packages: consider packages with platform directories; score by **count of
platforms whose launcher icon is not the `flutter create` default**; demote paths
containing `example`/`demo`; tie-break on total platforms, then path depth.

Platform count alone is not enough — in one monorepo a five-platform app would
win on count, but its iOS and Android icons are stock. Hashing against the known
defaults did the real work, and also correctly demoted both `/example` packages
and left a macOS-only utility fourth.

Ship the default-icon hashes with it.

### P3 — Resolve the icon — done, then replaced

Shipped as: given the declared package, find its best available icon (the
launcher-icon scan already knows the per-platform paths), decode, cache per
worktree session. Must handle, because all three occur in the wild: no icon at
all; a stock Flutter icon; a logo with a transparent or non-solid background.

The search is gone — the declaration names the file. See the note under
**Risks**; the middle case above is what took it down.

### P4 — Compose the tile — done

Do **not** re-draw the wordmark at runtime. Add a fourth source to
`app/tool/icon/generate.dart` — the tile with no cursor — and ship it as a PNG
alongside the others. At runtime: draw base, draw chip into a constant rect
derived from the same measured layout, draw the hairline.

The chip rect is a constant because the wordmark is fixed; it should be emitted
by the generator into a small Dart constant so the two cannot drift.

One image, not a set — see S2. Compose at 512px or 1024px and let macOS scale;
there is nothing to gain from supplying more representations.

### P5 — The Dock — done

Extend the `flutterware/window` channel (added in #114) with `setIcon(bytes)`,
calling `NSApplication.shared.applicationIconImage`. Set after first frame; re-set
when the identity or worktree changes.

### P6 — In-app — done

One chip at the leading edge of the tab band, in `_bandContent`
(`app/lib/src/shell/shell_view.dart`), after `_SidebarButton`. **Once per window,
not per tab** — tabs are worktrees and identity is per repo, so a per-tab chip
would repeat the same image across every tab.

Needs a gap or separator: in the prototype it sat directly against
`_ExplorerTab`'s own icon, giving two small glyphs with nothing between them.

## Spikes — run 2026-08-12

Probe: a standalone AppKit binary setting `applicationIconImage` to an `NSImage`
carrying four flat-colour representations — 16px red, 32px green, 128px blue,
512px yellow — so whichever macOS picks is readable off a screenshot.

**S1 — Does `applicationIconImage` reach ⌘-Tab? → Yes.** The probe's tile appears
in the switcher alongside the Dock. So the runtime path covers both surfaces a
user scans first, and P5 is worth building.

**S2 — Can one `NSImage` carry per-size art? → No.** Both the Dock tile and the
switcher render the **512px** representation downsampled, not the 128px one.

The interesting part is that this contradicts the in-process answer. Asked
directly, `NSImage.bestRepresentation(for:)` picks correctly and even accounts
for the 2× backing scale:

```
request 16pt -> representation 32px      request 128pt -> representation 512px
request 32pt -> representation 128px     request 256pt -> representation 512px
request 64pt -> representation 128px     request 512pt -> representation 512px
```

A 64pt request resolves to the 128px rep exactly as the ladder wanted — but the
Dock is a different process and does not use those semantics. Do not reason about
this from `bestRepresentation`; it will tell you the ladder works.

**Consequences.** The runtime path supplies one image, composed for 128px+.
The flat-accent-below-128 idea is dropped from it. Colour's remaining jobs are
narrower than the original design assumed: the fallback when a project has no
usable icon, and optionally a ring on the chip.

If true per-size art is ever wanted, it has to be a baked `.icns` in the
per-project bundle — hosted installs already get their own `~/.flutterware/<sha1>/`
directory, so it is possible. But it is build-time, so it cannot follow a
worktree switch. Not v1.

**S3 — Cost of compose + set at startup.** Not yet run. Expected trivial; if not,
it moves after first frame.

## Risks

**Arbitrary user icons.** The hairline fixes edges, not content. A logo that is a
white glyph on transparency will be invisible on the dark tile. Mitigation:
composite onto the sampled background colour (the technique works — it was
verified while prototyping the "belly" idea, which was itself rejected), or a
neutral plate when the background is not solid.

**A declared package with a stock icon.** Falls back to colour-only. Should be
silent, not an error — it is the normal state of a young project.

> **Superseded by what actually happened.** P3 shipped as a search — best
> available icon per platform, skipping any file whose bytes matched a
> `flutter create` default — and the skipping is what broke. A real mobile app
> whose generator writes `ios:` and `android:` and never touches `macos/` got the
> Flutter logo in its Dock: the macOS icon there *was* the template's, from an
> older Flutter than the hashes had been taken from, so it hashed to nothing and
> ranked first for being the largest art in the package. Nothing on screen could
> say why.
>
> The risk above assumed the stock check would hold. It cannot: a byte-exact list
> of somebody else's template files is a promise that expires on their schedule,
> and it fails *silently and wrongly* rather than loudly. `ProjectIdentity` now
> takes a required `icon:` path relative to the package, resolved and reported —
> a path that is not there, or a format Flutter has no decoder for, is an error
> on the worktree rather than a window that quietly looks like every other one.
>
> The hashes survive in `stock_icons.dart` for the P2 `init` guess alone, where
> going stale costs a scaffolded line under a comment saying it was guessed.

**The icon changing on disk** while the app runs. v1 reads at worktree open and
does not watch.

## Open questions for Xavier

1. Should the colour appear in-app at all — as a ring on the chip — or stay
   Dock-only?
2. If the declared package has no usable icon, show nothing, or a flat colour
   block?
3. Does the chip belong anywhere besides the band — the worktree switcher rows,
   the explorer?
