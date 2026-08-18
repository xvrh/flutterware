/// How the translations plugin writes itself into an address, and how it reads
/// itself back out — both directions in one file, with a round-trip test, for
/// the reason `dependencies_address.dart` gives.
///
/// ```
/// <package>                       the table
/// <package>/<catalog>/<key>     one key open
/// ?locale=nl                      which language is beside the source
/// ?filter=missing|no-picture      which rows the table is showing
/// ```
///
/// The locale and the filter are **axes, not segments**: they are the same
/// table seen differently, and a link to a key should survive being read with
/// a different language selected.
library;

/// A place in the translations plugin.
class TranslationPlace {
  const TranslationPlace(
    this.package, {
    this.catalog,
    this.key,
    this.locale,
    this.filter = TranslationFilter.all,
  }) : assert(key == null || catalog != null, 'a key needs its catalog');

  /// The workspace-relative package path whose translations are shown.
  final String package;

  final String? catalog;

  /// The open key within [catalog], or null for the table alone.
  final String? key;

  /// The language shown beside the source text, or null for the catalog's
  /// own template — which is the one locale that is never a comparison.
  final String? locale;

  final TranslationFilter filter;

  String? get id => key == null ? null : '$catalog/$key';

  @override
  bool operator ==(Object other) =>
      other is TranslationPlace &&
      other.package == package &&
      other.catalog == catalog &&
      other.key == key &&
      other.locale == locale &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(package, catalog, key, locale, filter);

  @override
  String toString() =>
      'TranslationPlace($package'
      '${id == null ? '' : '/$id'}'
      '${locale == null ? '' : ' @$locale'}'
      '${filter == TranslationFilter.all ? '' : ' ${filter.id}'})';
}

/// Which rows the table is showing.
///
/// Deliberately short. Five finding lists were proposed and four did not hold
/// up: a suite that already fails on real overflow says everything about
/// overflow, and a list of every key a run did not reach is a coverage number
/// rather than a worklist. What is left is the pair somebody acts on.
enum TranslationFilter {
  all('all'),

  /// A target language has nothing to say. Readable with no export at all,
  /// which is what makes it the filter that works the first time the tab is
  /// opened.
  missing('missing'),

  /// No export has photographed it — either the scenarios miss that screen, or
  /// the key is an orphan. Both are worth knowing; neither is a defect on its
  /// own, which is why this is a filter and not a badge.
  noPicture('no-picture');

  const TranslationFilter(this.id);

  final String id;

  static TranslationFilter byId(String? id) =>
      TranslationFilter.values.firstWhere(
        (filter) => filter.id == id,
        orElse: () => TranslationFilter.all,
      );
}

/// The address segments naming [package] and, if given, the key inside it.
List<String> translationSegments(
  String package, {
  String? catalog,
  String? key,
}) {
  assert(key == null || catalog != null, 'a key needs its catalog');
  return [package, ?catalog, ?key];
}

/// The axes for a table's current view.
///
/// Absent rather than spelled out when they are the default, so the plain
/// address of a package stays plain — an address that names every default is
/// one nobody can read at a glance.
Map<String, String> translationAxes({
  String? locale,
  TranslationFilter filter = TranslationFilter.all,
}) => {
  'locale': ?locale,
  if (filter != TranslationFilter.all) 'filter': filter.id,
};

/// The inverse of [translationSegments] and [translationAxes].
///
/// A tail this does not recognise reads as the nearest place it does, which
/// leaves the panel showing something rather than nothing.
TranslationPlace? translationPlace(
  List<String> segments, {
  String? locale,
  String? filter,
}) {
  if (segments.isEmpty) return null;
  return TranslationPlace(
    segments.first,
    catalog: segments.length > 1 ? segments[1] : null,
    key: segments.length > 2 ? segments.skip(2).join('/') : null,
    locale: locale,
    filter: TranslationFilter.byId(filter),
  );
}
