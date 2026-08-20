import 'dart:io';

import 'package:flutterware_app/src/comparison/build_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_comparison_build_dir');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('every claim is its own directory, and it exists', () {
    var first = claimComparisonBuildDirectory(root.path);
    var second = claimComparisonBuildDirectory(root.path);

    expect(first, isNot(second));
    for (var claim in [first, second]) {
      expect(p.url.isWithin(comparisonBuildRoot, claim), isTrue);
      expect(Directory(p.join(root.path, claim)).existsSync(), isTrue);
    }
  });

  test('release deletes the claim and only the claim', () {
    var kept = claimComparisonBuildDirectory(root.path);
    var released = claimComparisonBuildDirectory(root.path);
    File(
      p.join(root.path, released, 'previews.dill'),
    ).writeAsStringSync('kernel');

    releaseComparisonBuildDirectory(root.path, released);

    expect(Directory(p.join(root.path, released)).existsSync(), isFalse);
    expect(Directory(p.join(root.path, kept)).existsSync(), isTrue);
  });

  test('release refuses a directory it never claimed', () {
    // The guard between "delete this run's artifacts" and "delete the warm
    // lane's": a default `build/flutterware` handed over by mistake must be
    // an error, not the panel's dill gone.
    expect(
      () => releaseComparisonBuildDirectory(root.path, 'build/flutterware'),
      throwsArgumentError,
    );
  });

  test('a released claim that is already gone is not a failure', () {
    var claim = claimComparisonBuildDirectory(root.path);
    Directory(p.join(root.path, claim)).deleteSync(recursive: true);

    // A base checkout somebody disposed of first takes the claim with it.
    expect(
      () => releaseComparisonBuildDirectory(root.path, claim),
      returnsNormally,
    );
  });

  test('claiming sweeps what a crashed run left behind, and nothing newer', () {
    var crashed = claimComparisonBuildDirectory(root.path);
    File(p.join(root.path, crashed, 'scenarios.dill')).writeAsStringSync('k');
    // The stamp's mtime is when the claim was made; a run is minutes, so two
    // days is safely past expiry.
    File(
      p.join(root.path, crashed, '.claim'),
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    var live = claimComparisonBuildDirectory(root.path);
    // Not a claim — no stamp — so however old, it is not the sweep's to touch.
    var foreign = Directory(p.join(root.path, comparisonBuildRoot, 'foreign'))
      ..createSync(recursive: true);

    var claim = claimComparisonBuildDirectory(root.path);

    expect(Directory(p.join(root.path, crashed)).existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
    for (var survivor in [live, claim]) {
      expect(Directory(p.join(root.path, survivor)).existsSync(), isTrue);
    }
  });
}
