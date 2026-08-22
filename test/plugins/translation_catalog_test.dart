import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

/// The catalog declaration crosses a process boundary: `tool/flutterware.dart`
/// writes it, the studio reads it back out of the plugin config. So what is
/// worth pinning is not that the variants exist but that each survives the
/// trip as itself — and what happens to one that cannot.
void main() {
  test('each variant survives the trip as itself', () {
    const perLocale = TranslationCatalog(
      name: 'app',
      files: 'assets/i18n/*.json',
    );
    const perKey = TranslationCatalog.localesPerKey(
      name: 'server',
      file: 'tool/strings.json',
      template: 'fr',
    );

    expect(
      TranslationCatalog.fromJson(perLocale.toJson()),
      isA<FilePerLocaleCatalog>()
          .having((c) => c.files, 'files', 'assets/i18n/*.json')
          .having((c) => c.name, 'name', 'app')
          .having((c) => c.template, 'template', 'en'),
    );
    expect(
      TranslationCatalog.fromJson(perKey.toJson()),
      isA<LocalesPerKeyCatalog>()
          .having((c) => c.file, 'file', 'tool/strings.json')
          .having((c) => c.template, 'template', 'fr'),
    );
  });

  test('the two do not carry the same field', () {
    // The reason this is a hierarchy rather than one class with a mode: there
    // is one file per locale and so a glob finds them, and every locale under
    // a key is one file, which `files` would be a plural for that is never
    // plural. A format added later widens the gap rather than closing it.
    expect(
      const TranslationCatalog(name: 'app', files: 'l10n/*.json').toJson().keys,
      contains('files'),
    );
    expect(
      const TranslationCatalog.localesPerKey(
        name: 'server',
        file: 'strings.json',
      ).toJson().keys,
      contains('file'),
    );
  });

  test('a config from before the choice reads as the shape of its time', () {
    var json = {'name': 'app', 'files': 'assets/i18n/*.json', 'template': 'en'};

    // Not a default chosen for taste: every declaration written before there
    // was a choice described a file per locale, because that was the only
    // thing the loader could read.
    expect(TranslationCatalog.fromJson(json), isA<FilePerLocaleCatalog>());
  });

  test('a layout this build does not know reads as null', () {
    var json = {'name': 'app', 'file': 'strings.csv', 'layout': 'csv'};

    // Refused rather than guessed at. Falling back to the shape we do know
    // would read a file of one format as another and call the catalog empty —
    // a declaration that is right, reported as a mistake. Null is what lets
    // the panel say the build is too old instead.
    expect(TranslationCatalog.fromJson(json), isNull);
  });
}
