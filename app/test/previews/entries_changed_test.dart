import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/catalog_session.dart';
import 'package:flutterware_app/src/previews/protocol.dart';

/// How the plugin's scan hears that it has been overtaken.
///
/// The panel's listing and the previews harness read two different lists. The
/// tree draws what the compiler daemon reports, and the daemon watches the
/// files, so a demo written while the panel is open is listed the moment it is
/// saved. The harness generates its program from the plugin's own scan, which
/// is taken when the package is first tracked and never again on its own — so
/// a preview added while the panel was open was listed and could not be
/// photographed (*the harness returned nothing for this entry*), and a
/// **renamed** one left the generated wrapper naming a symbol that no longer
/// existed, which stopped the harness compiling for good.
///
/// This is the one signal that closes that gap, and the whole of what it has
/// to get right is *when it fires*: a rescan throws away every picture the
/// package has, so firing on a report that changed nothing would empty the
/// store each time a demo was edited.
void main() {
  CatalogEntry entry(
    String symbol, {
    String? annotation,
    String? name,
    String path = 'demo/a.dart',
  }) => CatalogEntry(
    path: path,
    symbol: symbol,
    annotation: annotation ?? "Preview(name: '$symbol')",
    name: name ?? symbol,
  );

  var alpha = entry('alpha');
  var beta = entry('beta');
  var gamma = entry('gamma');

  ({CatalogSession session, List<void> heard}) staged({
    List<CatalogEntry> scanned = const [],
  }) {
    var heard = <void>[];
    var session = CatalogSession(
      appPackageRoot: '/app',
      flutterSdkRoot: '/sdk',
      projectRoot: '/project',
      scannedEntries: scanned,
    )..onEntriesChanged = (() => heard.add(null));
    addTearDown(session.dispose);
    return (session: session, heard: heard);
  }

  test('a report that matches the scan says nothing', () {
    var (:session, :heard) = staged(scanned: [alpha, beta]);
    session.reportCatalog([alpha, beta], const []);
    expect(
      heard,
      isEmpty,
      reason: 'the ordinary handshake, where both sides read the same disk',
    );
  });

  test('an entry written since the scan is news', () {
    var (:session, :heard) = staged(scanned: [alpha, beta]);
    session.reportCatalog([alpha, beta, gamma], const []);
    expect(heard, hasLength(1));
  });

  test('so is one renamed since — the case that broke the harness', () {
    var (:session, :heard) = staged(scanned: [alpha, beta]);
    // A rename is a delete and an add: the wrapper generated from the scan goes
    // on naming `beta`, and the demo no longer declares it.
    session.reportCatalog([alpha, entry('betaRenamed')], const []);
    expect(heard, hasLength(1));
  });

  test('and one deleted since', () {
    var (:session, :heard) = staged(scanned: [alpha, beta]);
    session.reportCatalog([alpha], const []);
    expect(heard, hasLength(1));
  });

  test('an edited annotation is news, though every id stands still', () {
    // The wrapper the harness generates is written from the annotation, and the
    // harness regenerates only when the id list moves — so a comparison on ids
    // alone leaves a thumbnail rendering under the wrapper you have just
    // replaced, for ever, while the panel shows the new one.
    var (:session, :heard) = staged(scanned: [alpha, beta]);
    session.reportCatalog([
      alpha,
      entry('beta', annotation: "Preview(name: 'beta', wrapper: darkShell)"),
    ], const []);
    expect(heard, hasLength(1));
  });

  test('so is a retitled one', () {
    var (:session, :heard) = staged(scanned: [alpha]);
    session.reportCatalog([entry('alpha', name: 'Alpha, retitled')], const []);
    expect(heard, hasLength(1));
  });

  test('and a demo that moved file under a pinned id', () {
    // A declared `id:` is the one thing that unties identity from the path, so
    // it is the one case where the file the wrapper resolves can move without
    // the id saying anything.
    var pinned = CatalogEntry(
      path: 'demo/a.dart',
      symbol: 'alpha',
      annotation: "Preview(id: 'pinned')",
      name: 'alpha',
      declaredId: 'pinned',
    );
    var (:session, :heard) = staged(scanned: [pinned]);
    session.reportCatalog([
      CatalogEntry(
        path: 'demo/moved.dart',
        symbol: 'alpha',
        annotation: "Preview(id: 'pinned')",
        name: 'alpha',
        declaredId: 'pinned',
      ),
    ], const []);
    expect(heard, hasLength(1));
  });

  test('an entry that stopped compiling is not a change to the catalog', () {
    var (:session, :heard) = staged(scanned: [alpha, beta]);
    session.reportCatalog(
      [alpha],
      [QuarantinedEntry(entry: beta, error: 'boom at line 3')],
    );
    expect(
      heard,
      isEmpty,
      reason: "a typo mid-edit must not throw away the package's pictures",
    );
  });

  test('said once, not once per report', () {
    var (:session, :heard) = staged(scanned: [alpha]);
    session.reportCatalog([alpha, beta], const []);
    session.reportCatalog([alpha, beta], const []);
    session.reportCatalog([alpha, beta], const []);
    expect(heard, hasLength(1));
  });

  test('a session nobody scanned for hears the first report', () {
    // The standalone entry point and the motion panel, which pass no scan.
    // Nothing is wired to this there, so what it costs is nothing; what it
    // must not do is decide the empty seed already agreed with the daemon.
    var (:session, :heard) = staged();
    session.reportCatalog([alpha], const []);
    expect(heard, hasLength(1));
  });
}
