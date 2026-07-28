import '../native_plugin.dart';
import '../registry.dart';
import 'dependencies_plugin.dart';
import 'ui_catalog_plugin.dart';

/// The panels compiled into this GUI binary.
///
/// v1 is first-party only, so this map *is* the extension point. A project can
/// choose and configure what it uses in `tool/flutterware.dart`, but it cannot
/// add to this list without a new GUI build — which is exactly why an unknown
/// id resolves to a visible [MissingPlugin] rather than nothing.
///
/// The ids here must also appear in `defaultCoreRegistry()`: a panel is drawn
/// over a core, so registering one without the other gets the plugin a
/// [MissingPlugin] and says why.
PluginRegistry buildNativeRegistry() => PluginRegistry({
  dependenciesPluginId: panelFor<DependenciesCore>(DependenciesPlugin.new),
  uiCatalogPluginId: panelFor<UiCatalogCore>(UiCatalogPlugin.new),
});
