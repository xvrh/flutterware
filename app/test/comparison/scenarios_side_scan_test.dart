import 'dart:io';

import 'package:flutterware_app/src/comparison/scenarios_side.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The listing a comparison plans from before it starts anything.
///
/// The expensive twin — `ScenariosSide.scenarios` — needs a generated
/// entrypoint, a compile and a `flutter_tester` on each side, which is what
/// makes this one worth having and worth testing separately: everything that
/// decides whether a harness starts at all is here, and none of it needs one.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_side_scan'));
  tearDown(() => root.deleteSync(recursive: true));

  String checkout(String name, Map<String, String> files) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    files.forEach((relative, content) {
      File(p.join(dir.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    return dir.path;
  }

  ScenariosSide sideFor({String directory = 'test'}) => ScenariosSide(
    flutterSdkRoot: '/nowhere',
    packagePath: 'app',
    directory: directory,
  );

  test('reads the ids a checkout declares, without a harness', () {
    var path = checkout('head', {
      'app/test/shop_test.dart': '''
void main() {
  scenario('Checkout', (s) async {});
  scenario('Refund', (s) async {});
}
''',
      'app/test/cart_test.dart':
          "void main() => scenario('Cart', (s) async {});",
    });

    expect(sideFor().scannedScenarios(path), [
      'test/cart_test.dart#Cart',
      'test/shop_test.dart#Checkout',
      'test/shop_test.dart#Refund',
    ]);
  });

  // The whole set or nothing. A name the parser cannot read is a scenario the
  // harness would list and this would not, and a plan short one id calls a
  // scenario nobody removed removed.
  test('a name it cannot read makes the whole listing null', () {
    var path = checkout('head', {
      'app/test/shop_test.dart': '''
void main() {
  scenario('Checkout', (s) async {});
  scenario(computed, (s) async {});
}
''',
    });

    expect(sideFor().scannedScenarios(path), isNull);
  });

  test('the ids are the package-relative ones the harness uses', () {
    var path = checkout('head', {
      'app/spec/shop_test.dart':
          "void main() => scenario('Checkout', (s) async {});",
    });

    expect(sideFor(directory: 'spec').scannedScenarios(path), [
      'spec/shop_test.dart#Checkout',
    ]);
  });

  test('a checkout with no scenario directory scans to nothing', () {
    expect(sideFor().scannedScenarios(checkout('head', {})), isEmpty);
  });

  // The harness wraps a scenario in the nearest folder config at or above it,
  // stopping at the package root — `flutter test`'s own rule. The comparison
  // asks the same question so a change to that file reaches the scenarios it
  // governs.
  group('the folder config', () {
    test('is the nearest one at or above the scenario', () {
      var path = checkout('head', {
        'app/test/flutter_test_config.dart': '',
        'app/test/scenarios/flutter_test_config.dart': '',
        'app/test/scenarios/shop_test.dart': '',
      });

      expect(
        sideFor().configOf(path, 'test/scenarios/shop_test.dart#Checkout'),
        'app/test/scenarios/flutter_test_config.dart',
      );
    });

    test('is found above the scenario when none is beside it', () {
      var path = checkout('head', {
        'app/test/flutter_test_config.dart': '',
        'app/test/scenarios/shop_test.dart': '',
      });

      expect(
        sideFor().configOf(path, 'test/scenarios/shop_test.dart#Checkout'),
        'app/test/flutter_test_config.dart',
      );
    });

    test('is null where no folder has one', () {
      var path = checkout('head', {'app/test/shop_test.dart': ''});

      expect(sideFor().configOf(path, 'test/shop_test.dart#Checkout'), isNull);
    });
  });
}
