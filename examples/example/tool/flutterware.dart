import 'package:flutterware/plugins.dart';

/// Declares which flutterware plugins this project uses.
///
/// Run by the GUI with a plain `dart run tool/flutterware.dart`; it prints the
/// manifest as JSON and exits. Native plugins are already compiled into the
/// GUI, so this file selects, configures and orders them — it does not supply
/// behaviour.
void main() => Flutterware.configure(
  (fw) => fw
    ..use(Dependencies())
    ..use(UiCatalog())
    ..use(TestRunner())
    ..use(LauncherIcon()),
);
