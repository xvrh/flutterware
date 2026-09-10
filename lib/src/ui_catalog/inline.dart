import '../inspect/guest_errors.dart';
import '../inspect/guest_images.dart';
import '../inspect/guest_inspect.dart';
import '../inspect/guest_logs.dart';
import '../inspect/guest_watch.dart';
import 'axes.dart';
import 'catalog_keyboard.dart';
import 'entries.dart';
import 'guest.dart';

/// Sets up the guest's extensions for a catalog drawn **inside the host** —
/// what the generated entrypoint's `main` does before `runApp`, minus the
/// parts that replace platform plumbing an embedder guest lacks and a real
/// app has.
///
/// Left out on purpose: the key and text-input shims (the host's own
/// keyboard works), the error hook and the log-capturing zone (both would
/// take over the host's), and the clock pin (the host decides its clock).
/// Everything a panel *asks* is here: entries, knobs, axes, the keyboard,
/// the tree and semantics, errors, images, logs, the watch.
///
/// Once per process is enough and more is harmless — see
/// `GuestExtensions.register`.
void installInlineGuest({required Iterable<String> Function() ids}) {
  CatalogKeyboard.instance.install();
  CatalogKeyboard.instance.registerExtensions();
  CatalogEntries.instance.install(ids);
  CatalogEntries.instance.registerExtensions();
  CatalogKnobs.instance.registerExtensions();
  CatalogAxes.instance.registerExtensions();
  var inspector = GuestInspector(
    rootOf: () => CatalogGuest.demoRoot,
    entryIdOf: () => CatalogKnobs.instance.entryId,
  )..registerExtensions();
  GuestWatch(
    inspector: inspector,
    rootOf: () => CatalogGuest.demoRoot,
    entryIdOf: () => CatalogKnobs.instance.entryId,
  ).registerExtensions();
  GuestErrors.instance.registerExtensions();
  GuestImages.instance.registerExtensions();
  GuestLogs.instance.registerExtensions();
}
