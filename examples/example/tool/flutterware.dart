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
  fw.use(Dependencies(packages: [.new(app)]));
  fw.use(Assets(packages: [.new(app)]));
  fw.use(NativeSplash(packages: [.new(app)]));
  fw.use(LauncherIcon(packages: [.new(app)]));
  // No `directory:` — the ordinary case, where the whole package is scanned
  // and previews are found wherever they were written.
  fw.use(Previews(packages: [.new(app)]));
  // Zero config: servers announce themselves at runtime — see
  // bin/example_server.dart.
  fw.use(ServerInspection());
  // No `directory:` — scenarios live in `test/scenarios/`.
  fw.use(
    Scenarios(
      packages: [
        .new(app, languages: ['en', 'fr']),
      ],
    ),
  );
});
