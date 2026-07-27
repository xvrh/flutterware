import 'package:flutterware/plugins.dart';

/// flutterware's own repo — a three-member pub workspace, and the monorepo
/// test case for the shell.
///
/// There is exactly one config, here at the repo root: `examples/example` is a
/// workspace *member*, so it is a package below, not a project of its own.
/// `.new(...)` is the dot shorthand; it needs an SDK constraint of 3.10+, and
/// the explicit `DependenciesPackage(...)` form is identical otherwise.
const root = Pkg('.', tags: ['lib']);
const app = Pkg('app', tags: ['gui']);
const example = Pkg('examples/example', tags: ['sample']);

void main() => Flutterware.configure((fw) {
  fw.packages([root, app, example]);
  fw.use(
    Dependencies(packages: DependenciesPackage.each([root, app, example])),
  );
  fw.use(
    UiCatalog(
      packages: [
        // flutterware's own demos sit beside the harness that renders them
        // rather than in `demo/`, because they exist to exercise the catalog.
        UiCatalogPackage(app, entrypoint: 'tool/catalog'),
        UiCatalogPackage(example),
      ],
    ),
  );
});
