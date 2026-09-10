/// The build hooks, on the platform this is compiled for.
///
/// `package:hooks_runner` and `package:code_assets` import `dart:ffi`, which
/// a web compile refuses outright — and they were the **only** thing in the
/// studio's whole import closure that did (measured 2026-09-10: a
/// `flutter build web` of the shell failed on these two packages and nothing
/// else). So the real implementation lives behind this one door, and a
/// browser gets a stand-in that declares the same names and throws if asked
/// to build anything. The web demo never asks: it opens a recording, and a
/// recording has no hooks to run.
///
/// `dart.library.js_interop` rather than `dart.library.io`, following
/// `utils/url_fragment.dart`: dart2js ships a `dart:io` that compiles and
/// throws, so testing for io would pick the wrong half.
library;

export 'build_hooks_io.dart'
    if (dart.library.js_interop) 'build_hooks_stub.dart';
