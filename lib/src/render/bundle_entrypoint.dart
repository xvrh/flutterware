// Pure Dart on purpose: the fw CLI imports this to generate the bundle's
// entrypoint, and the CLI must never reach package:flutter.
import 'package:path/path.dart' as p;

/// The name of the function marked `@RenderRegistry()` in [source], or null
/// when the file declares no registrar.
///
/// A textual scan, not an analyzer pass: the registrar is one annotated
/// top-level `void` function, and the bundle command refuses loudly when the
/// pattern is absent rather than guessing.
String? findRenderRegistrarName(String source) {
  var match = RegExp(r'@RenderRegistry\(\)[\s\S]{0,200}?void\s+(\w+)\s*\(')
      .firstMatch(source);
  return match?.group(1);
}

/// The generated main compiled into a render bundle: imports the app's
/// registrar and hands it to the driver.
///
/// [registrarFile] and [directory] are both package-root-relative;
/// [directory] is where the generated file will sit, so the import can be
/// spelled relative to it.
String generateRenderBundleEntrypoint({
  required String registrarFile,
  required String registrarName,
  required String directory,
}) {
  var import = p.url.relative(
    p.url.joinAll(p.split(registrarFile)),
    from: p.url.joinAll(p.split(directory)),
  );
  return '''
// GENERATED — flutterware render bundle harness. Do not edit.
import 'package:flutterware/render.dart' as render;
import '$import' as renders;

void main() => render.runRenderDriver(renders.$registrarName);
''';
}
