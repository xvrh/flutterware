/// What a project writes: demo declarations, a shell, and the standalone
/// catalog app.
///
/// Deliberately small — this is the published surface, and every name here is
/// a semver commitment. The machinery the flutterware GUI drives inside the
/// guest lives in `ui_catalog_guest.dart`, imported only by generated code.
library;

export 'src/ui_catalog/demo.dart' show Demo, FormFactor;
export 'src/ui_catalog/figma.dart' show Figma;
export 'src/ui_catalog/ui_catalog.dart'
    show UICatalog, UICatalogState, UICatalogStateProvider, UIBookExtension;
// What a project's own shell is written with: `CatalogShell` declares axes by
// asking `TopBarState` for them while it builds.
export 'src/ui_catalog/axes.dart' show CatalogShell, TopBarState;
