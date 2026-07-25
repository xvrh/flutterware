import 'package:flutterware/plugins.dart';

/// Declares which flutterware plugins this project uses.
///
/// Run by the GUI with a plain `dart run tool/flutterware.dart`; it prints the
/// manifest as JSON and exits. Native plugins are already compiled into the
/// GUI, so this file selects, configures and orders them — it does not supply
/// behaviour.
void main() => Flutterware.configure(
  (fw) => fw
    ..use(_Native('flutterware.ui_catalog', label: 'UI catalog'))
    ..use(_Native('flutterware.tests', label: 'Tests'))
    ..use(_Native('flutterware.dependencies', label: 'Dependencies'))
    ..use(_Native('flutterware.launcher_icon', label: 'Launcher icon')),
);

// Placeholder until the first-party plugin classes land; they will be imported
// from package:flutterware and used directly (`fw.use(UiCatalog())`).
class _Native extends Plugin {
  _Native(super.id, {super.label});
}
