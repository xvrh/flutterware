/// One key, as the panel's table shows it.
///
/// The join the panel needs and neither half has alone: the text comes from
/// the catalog files, the picture from the last export. Kept as its own type
/// rather than reusing [ExportedKey] because the table has to draw a row for a
/// key that has never been photographed — which is most of them, the first
/// time anyone opens the tab.
library;

import 'package:flutterware/translations.dart';

class TranslationRow {
  const TranslationRow({
    required this.catalog,
    required this.key,
    required this.template,
    this.values = const {},
    this.shot,
    this.occurrences = const [],
  });

  final String catalog;
  final String key;

  /// The locale this key's source text is written in.
  final String template;

  /// What each locale's file says. A locale absent from the map has nothing —
  /// empty and missing are the same thing here, because catalogs spell a
  /// missing translation both ways about equally often.
  final Map<String, String> values;

  /// The shot worth showing, or null when no export has seen this key.
  final ExportedShot? shot;

  final List<ExportedShot> occurrences;

  String get id => '$catalog/$key';

  String? valueIn(String locale) => values[locale];

  bool get hasPicture => shot != null;

  /// Whether [locale] has nothing to say for this key — the only finding that
  /// survived, and it reads with no export at all.
  bool missingIn(String locale) =>
      locale != template && (values[locale] ?? '').isEmpty;

  /// Whether any non-template locale is missing it.
  bool missingAnywhere(Iterable<String> locales) => locales.any(missingIn);

  bool matches(String query) {
    if (query.isEmpty) return true;
    var needle = query.toLowerCase();
    if (id.toLowerCase().contains(needle)) return true;
    for (var value in values.values) {
      if (value.toLowerCase().contains(needle)) return true;
    }
    return false;
  }
}
