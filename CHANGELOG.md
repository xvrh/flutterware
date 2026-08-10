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
  `PreviewShell` and `PreviewAxes` for the top bar's axes, and `context.knobs.*`
  for knobs. It is imported only when you want one of those; declaring a preview
  imports nothing of flutterware's.
- **`TopBarState` is `PreviewAxes`**, and a shell's builder is handed `axes`
  rather than `topBar`. It named the furniture the switches are drawn on, which
  left nothing in the API to connect it to `--axes=`, `describe --axes=true` or
  the `axes:` on an artifact's address.
- **Knobs are called knobs in Dart too.** `context.previews.parameters.*` and
  `context.uiCatalog.parameters.*` are both now **`context.knobs.*`**, the type
  is `Knobs` (exported, so knob-setting can be factored out), and the devbar's
  `DevbarKnobs` typedef — which existed only to give the class the right name —
  is gone. The CLI's `--knobs=`, `KnobDescriptor` and the panel already said
  knob; only the Dart API disagreed, and "parameters" means the *non*-interactive
  tier in Storybook and the arguments of a function in Dart.
- **`ui_catalog.dart` is now only the in-app catalog** — `UICatalog`,
  `FormFactor`, `Figma`, plus `Knobs` — the browsable page you ship inside your
  own app. `CatalogShell` moved to `previews.dart` as `PreviewShell`;
  `UICatalogState` is gone, and `UICatalogStateProvider` is `KnobsProvider`.
- `ui_catalog_guest.dart`, which only generated code imports, is
  `previews_guest.dart`.
- The plugin is `Previews(...)` (was `UiCatalog(...)`) and its id is
  `flutterware.previews`, so the CLI reads `fw run previews …`.
- **A `Run` entry point declares `defines`, not `knobs`.** `LaunchKnob` is
  `DartDefine` (its `define:` field is now `name:`), `KnobSource` is
  `DefineSource`, `Entrypoint(knobs: …)` is `Entrypoint(defines: …)`, and
  `fw run run launch --knobs=` is `--defines=`. Both plugins spelled `--knobs=`
  for opposite costs: a preview knob is read while a widget builds and changing
  one costs a frame, while these are compiled in and changing one costs a full
  rebuild and reinstall. The manifest key and the `launch` result field follow.

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
