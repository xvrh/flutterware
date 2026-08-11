import 'package:flutter/widgets.dart';

import 'src/comparison/web_viewer.dart';

/// The entry point of the exported comparison page.
///
/// Data-free on purpose, exactly like `main_scenarios_web.dart`: the bundle
/// this compiles to knows nothing about any particular comparison, so it is
/// built once, cached, and copied beside whatever `index.json` an export just
/// wrote. That is what makes exporting a file copy instead of a minute of
/// `flutter build web`.
void main() {
  runApp(ComparisonWebViewerApp(base: Uri.base));
}
