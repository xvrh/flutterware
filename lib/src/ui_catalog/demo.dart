import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';

/// The layout size a catalog entry is designed for.
///
/// Also selects which device-choice bucket the entry uses in the catalog
/// toolbar, which is what this enum meant before it carried a size.
///
/// [all] states no size opinion — the project-level default applies — and is
/// how an entry overrides a project path rule back to nothing.
enum FormFactor {
  mobile(Size(390, 844)),
  desktop(Size(1440, 900)),
  all(null);

  const FormFactor(this.size);

  final Size? size;
}

/// Marks a declaration as a catalog entry.
///
/// Applies to top-level functions, static methods, and public constructors or
/// factories with no required arguments, returning `Widget` or `WidgetBuilder`
/// — the same targets as [Preview], which this extends so that one declaration
/// serves both the flutterware catalog and Flutter's own widget previewer.
///
/// ```dart
/// @Demo(name: 'Empty')
/// Widget memberListEmpty() => MemberListView(items: const []);
/// ```
///
/// Hierarchy is derived from the file's path; [Preview.name] is the leaf's
/// display name, and [Preview.group] is derived from the filename when a file
/// holds more than one entry.
///
/// `base`, not `final`, so a project can define its own annotation — e.g.
/// `base class Tablet extends Demo` — and register it in `previewAnnotations`.
base class Demo extends Preview {
  const Demo({
    this.formFactor,
    this.id,
    this.figma,
    super.name,
    super.group,
    super.size,
    super.textScaleFactor,
    super.wrapper,
    super.theme,
    super.brightness,
    super.localizations,
  });

  /// The layout size this entry is designed for.
  ///
  /// Null leaves [Preview.size] for the project-level default to fill. An
  /// explicit [Preview.size] always wins over this.
  final FormFactor? formFactor;

  /// A stable identity, surviving renames and moves.
  ///
  /// Optional: identity is otherwise derived from the declaration's path and
  /// symbol. Required only where that derivation is ambiguous — several
  /// annotations stacked on one declaration derive the same value, which is
  /// reported as an error rather than silently dropping an entry.
  final String? id;

  /// An opaque link to the design this entry implements.
  final String? figma;

  /// Maps [formFactor] down to [Preview.size] so both hosts read one
  /// declaration.
  ///
  /// Note this returns a plain [Preview]: [id], [figma] and [formFactor] are
  /// **not** readable from the result, so a caller wanting both must keep the
  /// annotation itself as well.
  @override
  Preview transform() {
    var builder = super.transform().toBuilder();
    builder.size ??= formFactor?.size;
    return builder.build();
  }
}
