/// Where things live inside a recording. Pure Dart, because the script that
/// writes a recording runs under `dart`, and the studio that reads one runs
/// under Flutter — and the two have to agree on every path without either
/// importing the other's world.
///
/// A **recording** is a fixture the real tool produced from a real project:
/// the launcher-icon scan of `examples/example`, with the files it names
/// copied in beside it. The studio's own catalog demos, its scenario tests and
/// the web demo all open one. See
/// `docs/superpowers/specs/2026-09-10-studio-over-a-fake-project-design.md`.
library;

/// The recording's package path for a package. `.` is `root`, and a nested
/// path flattens to one segment so every file of a recording sits at a known
/// depth — which is what lets the whole recording be declared as two asset
/// directories.
String recordedPackageSlug(String packagePath) =>
    packagePath == '.' ? 'root' : packagePath.replaceAll('/', '-');

/// The launcher-icon scan of one package and flavor.
String recordedIconScanPath(String packagePath, {String? flavor}) =>
    'launcher_icon/${recordedPackageSlug(packagePath)}'
    '${flavor == null ? '' : '.$flavor'}.json';

/// Where the copy of one of that scan's files goes. Flat, for the reason
/// [recordedPackageSlug] gives: a Flutter asset directory is not recursive,
/// and a mirror of `android/app/src/main/res/mipmap-xxxhdpi/…` would need a
/// pubspec line per density.
String recordedIconFilePath(String packagePath, String packageRelativePath) =>
    'launcher_icon/files/${recordedPackageSlug(packagePath)}-'
    '${packageRelativePath.replaceAll('/', '-')}';
