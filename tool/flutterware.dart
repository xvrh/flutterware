import 'dart:io';

import 'package:flutterware/plugins.dart';

/// flutterware's own repo — a three-member pub workspace, and the monorepo
/// test case for the shell.
///
/// There is exactly one config, here at the repo root: `examples/example` is a
/// workspace *member*, so it is a package below, not a project of its own.
/// `.new(...)` is the dot shorthand for a package entry, and needs an SDK
/// constraint of 3.10+; the explicit `PreviewsPackage(...)` form is identical
/// otherwise. It only works inside a list literal, where the context type is
/// the entry — `.each(...)` is handed a `List`, so it stays spelled out.
const root = Pkg('.');
const app = Pkg('app');
const example = Pkg('examples/example');

/// The dart this config is running under — see the [DevStack] note below.
final dart = Platform.resolvedExecutable;

void main() => Flutterware.configure((fw) {
  fw.use(
    Dependencies(packages: DependenciesPackage.each([root, app, example])),
  );
  fw.use(Assets(packages: AssetsPackage.each([root, app, example])));
  fw.use(
    Previews(
      packages: [
        // flutterware's own demos sit beside the harness that renders them
        // rather than in `demo/`, because they exist to exercise the catalog.
        .new(app, directory: 'tool/catalog'),
        .new(example),
      ],
    ),
  );
  // `example` only. `root` is a library and `app` is this GUI — neither has a
  // native splash to resolve, which is why `NativeSplash` offers no `each`.
  fw.use(NativeSplash(packages: [.new(example)]));
  // `example` again, and for the same reason: only a package that is an app
  // has launcher icons to look at.
  fw.use(LauncherIcon(packages: [.new(example)]));
  fw.use(ServerInspection());
  // The same stack `examples/example/tool/flutterware.dart` declares, from the
  // root of the monorepo it lives in — which is the whole job of
  // `workingDirectory:`. The commands are written as that package writes them
  // and run where it runs them, so one script serves both configs and neither
  // has to know where the other opened.
  //
  // `Platform.resolvedExecutable` rather than the string `dart`: a config runs
  // under the SDK the project is pinned to, and that is the one that can run
  // the project's scripts. The `dart` on PATH is a different question with a
  // frequently different answer — in this repo, a two-versions-old one.
  fw.use(
    DevStack.background(
      label: 'Example server',
      workingDirectory: 'examples/example',
      probe: Probe.json([dart, 'tool/stack.dart', 'status', '--json']),
      start: [dart, 'tool/stack.dart', 'up'],
      stop: [dart, 'tool/stack.dart', 'down'],
      poll: const Duration(seconds: 15),
      commands: [
        StackCommand('logs', 'Logs', [dart, 'tool/stack.dart', 'logs']),
        StackCommand(
          'hit',
          'Send a request',
          [dart, 'tool/stack.dart', 'hit'],
          argument: 'path',
          description:
              'Requests a path — /users, /slow, /error — so the Server panel '
              'has traffic to show. Defaults to /users.',
        ),
      ],
    ),
  );
  // `example` only: it is the one package here that is an app you would put on
  // a phone. `app` is this GUI and `root` is a library.
  //
  // Named rather than left to the scan, which would find four `main()`s under
  // `lib/` and offer them by file name. `FW_MARKER` is a real define — see
  // `examples/example/lib/main.dart` — and is here because a launch define the
  // app does not read is a control that does nothing.
  fw.use(
    Run(
      packages: [
        .new(
          example,
          entrypoints: [
            Entrypoint(
              'lib/main.dart',
              name: 'App',
              description: 'The example app, with the devbar mounted',
              defines: [
                DartDefine(
                  'FW_MARKER',
                  description:
                      'Shown on the home page, to prove which build '
                      'is on the device',
                ),
              ],
            ),
            Entrypoint(
              'lib/devbar_example.dart',
              name: 'Devbar',
              description: 'Every devbar plugin, on a demo screen',
            ),
            Entrypoint(
              'lib/ui_book.dart',
              name: 'UI book',
              description: 'The component gallery, no backend',
              // Not a restriction the gallery needs — it runs anywhere — but
              // the one entry point here that is worth reading a device list
              // through, and this repo is the monorepo test case.
              platforms: [RunPlatform.desktop, RunPlatform.web],
            ),
          ],
        ),
      ],
    ),
  );
  // `example` only, for now — the sample scenarios live there.
  fw.use(
    Scenarios(
      packages: [
        .new(example, languages: ['en', 'fr']),
      ],
    ),
  );
});
