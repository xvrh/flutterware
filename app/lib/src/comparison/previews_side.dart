import 'package:path/path.dart' as p;

// ignore: implementation_imports
import 'package:flutterware/src/inspect/error.dart';

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
  @override
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
    // An entry that compiled and then threw *while building* is a picture of
    // Flutter's red error screen. Two of those compared say nothing, and one
    // of them compared against a working screen says "97% changed" when the
    // finding is "this throws now".
    //
    // **But only a build error replaces the picture.** This used to drop any
    // frame that reported anything, which threw away a perfectly comparable
    // screen because something overflowed by 1.5 pixels — a complaint about
    // the frame, not the absence of one. `InspectError.library` is there to
    // tell those apart without reading the message, and says so.
    var threw = <String, String>{};
    var complained = <String, String>{};
    CatalogBatch batch;
    try {
      batch = await catalog.captureAll(
        entryIds: entryIds,
        onFrame: (frame) async {
          var errors = frame.errors.errors;
          if (errors.where(_replacesTheFrame).firstOrNull case var fatal?) {
            threw[frame.entry.id] = fatal.exception;
            return;
          }
          if (errors.firstOrNull case var complaint?) {
            complained[frame.entry.id] = complaint.exception;
          }
          // **Said, not silently compared.** A preview that never stops moving
          // is photographed at whatever point the deadline fell on, so a
          // difference between the two sides may be the clock rather than the
          // branch. Both sides carry the same note, so it cancels and the row
          // stays quiet — until only one side animates, which is itself the
          // finding.
          if (!frame.settled) {
            complained[frame.entry.id] =
                'still animating when it was captured, so this picture is not '
                'reproducible';
          } else if (!frame.seesAnimations) {
            complained[frame.entry.id] =
                'this side cannot tell whether anything was still animating, '
                'so the frame may have been taken mid-transition';
          }
          await onFrame(
            RenderedEntry(
              entryId: frame.entry.id,
              rgba: frame.rgba,
              width: frame.width,
              height: frame.height,
              tree: frame.tree?.root,
              complaint: complained[frame.entry.id],
            ),
          );
        },
      );
    } on Object catch (error) {
      // **A side that cannot start is one finding.** The daemon refuses as a
      // whole when the generated entrypoint does not compile — one way that
      // happens is version skew, because the base is rendered with the *head's*
      // tooling (see the design doc's §11a). Nothing about that is per entry,
      // and reporting it per entry produced twenty-four rows of one sentence.
      // **Whole, not the first line.** A refusal you cannot act on is barely
      // better than the twenty-four rows it replaced, and the compiler puts
      // its diagnostics on the lines after the summary.
      throw SideDidNotCompile('$error');
    }
    return {...batch.failed, ...threw};
  }

  /// Whether this error replaced what would have been on screen.
  ///
  /// A build that throws is caught by the widgets library and the subtree
  /// becomes an `ErrorWidget`: there is no picture left of the thing you asked
  /// for, and comparing one is comparing error screens. A layout overflow is
  /// reported by the rendering library and **paints anyway**, with a stripe
  /// over the part that did not fit — a picture, plus a complaint, and the
  /// complaint is not a reason to refuse to compare it.
  static bool _replacesTheFrame(InspectError error) =>
      error.library == 'widgets library';

  String _packageRootIn(String checkout) =>
      p.normalize(p.join(checkout, packagePath));
}
