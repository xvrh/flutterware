import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/translations.dart';
import 'package:flutterware_app/src/translations/row.dart';

TranslationRow row({
  Map<String, String> values = const {'en': 'Save', 'nl': 'Opslaan'},
  ExportedShot? shot,
}) => TranslationRow(
  catalog: 'app',
  key: 'save',
  template: 'en',
  values: values,
  shot: shot,
);

void main() {
  test('a locale with nothing to say is missing', () {
    var it = row(values: const {'en': 'Save'});

    expect(it.missingIn('nl'), isTrue);
    expect(it.missingAnywhere(['en', 'nl']), isTrue);
  });

  test('an empty string counts as missing, like an absent key', () {
    // Catalogs spell a missing translation both ways about equally often,
    // and a blank cell that reads as translated is the one that never gets
    // fixed.
    expect(row(values: const {'en': 'Save', 'nl': ''}).missingIn('nl'), isTrue);
  });

  test('the source language is never missing against itself', () {
    // Otherwise every key in a single-language project is a finding, and the
    // filter that matters becomes the filter nobody trusts.
    expect(row(values: const {}).missingIn('en'), isFalse);
  });

  test('search matches the key and the text in any language', () {
    var it = row();

    expect(it.matches('sav'), isTrue, reason: 'the key');
    expect(it.matches('Opsla'), isTrue, reason: "another locale's words");
    expect(it.matches('OPSLA'), isTrue, reason: 'case-insensitively');
    expect(it.matches('nothing'), isFalse);
    expect(it.matches(''), isTrue);
  });

  test('a key with no shot has no picture', () {
    expect(row().hasPicture, isFalse);
    expect(
      row(
        shot: const ExportedShot(
          image: 'a.png',
          scenario: 's',
          step: 'x',
          stepIndex: 1,
        ),
      ).hasPicture,
      isTrue,
    );
  });
}
