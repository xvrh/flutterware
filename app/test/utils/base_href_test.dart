import 'dart:io';

import 'package:flutterware_app/src/utils/base_href.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('the default is relative, so a page works wherever it is hosted', () {
    expect(defaultBaseHref, './');
    expect(baseHrefProblem(defaultBaseHref), isNull);
  });

  test('an absolute mount begins and ends with a slash', () {
    expect(baseHrefProblem('/comparisons/42/'), isNull);
    expect(baseHrefProblem('/comparisons/42'), isNotNull);
    expect(baseHrefProblem('comparisons/42/'), isNotNull);
  });

  test('a relative mount other than the default is refused', () {
    // `../` and a bare `.` resolve somewhere the exporter cannot predict, and
    // a page that boots against the wrong root renders blank in silence.
    expect(baseHrefProblem('../'), isNotNull);
    expect(baseHrefProblem('.'), isNotNull);
  });

  test('only an absolute mount is something a local server can mount', () {
    expect(absoluteMount('/catalog/'), '/catalog/');
    expect(absoluteMount(defaultBaseHref), isNull);
    expect(absoluteMount(''), isNull);
  });

  group('rewriting the tag', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('fw_base_href'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('replaces whatever the build compiled in', () {
      var index = p.join(temp.path, 'index.html');
      File(index).writeAsStringSync('<head><base href="/">\n<title>a</title>');

      setBaseHrefIn(index, './');

      expect(
        File(index).readAsStringSync(),
        '<head><base href="./">\n<title>a</title>',
      );
    });

    test('says nothing about a page that is not there', () {
      // A cancelled build leaves no index.html, and a rewrite is not the place
      // to discover that.
      expect(
        () => setBaseHrefIn(p.join(temp.path, 'gone.html'), './'),
        returnsNormally,
      );
    });
  });
}
