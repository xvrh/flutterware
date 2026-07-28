/// The wire shape of what an action returns.
///
/// Extracted from the `PluginResult` class an action declares in `returns:` —
/// nobody writes one of these by hand, which is the point. A schema somebody
/// maintains alongside the code is a schema that disagrees with it by the third
/// field; a schema *read from* the code cannot.
///
/// It carries what a sample of real output never could: which fields are
/// optional. "This package has no error" and "this package cannot have one"
/// look identical in a response and are different promises.
class ResultShape {
  const ResultShape(this.type, this.fields);

  /// The class name, which is also what `PluginAction.returnsName` reports.
  final String type;

  final List<ResultField> fields;

  /// The shape as an indented tree.
  ///
  /// A tree rather than a table because results nest, and the thing a reader
  /// is looking for — did this field become optional, did that list gain a
  /// member — is one line either way. Rendered here rather than in each
  /// surface so `fw ... --help` and `docs/capabilities.md` cannot describe the
  /// same shape differently.
  String toText({String indent = '', bool docs = true}) {
    var buffer = StringBuffer();
    for (var field in fields) {
      buffer.writeln(
        '$indent${field.name}: ${field.type}${field.optional ? '?' : ''}'
        '${docs && field.doc != null ? '   # ${field.doc}' : ''}',
      );
      if (field.shape case var nested?) {
        buffer.write(nested.toText(indent: '$indent  ', docs: docs));
      }
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'fields': [for (var field in fields) field.toJson()],
  };

  static ResultShape fromJson(Map<String, Object?> json) =>
      ResultShape(json['type']! as String, [
        for (var field in (json['fields'] as List? ?? const []))
          ResultField.fromJson((field as Map).cast<String, Object?>()),
      ]);
}

class ResultField {
  const ResultField(
    this.name,
    this.type, {
    this.optional = false,
    this.shape,
    this.doc,
  });

  /// The key as it appears in JSON — the `@JsonKey(name:)` when there is one,
  /// so this describes what is actually sent rather than what the Dart field
  /// happens to be called.
  final String name;

  /// As written: `String`, `int`, `List<CatalogEntrySummary>`.
  final String type;

  /// Nullable, and therefore absent from a response that has nothing to say.
  final bool optional;

  /// The nested shape, when this field's type is another result class.
  final ResultShape? shape;

  /// The first line of the field's dartdoc. What the field *means*, which the
  /// type cannot say.
  final String? doc;

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    if (optional) 'optional': true,
    if (doc != null) 'doc': doc,
    if (shape != null) 'shape': shape!.toJson(),
  };

  static ResultField fromJson(Map<String, Object?> json) => ResultField(
    json['name']! as String,
    json['type']! as String,
    optional: json['optional'] == true,
    doc: json['doc'] as String?,
    shape: switch (json['shape']) {
      Map<String, Object?> shape => ResultShape.fromJson(shape),
      Map<Object?, Object?> shape => ResultShape.fromJson(
        shape.cast<String, Object?>(),
      ),
      _ => null,
    },
  );
}
