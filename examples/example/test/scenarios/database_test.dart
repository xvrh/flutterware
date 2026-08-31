import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// The scenario that must load a native library, and the guard that keeps it
/// loading.
///
/// `sqlite3` resolves its C functions through `@Native` and the native-assets
/// manifest — there is no runtime override any more — so a harness that spawns
/// `flutter_tester` itself has to build the library and write the mapping, the
/// way `flutter test` does. Nothing else here exercises that: previews mount
/// widgets and touch no database, which is how a suite whose scenarios all
/// open one can be red while its previews half is perfect.
///
/// The platform matters more than it should. A missing mapping does not fail
/// on macOS: the VM falls back to looking the symbols up in the running
/// process, and macOS `flutter_tester` happens to satisfy them — with the
/// *system's* SQLite, not the one the build hook compiled. Linux and Windows
/// testers export nothing, and fail on the first call. So this scenario is
/// green-by-accident on a Mac and honest everywhere else, which is exactly why
/// it shows the version it loaded: a bundled library is years newer than the
/// system's.
///
/// Deliberately the synchronous `package:sqlite3` API. `sqlite_async` runs the
/// database on its own isolate, and a scenario body may not await a future
/// another zone completes.
void main() {
  scenario('Drinks ledger', (s) async {
    var db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute('CREATE TABLE drinks(name TEXT NOT NULL, price REAL NOT NULL)');
    var insert = db.prepare('INSERT INTO drinks(name, price) VALUES(?, ?)');
    for (var (name, price) in [('Flat white', 4.2), ('Cortado', 3.8)]) {
      insert.execute([name, price]);
    }
    insert.close();

    var rows = db.select('SELECT name, price FROM drinks ORDER BY name');
    await s.pumpWidget(
      _Ledger(
        engine: 'SQLite ${sqlite3.version.libVersion}',
        rows: [for (var row in rows) '${row['name']} — ${row['price']}'],
      ),
    );
    await s.screen('Poured from the bundled library');
    expect(find.text('Cortado — 3.8'), findsOneWidget);
  });
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.engine, required this.rows});

  final String engine;
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text(engine)),
        body: ListView(
          children: [for (var row in rows) ListTile(title: Text(row))],
        ),
      ),
    );
  }
}
