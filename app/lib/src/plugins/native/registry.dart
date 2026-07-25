import '../registry.dart';
import 'dependencies_plugin.dart';

/// The plugins compiled into this GUI binary.
///
/// v1 is first-party only, so this map *is* the extension point. A project can
/// choose and configure what it uses in `tool/flutterware.dart`, but it cannot
/// add to this list without a new GUI build — which is exactly why an unknown
/// id resolves to a visible [MissingPlugin] rather than nothing.
PluginRegistry buildNativeRegistry() =>
    PluginRegistry({dependenciesPluginId: DependenciesPlugin.new});
