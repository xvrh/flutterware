/// Generating the frame harness's entrypoint.
///
/// **Pure Dart, and that is the whole reason this is not in `frame_harness.dart`
/// beside the thing it generates a call to.** `fw` links the tool half of this
/// plugin, and the tool half runs under a bare `dart run` with no `dart:ui` —
/// so a single import reaching into the harness drags Flutter into a program
/// that cannot have it, and every Flutter source in the graph fails to compile
/// at once. The purity guardrail catches it; this file is the fix.
library;

import 'package:path/path.dart' as p;

/// What a project's frame file must export, and the only name this looks for.
///
/// A convention rather than a parse. The alternative is reading the file to
/// find the one class extending [StoreFrame], which is a parser to write, a
/// parser to keep in sync with the language, and a silent wrong answer for a
/// file that declares two. `flutter_test_config.dart` asks for
/// `testExecutable` the same way and for the same reason.
///
/// ```dart
/// // tool/store/coffee_frame.dart
/// final storeFrame = CoffeeFrame.new;
/// ```
const storeFrameSymbol = 'storeFrame';

/// The generated `main` the frame runner compiles: one import, the project's
/// frame, handed to [runStoreFrameHarness].
///
/// [frameFile] is package-relative and usually sits outside `lib/`, so it has
/// no `package:` URI and the import is relative to the entrypoint's own
/// directory — exactly what the scenario harness's generator does for scenario
/// files.
String generateStoreFrameEntrypoint({
  required String frameFile,
  String directory = 'build/flutterware/store_frames',
}) {
  var import = p.url.relative(frameFile, from: directory);
  return '''
// GENERATED — flutterware store frames harness. Do not edit.
import 'package:flutterware/src/store/frame_harness.dart' as harness;
import '$import' as frame;

void main() => harness.runStoreFrameHarness(frame.$storeFrameSymbol);
''';
}
