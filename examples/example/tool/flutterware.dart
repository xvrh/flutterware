import 'package:flutterware/plugins.dart';

/// The sample project, configured as a project in its own right.
///
/// It is also a member of flutterware's own pub workspace, which is why the
/// repo root has a config too. Opening this directory gives you what a user
/// with a single Flutter app sees; opening the repo root gives you the monorepo
/// case. Neither is a special mode — a config is whatever `tool/flutterware.dart`
/// is found beside the directory you opened.
const app = Pkg('.');

void main() => Flutterware.configure((fw) {
  fw.packages([app]);
  fw.use(Dependencies(packages: [DependenciesPackage(app)]));
  fw.use(Assets(packages: [AssetsPackage(app)]));
  // No `entrypoint:` — this is the ordinary case, where demos live in `demo/`.
  fw.use(UiCatalog(packages: [UiCatalogPackage(app)]));
});
