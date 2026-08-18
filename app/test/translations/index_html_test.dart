import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/translations.dart';
import 'package:flutterware_app/src/translations/index_html.dart';

void main() {
  test('the page carries its own data, so file:// works', () {
    var page = renderTranslationIndex(
      const TranslationExport(
        keys: [
          ExportedKey(
            catalog: 'app',
            key: 'save',
            values: {'en': 'Save'},
            representative: ExportedShot(
              image: 'shots/en/home/1.png',
              scenario: 'home_test.dart/Home',
              step: 'Home',
              stepIndex: 1,
              rect: ExportedRect(x: 10, y: 20, width: 100, height: 40),
            ),
          ),
        ],
      ),
    );

    // Inlined rather than fetched: the person who most needs to read this was
    // sent a zip, and a fetch of keys.json from file:// is blocked.
    expect(page, contains('"key":"save"'));
    expect(page, contains('shots/en/home/1.png'));
    expect(page, isNot(contains('fetch(')));
  });

  test('a translated string cannot close the block it sits in', () {
    var page = renderTranslationIndex(
      const TranslationExport(
        keys: [
          ExportedKey(
            catalog: 'app',
            key: 'evil',
            values: {'en': '</script><script>alert(1)</script>'},
          ),
        ],
      ),
    );

    // Translations are somebody else's text. The escape is what stops the
    // JSON block from being closed by its own contents.
    expect(page, isNot(contains('</script><script>alert(1)')));
    expect(page, contains(r'</script'));
  });

  test('the highlight is drawn from the rectangle, not baked into the png', () {
    var page = renderTranslationIndex(const TranslationExport());

    // The one line of evidence for the decision: the box is positioned at
    // view time from naturalWidth, which is only possible because the frame
    // was left alone.
    expect(page, contains('naturalWidth'));
  });
}
