## 0.5.2

- New entry model: declare demos with `@Demo(...)` (extends Flutter's
  `Preview`), and declare axes with `CatalogShell` / `TopBarState`.
- `ui_catalog.dart` exports only what a project writes: `Demo`, `FormFactor`,
  `Figma`, `UICatalog*`, `CatalogShell`, `TopBarState`. The guest-side
  machinery the flutterware GUI drives lives in `ui_catalog_guest.dart`,
  which only generated code imports.

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
