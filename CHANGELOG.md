## 0.5.2

The UI catalog tool is now **Previews**, and entries are declared with
Flutter's own annotation. Breaking, with no deprecation path.

- **`@Demo` is gone.** Annotate with `@Preview` from
  `package:flutter/widget_previews.dart`; a preview written for Flutter's own
  previewer is an entry here with nothing to change. `formFactor:` went with
  it — pin a canvas from the panel instead.
- **The whole package is scanned**, not `demo/` only, so a preview beside the
  widget it shows is found. Files `git` ignores are skipped, and symlinks are
  not followed. `Previews(directory: …)` narrows the scan, and moves where
  `new` writes.
- **New library `previews.dart`** — what `@Preview` does not carry:
  `PreviewShell` and `TopBarState` for the top bar's axes, and
  `context.previews.parameters.*` for knobs. It is imported only when you want
  one of those; declaring a preview imports nothing of flutterware's.
- **`ui_catalog.dart` is now only the in-app catalog** — `UICatalog`,
  `FormFactor`, `Figma` — the browsable page you ship inside your own app.
  `CatalogShell` moved to `previews.dart` as `PreviewShell`, and
  `UICatalogState` is `PreviewState`.
- `ui_catalog_guest.dart`, which only generated code imports, is
  `previews_guest.dart`.
- The plugin is `Previews(...)` (was `UiCatalog(...)`) and its id is
  `flutterware.previews`, so the CLI reads `fw run previews …`.

## 0.5.1

- Upgrade dependencies

## 0.5.0

- Add Figma integration to `ui_catalog`

## 0.4.2

- Move the devbar button slightly

## 0.4.1

- Increase test_api constraint

## 0.4.0

- Improve `package:flutterware/devbar.dart`

## 0.3.0

- Rename `widget_book` to `ui_book`

## 0.2.1

- Add search field to up-coming `storybook` feature

## 0.2.0

- Support Flutter 3.13

## 0.1.2

- Internal maintenance to improve pub's score.

## 0.1.1

- Allow to start the app from pub cache.

## 0.1.0

- Test runner with screenshots & hot-reload
- Pub dependencies manager
- Launcher icon manager
