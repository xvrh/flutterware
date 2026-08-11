import 'package:path/path.dart' as p;

import '../previews/discovery.dart';
import '../previews/headless_catalog.dart';
import '../previews/protocol.dart';
import 'runner.dart';

/// The previews of a checkout, as the runner asks about them.
///
/// One of these serves **both** sides: it is handed a checkout per call, so
/// base and head go through the same scanner, the same daemon config and the
/// same pipeline. Two objects with two configs is how the two sides start
/// disagreeing about which directories to scan and which annotations count,
/// and then the comparison reports entries that only ever existed in the
/// asking.
class PreviewsSide implements ComparisonSide {
  PreviewsSide({
    required this.dartExecutable,
    required this.flutterSdkRoot,
    required this.appToolDirectory,
    required this.packagePath,
    required this.root,
    required this.previewAnnotations,
  });

  final String dartExecutable;
  final String flutterSdkRoot;
  final String appToolDirectory;

  /// The package inside each checkout, relative — `.` for a single-package
  /// project, `examples/example` in a workspace.
  final String packagePath;

  /// The scan root inside the package, and the preview annotations, both taken
  /// from the **head** checkout's config.
  ///
  /// Deliberately not re-read per side. A comparison asks what *this branch*
  /// did, and if the branch moved its previews directory then reading each
  /// side's own config would compare the old directory against the new one and
  /// report every entry as removed and re-added. Asking one question of both
  /// sides is what makes the answer about the code.
  final String root;
  final List<String> previewAnnotations;

  /// An entry id is `<path>#<symbol>` where the path is relative to the
  /// *package*; a checkout can hold several packages, so the package's own
  /// place in the checkout goes back on the front.
  @override
  String fileOf(String entryId) {
    var hash = entryId.indexOf('#');
    var file = hash < 0 ? entryId : entryId.substring(0, hash);
    return p.normalize(p.join(packagePath, file));
  }

  @override
  Future<List<String>> entries(String checkout) async {
    var scan = CatalogScanner(
      projectRoot: _packageRootIn(checkout),
      roots: [root],
      previewAnnotations: previewAnnotations,
    ).scan();
    return [for (var entry in scan.entries) entry.id];
  }

  @override
  Future<Map<String, String>> render({
    required String checkout,
    required List<String> entryIds,
    required Future<void> Function(RenderedEntry frame) onFrame,
  }) async {
    var packageRoot = _packageRootIn(checkout);
    var catalog = HeadlessCatalog(
      dartExecutable: dartExecutable,
      config: DaemonConfig.forPackage(
        appToolDirectory: appToolDirectory,
        packageRoot: packageRoot,
        flutterSdkRoot: flutterSdkRoot,
        roots: [root],
        previewAnnotations: previewAnnotations,
      ),
    );
    // An entry that compiled and then threw while building is a picture of
    // Flutter's red error screen. Two of those compared say nothing, and one
    // of them compared against a working screen says "97% changed" when the
    // finding is "this throws now". So a frame with errors is *not* a frame.
    var threw = <String, String>{};
    CatalogBatch batch;
    try {
      batch = await catalog.captureAll(
        entryIds: entryIds,
        onFrame: (frame) async {
          if (frame.errors.errors.firstOrNull case var error?) {
            threw[frame.entry.id] = error.exception;
            return;
          }
          await onFrame(
            RenderedEntry(
              entryId: frame.entry.id,
              rgba: frame.rgba,
              width: frame.width,
              height: frame.height,
              tree: frame.tree?.root,
            ),
          );
        },
      );
    } on Object catch (error) {
      // **A side that cannot start is a side, not a crash.** The daemon
      // refuses as a whole when the generated entrypoint does not compile —
      // and one way that happens is version skew, because the base is
      // rendered with the *head's* tooling: a generator that emits a call
      // into `package:flutterware` meets whatever version that checkout
      // resolves. Reported per entry, which lands them on the severity ladder
      // as "this side could not render it" rather than ending the comparison.
      return {for (var id in entryIds) id: '$error'.split('\n').first};
    }
    return {...batch.failed, ...threw};
  }

  String _packageRootIn(String checkout) =>
      p.normalize(p.join(checkout, packagePath));
}
