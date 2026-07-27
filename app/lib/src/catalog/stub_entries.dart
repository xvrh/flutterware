import 'catalog_entry.dart';

/// A hand-written stand-in for discovery.
///
/// Everything downstream of this list is real — wrapper generation, the
/// accumulating entrypoint, the resident compiler, reload-to-switch. Only the
/// scan that would produce it is missing, so the entries carry their annotation
/// as source text exactly as a syntactic parse would hand it over.
///
/// The paths are relative to the repo root, and the demo files deliberately
/// carry no `@Demo` annotation of their own: nothing reads them yet, and
/// duplicating the annotation in two places would invite them to disagree.
const stubEntries = <CatalogEntry>[
  CatalogEntry(
    path: 'app/tool/catalog/demos/avatar_tile.dart',
    symbol: 'avatarTileMembers',
    name: 'Members',
    annotation:
        "Demo(name: 'Members', group: 'Avatar tile', wrapper: wrapInApp)",
  ),
  CatalogEntry(
    path: 'app/tool/catalog/demos/avatar_tile.dart',
    symbol: 'avatarTileEmpty',
    name: 'Empty',
    annotation: "Demo(name: 'Empty', group: 'Avatar tile', wrapper: wrapInApp)",
  ),
  CatalogEntry(
    path: 'app/tool/catalog/demos/avatar_tile.dart',
    symbol: 'avatarTileLongText',
    name: 'Long text',
    annotation:
        "Demo(name: 'Long text', group: 'Avatar tile', wrapper: wrapInApp)",
  ),
  CatalogEntry(
    path: 'app/tool/catalog/demos/counter.dart',
    symbol: 'counter',
    name: 'Counter',
    annotation: "Demo(name: 'Counter', wrapper: wrapInApp)",
  ),
  CatalogEntry(
    path: 'app/tool/catalog/demos/dashboard.dart',
    symbol: 'dashboard',
    name: 'Dashboard',
    annotation:
        "Demo(name: 'Dashboard', formFactor: FormFactor.desktop, "
        'wrapper: wrapInApp)',
  ),
];
