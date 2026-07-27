/// Marks a project's catalog shell: the wrapper every entry is rendered
/// inside, whose optional named parameters are the catalog's top-bar switches.
///
/// ```dart
/// enum Flavor { dev, staging, prod }
///
/// @CatalogShell()
/// Widget wrapInApp(Widget child, {Flavor flavor = Flavor.dev}) =>
///     MyApp(flavor: flavor, home: child);
/// ```
///
/// The parameters are the whole API. Nothing in the shell's body has to know
/// the catalog exists: a demo names it the way it always did, with
/// `@Demo(wrapper: wrapInApp)`, and the catalog drives the axes from outside.
///
/// That works because Dart lets a function keep **extra optional named**
/// parameters and still satisfy `WidgetWrapper`, which is
/// `Widget Function(Widget)` and is not ours to change. So:
///
/// - Flutter's own widget previewer calls it through that typedef, with one
///   argument, and gets the shell exactly as written — including whatever the
///   shell injects, which is what demos below it depend on.
/// - The real app calls `wrapInApp(child)` like any other function.
/// - Only the catalog calls it *by name*, which is the one place the named
///   parameters are still visible, passing whatever the top bar has selected.
///
/// An axis must be an `enum` or a `bool` — the guest reports what there is to
/// choose from by handing back the values it was given, and those are the two
/// kinds with a closed set. See
/// `docs/superpowers/specs/2026-07-27-top-bar-axes.md`.
///
/// A project may have several shells. Each entry gets the axes of the shell its
/// `wrapper:` names, so the top bar changes as you move between them, and each
/// shell remembers its own selections.
class CatalogShell {
  const CatalogShell();
}
