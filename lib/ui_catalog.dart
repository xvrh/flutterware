/// The in-app catalog: a browsable page of your previews, shipped inside your
/// own app.
///
/// **Not the Previews tool.** That is `previews.dart` and the `Previews` plugin
/// — a panel, a CLI and an MCP surface driving a guest engine. This is a widget
/// you mount in your own `main.dart`, and the two keep separate names on
/// purpose: Previews is where you work, a catalog is what you ship.
///
/// It hosts the same previews. `UICatalog` renders whatever the scan found,
/// knobs and all, which is why [Knobs] is re-exported here — `context.knobs`
/// reads the same on a ui_book page as in a preview, because it is the same
/// thing being read.
library;

export 'src/ui_catalog/form_factor.dart' show FormFactor;
export 'src/ui_catalog/figma.dart' show Figma;
export 'src/ui_catalog/knobs.dart' show Knobs;
export 'src/ui_catalog/ui_catalog.dart'
    show UICatalog, KnobsProvider, KnobsExtension;
