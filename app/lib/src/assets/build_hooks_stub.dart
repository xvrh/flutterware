/// The web half of `build_hooks.dart`: the same names, and nothing behind
/// them.
///
/// A browser cannot run a package's build hook — there is no `dart` to run
/// it with and no filesystem for it to write to — and nothing that runs in
/// one asks. These declarations exist so the asset bundle, which sits in the
/// shell's import closure, compiles; calling into them is a programming error
/// and says so.
library;

/// See `build_hooks_io.dart`.
typedef BuildHooksResult = ({
  List<String> packages,
  String? failure,
  List<KernelAsset> nativeAssets,
});

class BuildHooks {
  BuildHooks({
    required this.dartExecutable,
    required this.packageConfigPath,
    required this.rootPackageRoot,
  });

  final String dartExecutable;
  final String packageConfigPath;
  final String rootPackageRoot;

  static const retryHold = Duration(minutes: 1);

  Future<BuildHooksResult> run() =>
      throw UnsupportedError('Build hooks cannot run in a browser.');
}

/// The shape of `package:hooks_runner`'s `KernelAsset`, as far as the asset
/// bundle reads it.
class KernelAsset {
  const KernelAsset({
    required this.id,
    required this.target,
    required this.path,
  });

  final String id;
  final Object target;
  final KernelAssetPath path;
}

abstract class KernelAssetPath {
  const KernelAssetPath();
}

class KernelAssetAbsolutePath extends KernelAssetPath {
  const KernelAssetAbsolutePath(this.uri);

  final Uri uri;
}

class KernelAssets {
  const KernelAssets(this.assets);

  final List<KernelAsset> assets;

  String toNativeAssetsFile() =>
      throw UnsupportedError('Native assets cannot be installed in a browser.');
}
