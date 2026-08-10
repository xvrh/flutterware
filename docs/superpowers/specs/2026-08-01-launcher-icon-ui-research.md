# Launcher icon panel — UI research

**Date:** 2026-08-01
**Status:** Research. No code written from this yet.
**Subject:** `app/lib/src/launcher_icon/` — the panel shipped on 2026-08-01,
and what it would take for it to be good rather than merely correct.

## Why

The plugin reads the right things and says true things. Looked at in the
running app it is flat: six platform sections stacked down the left eighth of
the window, each a row of one to three 176px thumbnails, most of the width
empty. The information is there; the presentation is an inventory listing.

This is a research pass before rebuilding the layout. It has three parts —
what the repo already provides, what the rest of the world does with this exact
problem, and where the current build actually goes wrong.

## 1. What the repo already provides

### The token layer is real and complete

`app/lib/src/ui/design/` (ported in S2, `2026-07-26-s2-design-tokens-findings.md`):

- **Spacing** `FwSpacing.xxs 2 · xs 4 · sm 6 · md 8 · lg 12 · xl 16 · xxl 24 ·
  xxxl 32`, plus a `Gap(size)` widget that reads better than a bare `SizedBox`.
- **Typography** `pageTitle · heading · sectionLabel · body · bodyStrong ·
  bodyMuted · bodySmall · caption · micro · button · fieldLabel`.
- **Radii** `radiusSmall / radius / radiusLarge`, **elevation**, and the full
  `FwPalette` (accent ×4, panel/panel2/bg, ink/ink2, mut/mut2/mut3, line/line2,
  grn/amber/red).

Read through `context.colors`, `context.type`, `context.radii`,
`context.elevation`.

### There is a shared UI kit, and the current panel ignores most of it

`app/lib/src/ui/`: `breadcrumb`, `empty_state`, `popover`, `popover_menu`,
`side_menu`, `table`, `tappable`, `menu`, `json_view`, `matched_text`,
`command_palette`, `column_layout`.

Two direct hits against what was built:

- **`popover.dart`** is a proper anchored, dismissible popover with side/align
  control and a controller. The finding badge hand-rolls a `MenuAnchor` with a
  bespoke `MenuStyle` instead. Should be `Popover`.
- **`empty_state.dart`** is the house empty arm (`icon`, `title`, `message`,
  `action`) of the load → empty/error triad. The panel hand-rolls a centred
  `Text`.

### `device_frame` is already vendored and already used

`lib/src/third_party/device_frame/`, and `app/lib/src/catalog/catalog_view.dart`
already draws `DeviceFrame(device: chrome, screen: guest)` around a live guest.
`lib/src/devices.dart` is the shared device catalog — real dimensions, pixel
ratios and safe-area insets, with stable ids for addresses.

**Drawing an app icon on a real phone chrome is existing infrastructure, not new
work.** This is the single most important thing found in this pass.

### The house layout for "many items, one focus" is master–detail

`scenarios_plugin.dart:201` — a `Row` of `SizedBox(width: 240)` list pane, a
`VerticalDivider(width: 1)`, and `Expanded(child: detail)`, with an `EmptyState`
in the detail slot when nothing is picked. The list pane is deliberately always
visible: *"running a scenario never hides where you are in the suite."*

That is the answer to the wasted-width problem, and it is already the
established shape.

### The catalog is how UI is meant to be iterated here

`app/tool/catalog/demos/*.dart`, annotated with Flutter's own
`@Preview(name: …, group: …, wrapper: …)`, run from
`app/lib/main_catalog_dev.dart`. The house rule is **stacked variants, not a
picker** — every state rendered at once so overflow and collapse show up
without anyone selecting them.

`asset_inspector.dart` states the rule the launcher icon panel breaks:

> Everything here is synthesised … every preview is handed **bytes** rather than
> a path. That is the whole reason the views take data instead of reading files
> themselves.

## 2. What the rest of the world does

Convergent across every current tool
([adaptive-icons.com](https://www.adaptive-icons.com/),
[App Icon Creator](https://appiconcreator.com/),
[App Icon Checker](https://appiconchecker.vercel.app/),
[IconCraft](https://www.iconcraft.app/app-icon-mockup),
[Rami James' mockup tool](https://www.ramijames.com/tools/app-icon-mockup)):

1. **The preview is a device home screen, not a thumbnail.** Pixel-accurate
   chrome, status bar, wallpaper, and a *grid of neighbouring icons*.
2. **Neighbours are the point.** "See how legacy squares and squircles appear in
   the home screen grid." An icon's size and weight are only judgeable relative
   to other icons — which is exactly the macOS full-bleed problem the current
   panel can state but cannot *show*.
3. **All mask shapes at once**, not one at a time behind a picker. Android
   Studio's Image Asset Studio does the same.
4. **The safe zone is taught, not just drawn** — the 66×66dp circle inside the
   108×108dp canvas appears as an explicit diagram beside the preview.
5. Controls (padding, background colour, shape) sit beside the preview and
   update it live.

None of this is exotic. Points 1–4 are all reachable with what is already in
this repo.

## 3. Where the current build actually goes wrong

| Problem | Why it matters |
|---|---|
| **Inventory, not context.** Tiles are file thumbnails on a checkerboard. | Icons live on screens. A thumbnail cannot answer "is this too big", "does it read at a glance", "does it disappear against a dark wallpaper". |
| **No neighbours.** | Relative size and weight are unjudgeable. The macOS oversize finding is *stated* in prose and invisible in the picture. |
| **Platform-per-row wastes the width.** | Six sparse rows in the left eighth of a 1300px panel. Master–detail is the house answer and is already built next door. |
| **Kit ignored.** Hand-rolled popover and empty state. | Two bespoke components that will drift from the rest of the app. |
| **Views read the filesystem.** `IconRoleTile` builds `FileImage(File(path))` inside `build`. | Per the skill and `asset_inspector`'s precedent this is a Screen wearing a View costume — and it is **why none of this could be iterated in the catalog**. Every visual check so far has needed a full shell build against a real project. |
| **No demo entry at all.** | The panel is not in `app/tool/catalog/demos/`. There is no way to see the empty state, the error state, a monochrome icon, or a notification icon without finding a project that happens to have one. |

The last two compound: the sample project has no adaptive layers, no monochrome
and no notification icon, so **the plugin's marquee features have never been
seen rendered by anyone**, only asserted by widget tests.

## 4. Direction

### The stage

Master–detail, following scenarios:

```
┌────────────┬──────────────────────────────────────────────┐
│ Android    │  ┌────────────────┐   Adaptive foreground    │
│  ▸ Launcher│  │                │   Android 8 (API 26)     │
│  ▸ Adaptive│  │  device frame  │                          │
│  ▸ Themed  │  │  home screen   │   [safe zone] [neighbours]│
│  ▸ Notif.  │  │  + neighbours  │   ○ squircle ○ circle …  │
│ iOS        │  │                │                          │
│  ▸ App  ●  │  └────────────────┘   ⚠ finding, inline      │
│  ▸ Dark    │                                              │
│ macOS …    │  At true size  ▪ ▪ ▫ ▫ ▫  20 29 40 58 76px   │
└────────────┴──────────────────────────────────────────────┘
```

- **Left rail** — platforms with their roles, each with a small true thumbnail
  and its status dot. Always visible; selecting never hides where you are.
- **Stage** — the icon *in situ* for the selected role:
  - Android → phone home screen, wallpaper, a row of neighbour icons, mask
    picker, safe-zone toggle
  - iOS → same chrome, squircle, dark/tinted as siblings
  - macOS → a Dock strip with neighbours (this is where "oversized" becomes
    visible rather than asserted)
  - Web → a browser tab strip at 16px, plus the maskable safe circle
  - Notification → a status bar / shade row, which is the only honest place for
    a white silhouette
- **True-size strip** stays. It is the strongest thing the current build has and
  it survives unchanged.
- **Findings inline on the stage**, not only in a list at the bottom.

### What this does not become

Not a generator, not an editor, not a config surface. Everything above is
display of files that already exist — the scope decided on 2026-07-31 is
unchanged.

## 5. Variants to enumerate before coding

Per the skill's step 3, and stacked rather than behind a picker:

- **State** — no icons at all · scan failed · scanning · populated · Icon
  Composer (no per-size PNGs) · both catalogs present
- **Role coverage** — every one of the 16 roles, including the three the sample
  project lacks (adaptive trio, monochrome, notification)
- **Data shape** — one density vs five · non-square source · tiny source
  (16px) · huge source (1024) · colour-as-background vs image-as-background ·
  `.ico` with one frame vs ten
- **Findings** — none · one warn · one error · several on one role
- **Theme** — light and dark (the checkerboard, the status-bar backing and the
  themed-icon ground all have to survive both)
- **Width** — narrow panel (rail collapses?) and wide

### Prerequisite refactor

Split `IconRoleTile` / the stage widgets so they take **`ImageProvider` (or
bytes) plus plain data**, and let the screen build `FileImage`. Without this
there can be no demo, and without a demo none of the variants above can be seen.

## 6. Open question

There is no `figma_links.json` and no design source in the repo for this panel.
Either a reference exists and should be followed — the way `dev_studio` is the
reference for the scenarios panel — or this is a free design. That decision is
the gate on everything in §4.
