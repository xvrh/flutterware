import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../address/address_scope.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import 'scenarios_core.dart';

export 'scenarios_core.dart' show ScenariosCore, scenariosPluginId;

/// The GUI half of the scenarios plugin: a panel, and literally nothing else.
///
/// The skeleton tier — the scanned scenario list. The flow graph, the run
/// toolbar and the step detail arrive with the runner.
class ScenariosPlugin extends NativePlugin<ScenariosCore> {
  ScenariosPlugin(super.core);

  @override
  String? get busyWith =>
      core.packages.any(core.isScanning) ? 'scanning scenarios' : null;

  @override
  Widget buildPanel(BuildContext context) => _ScenariosPanel(this);
}

/// Owns the subscription: mounting starts the scan, as the laziness rule
/// requires — a package is scanned because its panel is visible.
class _ScenariosPanel extends StatefulWidget {
  const _ScenariosPanel(this.plugin);

  final ScenariosPlugin plugin;

  @override
  State<_ScenariosPanel> createState() => _ScenariosPanelState();
}

class _ScenariosPanelState extends State<_ScenariosPanel> {
  ScenariosCore get _core => widget.plugin.core;

  /// The package the address names, or the first declared one when it names
  /// none — where selecting the plugin off the rail leaves you.
  String? _resolve() =>
      AddressScope.segment(context, 0) ?? _core.packages.firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var path = _resolve();
    if (path != null) _core.track(path);
  }

  @override
  Widget build(BuildContext context) {
    var path = _resolve();
    if (path == null) {
      return Center(
        child: Text(
          'No packages configured for this plugin.\n'
          'Add them in tool/flutterware.dart.',
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      );
    }

    // The plugin already relays core.changes as ChangeNotifier notifications.
    return ListenableBuilder(
      listenable: widget.plugin,
      builder: (context, _) => _ScenarioList(_core, path, key: ValueKey(path)),
    );
  }
}

class _ScenarioList extends StatelessWidget {
  const _ScenarioList(this.core, this.package, {super.key});

  final ScenariosCore core;
  final String package;

  @override
  Widget build(BuildContext context) {
    var result = core.scanResultFor(package);
    if (result == null) {
      if (core.scanErrorFor(package) case var error?) {
        return Center(
          child: Text(
            'The scan failed:\n$error',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (result.scenarios.isEmpty) {
      return Center(
        child: Text(
          'No scenarios in ${core.directoryFor(package)}.\n'
          "Write one with scenario('…', (s) async { … }).",
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      );
    }
    return ListView(
      children: [
        for (var diagnostic in result.diagnostics)
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(diagnostic, style: context.type.bodyMuted),
            dense: true,
          ),
        for (var ref in result.scenarios)
          ListTile(
            leading: const Icon(Icons.route_outlined),
            title: Text(ref.name),
            subtitle: Text('${ref.file}:${ref.line}'),
          ),
      ],
    );
  }
}
