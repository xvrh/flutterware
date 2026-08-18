import 'package:flutterware/src/translations/index.dart';
import 'package:test/test.dart';

/// A catalog compiled as constants — the case that breaks a scheme relying on
/// the stored string's own identity, and the reason [TranslationIndex] mints
/// its own token.
const constCatalog = <String, String>{
  'common_cancel': 'Cancel',
  'dialog_cancel': 'Cancel',
  'common_save': 'Save',
};

void main() {
  setUp(() {
    TranslationIndex.reset();
    TranslationIndex.recording = true;
  });

  tearDown(() {
    TranslationIndex.reset();
    TranslationIndex.recording = false;
  });

  String read(String key, {String catalog = 'app'}) =>
      indexTranslations(catalog)(key, constCatalog[key]!);

  test('a read renders exactly what the catalog said', () {
    expect(read('common_cancel'), 'Cancel');
  });

  test('two keys with the same words stay apart', () {
    var first = read('common_cancel');
    var second = read('dialog_cancel');

    expect(first, second, reason: 'they render the same');
    expect(identical(first, second), isFalse, reason: 'but are not one object');
    expect(TranslationIndex.keyOf(first)?.key, 'common_cancel');
    expect(TranslationIndex.keyOf(second)?.key, 'dialog_cancel');
  });

  test('a literal written in the UI is not attributed to a key', () {
    read('common_cancel');

    // The const catalog's value and this literal *are* the same object. If
    // the index registered the stored string rather than a copy of it, this
    // would come back `common_cancel` and a hardcoded string would be reported
    // as translated.
    expect(identical(constCatalog['common_cancel'], 'Cancel'), isTrue);
    expect(TranslationIndex.keyOf('Cancel'), isNull);
  });

  test('the same key reads back the same object every time', () {
    expect(identical(read('common_save'), read('common_save')), isTrue);
  });

  test('two catalogs can use the same key name', () {
    var app = indexTranslations('app')('title', 'Home');
    var package = indexTranslations('package')('title', 'Home');

    expect(TranslationIndex.keyOf(app)?.catalog, 'app');
    expect(TranslationIndex.keyOf(package)?.catalog, 'package');
  });

  test('the wrapper for a catalog is the same closure every time', () {
    expect(
      identical(indexTranslations('app'), indexTranslations('app')),
      isTrue,
      reason: 'an InheritedWidget compares wrappers in updateShouldNotify',
    );
  });

  test('a matrix running two locales in one process keeps both', () {
    var english = indexTranslations('app')('greeting', 'Hello');
    var dutch = indexTranslations('app')('greeting', 'Hallo');

    expect(TranslationIndex.keyOf(english)?.key, 'greeting');
    expect(TranslationIndex.keyOf(dutch)?.key, 'greeting');
  });

  test('anything built after the lookup fails closed, never wrong', () {
    var value = read('common_cancel');

    expect(TranslationIndex.keyOf(value.toUpperCase()), isNull);
    expect(TranslationIndex.keyOf('$value!'), isNull);
    expect(TranslationIndex.keyOf('Cancel'), isNull);
  });

  test('an empty value is recorded but carries no identity', () {
    var empty = indexTranslations('app')('missing', '');

    expect(empty, isEmpty);
    expect(TranslationIndex.keyOf(empty), isNull);
    expect(TranslationIndex.read['app'], containsPair('missing', ''));
  });

  test('every key asked for is recorded, per catalog', () {
    read('common_cancel');
    read('common_save', catalog: 'other');

    expect(TranslationIndex.read['app']?.keys, ['common_cancel']);
    expect(TranslationIndex.read['other']?.keys, ['common_save']);
  });

  group('an expansion routes the key the substitution already had', () {
    test('the built string resolves to the key that built it', () {
      var template = indexTranslations('app')('greeting', 'Hello, {name}');
      var built = indexExpansions('app')(
        'greeting',
        template.replaceAll('{name}', 'Ada'),
      );

      expect(built, 'Hello, Ada');
      expect(TranslationIndex.keyOf(built), TranslationKey('app', 'greeting'));
    });

    test('the template still resolves too', () {
      var template = indexTranslations('app')('greeting', 'Hello, {name}');
      indexExpansions('app')('greeting', template.replaceAll('{name}', 'Ada'));

      expect(
        TranslationIndex.keyOf(template),
        TranslationKey('app', 'greeting'),
      );
    });

    test('one key expanding many ways keeps every one', () {
      var expand = indexExpansions('app');
      var ada = expand('greeting', 'Hello, Ada');
      var bo = expand('greeting', 'Hello, Bo');

      expect(TranslationIndex.keyOf(ada), TranslationKey('app', 'greeting'));
      expect(TranslationIndex.keyOf(bo), TranslationKey('app', 'greeting'));
      expect(identical(ada, bo), isFalse);
    });

    test('an expansion is not what the catalog answered', () {
      // `read` is compared against the locale's file to report a value that
      // disagrees with it. An expansion never equals the file's value, so
      // recording it there would make every substituted key look wrong.
      indexTranslations('app')('greeting', 'Hello, {name}');
      indexExpansions('app')('greeting', 'Hello, Ada');

      expect(TranslationIndex.read['app'], {'greeting': 'Hello, {name}'});
    });

    test('the wrapper for a catalog is the same closure every time', () {
      expect(identical(indexExpansions('app'), indexExpansions('app')), isTrue);
      expect(
        identical(indexExpansions('app'), indexTranslations('app')),
        isFalse,
      );
    });

    test('not recording is the identity function', () {
      TranslationIndex.recording = false;

      expect(indexExpansions('app')('greeting', 'Hello, Ada'), 'Hello, Ada');
      expect(TranslationIndex.read, isEmpty);
    });
  });

  test('not recording is the identity function', () {
    TranslationIndex.recording = false;
    var value = read('common_cancel');

    expect(identical(value, constCatalog['common_cancel']), isTrue);
    expect(TranslationIndex.keyOf(value), isNull);
  });
}
