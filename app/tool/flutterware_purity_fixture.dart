/// Fixture for `test/utils/entry_point_purity_test.dart`.
///
/// Imports `package:flutterware` and nothing else, so the purity test can prove
/// that forbidding `package:flutter` does not also forbid `package:flutterware`
/// — a prefix collision that would make the whole guard vacuous by failing
/// every entry point for the wrong reason.
library;

import 'package:flutterware/plugins.dart';

/// Referenced by nothing — it exists so the import above is not "unused" and
/// cannot be tidied away, which would make the test it backs vacuous.
Address get fixtureAddress => Address(plugin: 'fixture');
