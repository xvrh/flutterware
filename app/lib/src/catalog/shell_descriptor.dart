import 'package:json_annotation/json_annotation.dart';

part 'shell_descriptor.g.dart';

/// One `@CatalogShell` function, and the axes its signature declares.
///
/// Produced by the same syntactic scan that finds entries, so this is what a
/// parameter list *says* — a name, a type name, and the source text of a
/// default — never what any of it resolves to. Whether `Flavor` is really an
/// enum, and what its values are called, is the guest's to answer: it is handed
/// `Flavor.values` by the generated call and reports back from there.
@JsonSerializable()
class ShellDescriptor {
  const ShellDescriptor({
    required this.path,
    required this.symbol,
    this.axes = const [],
  });

  factory ShellDescriptor.fromJson(Map<String, dynamic> json) =>
      _$ShellDescriptorFromJson(json);

  /// Project-relative path of the declaring file.
  final String path;

  /// The annotated function — `wrapInApp`, or `MyShell.wrap` for a static
  /// member, which [Preview] allows a wrapper to be.
  final String symbol;

  final List<ShellAxis> axes;

  /// Identity, derived the way an entry's is.
  String get id => '$path#$symbol';

  Map<String, dynamic> toJson() => _$ShellDescriptorToJson(this);
}

/// One optional named parameter of a shell, offered in the top bar.
@JsonSerializable()
class ShellAxis {
  const ShellAxis({
    required this.name,
    required this.typeName,
    required this.defaultSource,
  });

  factory ShellAxis.fromJson(Map<String, dynamic> json) =>
      _$ShellAxisFromJson(json);

  /// The parameter's name, which is how a value is addressed.
  final String name;

  /// The type as written — `Flavor`, `bool`. Emitted into generated code as
  /// `<typeName>.values`, which is also what makes a type that is not an enum
  /// a compile error in one generated function rather than a silent wrong
  /// control.
  final String typeName;

  /// The default's source text — `Flavor.dev`, `false`. Emitted verbatim, so a
  /// default that is a constant expression rather than a literal costs nothing.
  final String defaultSource;

  /// A `bool` is its own closed set and needs no values from the guest.
  bool get isBoolean => typeName == 'bool';

  Map<String, dynamic> toJson() => _$ShellAxisToJson(this);
}
