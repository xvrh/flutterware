import 'dart:io';

import 'package:flutterware_app/src/session/cli.dart';
import 'package:flutterware_app/src/session/session.dart';

/// The CLI renderer of the plugin contract.
///
/// **Pure Dart, and guarded** — `test/utils/entry_point_purity_test.dart`
/// fails if this file's import closure ever reaches `package:flutter`. That is
/// not style: a plugin's panel returns a `Widget`, so reaching one from here
/// would make this unlinkable, and the compile error would arrive far from the
/// import that caused it.
///
/// Run it with:
///
///     cd app && dart run bin/fw.dart status
///
/// Everything it does lives in [FwCli], so a test can drive the same commands
/// against the same session the MCP server gets — which is the only way the
/// parity rule is checkable rather than asserted.
///
/// `dart compile exe` does **not** work from this package — `flutterware_app`
/// depends on Flutter plugins with native build hooks (`objective_c`, via
/// `path_provider`), and build hooks are a property of the dependency
/// resolution rather than the import closure. `dart compile kernel` does, and
/// runs in ~0.85s against `dart run`'s 5s.
Future<void> main(List<String> arguments) async {
  // Dart ignores whatever `main` returns, so the code has to be *set*. Without
  // this every invocation exits 0 — including the ones that just printed an
  // error, which is the difference between a CLI you can put in a script and
  // one you cannot.
  exitCode = await FwCli(
    openSession: () => Session.open(Directory.current),
    out: stdout,
    err: stderr,
  ).run(arguments);
}
