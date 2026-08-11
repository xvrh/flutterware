import 'package:flutter/widgets.dart';

import 'src/scenarios/web_viewer.dart';

/// The entry point of the exported scenario page.
///
/// Data-free on purpose: the bundle this compiles to knows nothing about any
/// particular run, so it is built once, cached, and copied beside whatever
/// `report.json` an export just wrote. That is what makes exporting a file
/// copy instead of a minute of `flutter build web`.
///
/// See `2026-08-11-scenario-web-export-design.md`.
void main() {
  runApp(ScenarioWebViewerApp(base: Uri.base));
}
