/// The in-app catalog: a browsable page of your previews, shipped inside your
/// own app.
///
/// **Not the Previews tool.** That is `previews.dart` and the `Previews` plugin
/// — a panel, a CLI and an MCP surface driving a guest engine. This is a widget
/// you mount in your own `main.dart`, and the two keep separate names on
/// purpose: Previews is where you work, a catalog is what you ship.
///
/// It hosts the same previews. `UICatalog` renders whatever the scan found,
/// knobs and all, which is why [PreviewState] is re-exported here — an author
/// writing a ui_book page says `context.uiCatalog`, an author writing a preview
/// says `context.previews`, and both reach the same state.
library;

export 'src/ui_catalog/form_factor.dart' show FormFactor;
export 'src/ui_catalog/figma.dart' show Figma;
export 'src/ui_catalog/ui_catalog.dart'
    show UICatalog, PreviewState, UICatalogStateProvider, UIBookExtension;
