import 'dart:convert';
import 'dart:io';

import 'package:flutterware_app/src/comparison/closure.dart';
import 'package:flutterware_app/src/comparison/scenarios_estimate.dart';
import 'package:flutterware_app/src/comparison/scenarios_side.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What the scenarios tab says before you click it.
///
/// Worked out by parsing rather than by compiling, because the live listing
/// costs a harness build and a guest on each side — which is the bulk of what
/// replaying costs, so an estimate that used it would be the work.
void main() {
  late Directory root;
  late ClosureMemo memo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_estimate');
    memo = ClosureMemo(p.join(root.path, 'memo'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A checkout holding [files] under `test/`, with a package config so the
  /// import graph can resolve.
  String checkout(String name, Map<String, String> files) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    File(p.join(dir.path, '.dart_tool', 'package_config.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'configVersion': 2, 'packages': const []}),
      );
    files.forEach((relative, content) {
      File(p.join(dir.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    return dir.path;
  }

  var side = ScenariosSide(
    flutterSdkRoot: '/unused',
    packagePath: '.',
    directory: 'test',
  );

  ScenariosEstimate estimate(String base, String head) => ScenariosEstimate.of(
    headRoot: head,
    baseRoot: base,
    side: side,
    memo: memo,
  );

  /// A file holding one scenario. Wrapped in a `main`, because a bare call at
  /// the top level is not Dart and the scanner parses for real.
  String scenario(String name) =>
      "void main() { scenario('$name', (t) async {}); }";

  test('a scenario nothing touched is not counted', () {
    var files = {'test/shop.dart': scenario('Checkout')};

    var result = estimate(checkout('base', files), checkout('head', files));

    expect(result.label, '0 of 1');
  });

  test('a touched scenario is counted', () {
    var result = estimate(
      checkout('base', {'test/shop.dart': scenario('Checkout')}),
      checkout('head', {
        'test/shop.dart': '${scenario('Checkout')}\n// edited',
      }),
    );

    expect(result.label, '1 of 1');
  });

  // The plan settles a scenario head alone has without replaying it, so the
  // estimate must not promise a replay that will not happen.
  test('a scenario only head has counts in the total, not the run', () {
    var result = estimate(
      checkout('base', {'test/shop.dart': scenario('Checkout')}),
      checkout('head', {
        'test/shop.dart': scenario('Checkout'),
        'test/cart.dart': scenario('Cart'),
      }),
    );

    expect(result.label, '0 of 2');
  });

  test('a scenario only base has is still something looked at', () {
    var result = estimate(
      checkout('base', {'test/gone.dart': scenario('Gone')}),
      checkout('head', {'test/shop.dart': scenario('Checkout')}),
    );

    expect(result.total, 2);
    expect(result.toRun, 0);
  });

  // The same rule the run uses, deliberately: an estimate computed by a second
  // rule drifts from the thing it estimates.
  test('a change anywhere in the closure counts', () {
    var body = "import 'helper.dart';\n${scenario('Checkout')}";

    var result = estimate(
      checkout('base', {
        'test/shop.dart': body,
        'test/helper.dart': 'const gap = 8;',
      }),
      checkout('head', {
        'test/shop.dart': body,
        'test/helper.dart': 'const gap = 12;',
      }),
    );

    expect(result.label, '1 of 1');
  });

  // A parse can be wrong where the harness cannot: this is the disagreement
  // `discovery.dart` already calls a diagnostic rather than a failure, and an
  // estimate is allowed to be an estimate.
  test('a name that is not a literal is invisible, and that is allowed', () {
    var files = {
      'test/shop.dart':
          'const name = "Checkout";\nscenario(name, (t) async {});',
    };

    expect(estimate(checkout('base', files), checkout('head', files)).total, 0);
  });
}
