import 'package:flutterware/plugins.dart';

/// flutterware's own repo — a three-member pub workspace, and the monorepo
/// test case for the shell.
///
/// There is exactly one config, here at the repo root: `examples/example` is a
/// workspace *member*, so it is a package below, not a project of its own.
/// `.new(...)` is the dot shorthand for a package entry, and needs an SDK
/// constraint of 3.10+; the explicit `UiCatalogPackage(...)` form is identical
/// otherwise. It only works inside a list literal, where the context type is
/// the entry — `.each(...)` is handed a `List`, so it stays spelled out.
const root = Pkg('.');
const app = Pkg('app');
const example = Pkg('examples/example');

void main() => Flutterware.configure((fw) {
  fw.use(
    Dependencies(packages: DependenciesPackage.each([root, app, example])),
  );
  fw.use(Assets(packages: AssetsPackage.each([root, app, example])));
  fw.use(
    UiCatalog(
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
  fw.use(ServerInspection());
  // `example` only: it is the one package here that is an app you would put on
  // a phone. `app` is this GUI and `root` is a library.
  //
  // Named rather than left to the scan, which would find four `main()`s under
  // `lib/` and offer them by file name. `FW_MARKER` is a real define — see
  // `examples/example/lib/main.dart` — and is here because a launch knob the
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
              knobs: [
                LaunchKnob(
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
