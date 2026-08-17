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

void main() => Flutterware.configure((fw) {
  // **What to surface first on the changes screen, for this repository.**
  //
  // There are no built-in attention rules and there must not be: flutterware
  // cannot know whether a project has migrations, and putting a file under a
  // heading that says *look here first* is a claim only the person reading it
  // can make. So every entry below is a statement about *this* repo.
  fw.changes(
    ChangesConfig(
      attention: [
        // The file you are reading. A change here changes what every other
        // screen in the app is looking at.
        'tool/flutterware.dart',
        // Instructions to whoever — or whatever — is working in this checkout.
        // An agent quietly rewriting its own brief is the single thing most
        // worth seeing.
        'CLAUDE.md',
        // The published package's public surface. One added `export` in
        // `lib/plugins.dart` reads as a one-line change and *is* the API.
        'lib/*.dart',
        // The two versions CLAUDE.md says must stay in sync, and the SDK pin
        // that decides whether anything builds at all.
        'pubspec.yaml',
        'app/pubspec.yaml',
        '.fvmrc',
        // What CI will actually run, and the lint rules it runs with.
        '.github/workflows/**',
        'analysis_options.yaml',
        // The design docs. Every screen in this app was argued in one of
        // these first, and a spec moving is usually the reason the code did.
        'docs/superpowers/specs/**',
      ],
    ),
  );

  // **Which of the three packages is this repository, and its picture.** `app`
  // — the desktop GUI — because that is the thing a window of flutterware is
  // showing you. `.` is the published library and `examples/example` is a
  // fixture; neither is what you point at to say "that project".
  //
  // The icon is the macOS art rather than a source file because that is where
  // `app/tool/icon/generate.dart` writes the largest version of it.
  fw.identity(
    const ProjectIdentity(
      package: app,
      icon: 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
    ),
  );

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
  // `app` only, and pointed at the catalog demos rather than `lib`: a motion
  // needs a mounted screen to scrub, and in this repo the screens that mount
  // one are the demos that exist to exercise it.
  fw.use(Motion(packages: [.new(app, directory: 'tool/catalog/demos')]));
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
  // `StackRun.script` rather than a command naming an interpreter: flutterware
  // supplies the SDK it is running under, which is the one the project pinned.
  // The `dart` on PATH is a different question with a frequently different
  // answer — in this repo, a two-versions-old one. This used to be
  // `Platform.resolvedExecutable` prepended to all six commands.
  fw.use(
    DevStack.background(
      label: 'Example server',
      workingDirectory: 'examples/example',
      probe: Probe.json(
        StackRun.script('tool/stack.dart', args: ['status', '--json']),
      ),
      start: StackRun.script('tool/stack.dart', args: ['up']),
      stop: StackRun.script('tool/stack.dart', args: ['down']),
      poll: const Duration(seconds: 15),
      commands: [
        StackCommand(
          'logs',
          'Logs',
          StackRun.script('tool/stack.dart', args: ['logs']),
          description:
              'The last 40 lines the server logged. A background process has '
              'no terminal, so it appends to a file instead.',
        ),
        StackCommand(
          'hit',
          'Send a request',
          StackRun.script('tool/stack.dart', args: ['hit']),
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
  // `lib/` and offer them by file name. `fwMarker` is a real parameter of that
  // app's `main` — see `examples/example/lib/main.dart`; the entry below only
  // labels it, because the signature already says everything else.
  fw.use(
    Run(
      packages: [
        // The GUI itself, on the worktree shell. Launching it through Run is
        // what makes it *driveable* — the launch wraps the entry point in the
        // run guest — and driving the GUI with its own drive verbs is this
        // repo's dogfood loop.
        .new(
          app,
          entrypoints: [
            Entrypoint(
              'lib/main_dev.dart',
              name: 'Studio (dev)',
              description:
                  'The flutterware GUI on the worktree shell — the '
                  'edit-reload-drive inner loop for GUI work',
              platforms: [RunPlatform.desktop],
            ),
          ],
        ),
        .new(
          example,
          entrypoints: [
            Entrypoint(
              'lib/main.dart',
              name: 'App',
              description: 'The example app, with the devbar mounted',
              knobs: [
                Knob(
                  'fwMarker',
                  label: 'Marker',
                  description:
                      'Shown on the home page, to prove which launch is on '
                      'the device',
                ),
              ],
            ),
            Entrypoint(
              'lib/devbar_example.dart',
              name: 'Devbar',
              description: 'Every devbar plugin, on a demo screen',
            ),
            Entrypoint(
              'lib/shop_devbar.dart',
              name: 'Brewline (devbar)',
              description:
                  'The shop, with a plugin that pushes a notification into '
                  'it — the sample for driving an app from the cockpit, '
                  '`fw` or an agent',
            ),
            Entrypoint(
              'lib/network_spike.dart',
              name: 'Network spike',
              description:
                  'Self-contained http traffic generator for the '
                  'ext.dart.io http-profile spike',
            ),
            // Outside `lib/`, which is the reason it is declared: the wrapper
            // that installs the run guest names this file by path and the enum
            // beside it by path, so a launch of it is the live check that a
            // dev-only entry point kept out of what ships is still driveable.
            Entrypoint(
              'demo/main_dev.dart',
              name: 'Dev entry point',
              description:
                  'A dev-only entry point in demo/ — the non-package: case '
                  'for the run guest wrapper',
              platforms: [RunPlatform.desktop],
              knobs: [
                Knob('seed', description: 'What to put in the app at startup'),
                Knob('marker', label: 'Marker'),
              ],
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
