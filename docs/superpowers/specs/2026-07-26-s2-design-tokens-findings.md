# S2 — Porting the admin_ui token layer: findings

**Date:** 2026-07-26
**Status:** Spike complete. **Succeeded.** The design lift is mechanical.
**Brief:** `2026-07-25-overhaul-master-plan.md` § "Spike briefs → S2".

## Verdict

The kill criterion — "the tokens drag in admin_ui's app state, CMS field model,
or shell assumptions" — was cleared in the first minute. The entire theme
subtree's external imports are:

```
package:flutter/foundation.dart
package:flutter/material.dart
package:flutter/widgets.dart
package:google_fonts/google_fonts.dart
```

**Zero CMS coupling.** 1,322 lines across 7 named themes, self-contained.

## What landed

`app/lib/src/ui/design/` — palette, radii, spacing, elevation, typography,
tokens, plus `themes/` (the `FwTheme` descriptor, `iris` as default, `shadcn` as
a second look to prove multi-theme). Barrel at `design/design.dart`.

The mechanism is a `ThemeExtension<FwTokens>` on `ThemeData` plus context
accessors:

```dart
context.colors.grn        context.radii.radiusSmall
context.type.bodyStrong   context.elevation.md
```

`app/lib/src/ui/theme.dart` now builds `appTheme` from `buildAppTheme(tokens)`,
merging in flutterware's existing chrome (tab indicator, popup menu, data table,
divider) so nothing regressed.

## Changes made to the upstream code

Near-verbatim, with four deliberate edits:

1. **`Cms` prefix → `Fw`.**
2. **`iris` → `accent`** as the primary-colour field name. Upstream names the
   field after its default theme; carrying `iris` into flutterware would be
   permanent confusion. Mechanical rename across the palette and theme files.
3. **Dropped CMS-specific fields** — `commentHighlight`,
   `commentHighlightBorder`, `draftTint`, and the `translated`/`untranslated`
   aliases.
4. **Dropped `google_fonts`.** It was used in exactly two methods
   (`applyFont` / `applyFontTheme`) and only when a theme sets `googleFont`. It
   fetches over the network on first paint, which a local dev tool should not
   do. `fontFamily` (system/bundled) is kept. **This costs nothing for the
   default look** — `iris` specifies no font at all. Only `carbon` (IBM Plex
   Sans), `shadcn` (Inter) and `material` (Roboto) named one; they now fall back
   to the platform font unless the family is bundled as an asset.

## Verified in the running app

`flutter run -d macos -t lib/main_dev.dart`, Dependencies screen:

- Page title through `type.pageTitle`; column headers uppercased through
  `type.micro`; package names `bodyStrong`; versions `bodyMuted`.
- The "Direct" badge is now `colors.statusFill(colors.grn)` +
  `statusBorder(grn)` + `grn` text, replacing hardcoded `Color(0xfff2f8eb)` /
  `Color(0xff618a3d)`. The "Transitive" badge is the neutral equivalent.
- Hardcoded `EdgeInsets` → `FwSpacing`; `BorderRadius.circular(10|20)` →
  `context.radii`.

**Theme swap verified.** Pointing `appTheme` at `shadcnTheme.tokens` and
restarting visibly changed the migrated screen — tighter radii (8 vs 9), lighter
heading weight (w600 vs w700) with −0.2 tracking, and a brighter green
(`#16A34A` vs `#2f9e63`). Reverted to `defaultTokens` afterward.

## The finding that matters for M1

**Swapping tokens re-themed only the migrated screen.** The overview screen and
sidebar did not move at all, because they still read the old flat `AppColors`
constants.

That is exactly the "port widgets lazily" state the master plan calls for, and
it puts a number on the remaining migration: **41 `AppColors` uses across 12
files.** `AppColors` is deliberately left in place and re-exported from
`ui/theme.dart` so un-migrated screens keep compiling. Each screen converts as
it is rewritten into a plugin panel.

## Diff

```
 app/lib/src/dependencies/list.dart |  91 ++++++++++---------
 app/lib/src/ui/theme.dart          | 149 ++++++++++++++++-------
 app/lib/src/ui/design/             | new — 8 files
```

Boring, as required. Analyzer-clean under the repo's `analysis_options.yaml`
(the 8 remaining workspace issues are all pre-existing, in `bin/_coucou.dart`,
`tool/_stream.dart` and `lib/src/test_runner/`).

## Consequences for the master plan

- **Decision 7 holds unchanged** — port the token layer first, port widgets
  lazily. Confirmed by construction.
- The token layer is **ready for M1**; the shell can be built against it now.
- `admin_ui`'s *widget* layer (~44k lines: collection table, filter bar, kanban,
  column chooser, asset library) was **not** assessed. Only the ~1.3k-line theme
  subtree was. Whether those widgets are as cleanly separable is a separate
  question — they live next to the CMS field model and almost certainly are not.
- Open follow-up: whether to bundle Inter / IBM Plex as assets so the non-default
  themes render as designed, or to drop those themes' font specs entirely.
