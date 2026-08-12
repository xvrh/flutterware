import 'dart:io';

import 'package:flutterware_app/src/comparison/sdk_match.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Whether two checkouts would render with the same engine — the check a
/// comparison refuses to run without.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_sdk_match'));
  tearDown(() => root.deleteSync(recursive: true));

  /// A directory that looks enough like a Flutter SDK to be found, carrying
  /// the version metadata a real one writes into its cache.
  String sdk(String name, {String? version, String? engine}) {
    var dir = Directory(p.join(root.path, 'sdks', name))
      ..createSync(recursive: true);
    var bin = Directory(p.join(dir.path, 'bin'))..createSync(recursive: true);
    File(p.join(bin.path, 'flutter')).writeAsStringSync('');
    File(p.join(bin.path, 'dart')).writeAsStringSync('');
    if (version != null) {
      var cache = Directory(p.join(bin.path, 'cache'))..createSync();
      File(p.join(cache.path, 'flutter.version.json')).writeAsStringSync('''
{
  "frameworkVersion": "$version",
  "frameworkRevision": "rev-$version",
  "engineContentHash": "${engine ?? 'engine-$version'}"
}
''');
    }
    return dir.path;
  }

  /// A checkout with an SDK link the way fvm writes one, and optionally the
  /// committed pins — `flutter_version` (the fw wrapper's) and `.fvmrc`.
  String checkout(
    String name, {
    String? pinning,
    String? claims,
    String? fvmrc,
  }) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    if (pinning != null) {
      var fvm = Directory(p.join(dir.path, '.fvm'))..createSync();
      Link(p.join(fvm.path, 'flutter_sdk')).createSync(pinning);
    }
    if (claims != null) {
      File(p.join(dir.path, 'flutter_version')).writeAsStringSync('$claims\n');
    }
    if (fvmrc != null) {
      File(
        p.join(dir.path, '.fvmrc'),
      ).writeAsStringSync('{"flutter": "$fvmrc"}');
    }
    return dir.path;
  }

  test('two checkouts pinning one SDK match without reading a file', () async {
    var pinned = sdk('beta', version: '3.47.0');
    var match = await SdkMatch.of(
      baseRoot: checkout('base', pinning: pinned),
      headRoot: checkout('head', pinning: pinned),
    );

    expect(match.same, isTrue);
    expect(match.reason, isNull);
  });

  test('two SDKs of the same version in two places match', () async {
    var match = await SdkMatch.of(
      baseRoot: checkout('base', pinning: sdk('one', version: '3.47.0')),
      headRoot: checkout('head', pinning: sdk('two', version: '3.47.0')),
    );

    expect(match.same, isTrue);
  });

  test('different versions are refused, and both are named', () async {
    var match = await SdkMatch.of(
      baseRoot: checkout('base', pinning: sdk('old', version: '3.44.0')),
      headRoot: checkout('head', pinning: sdk('new', version: '3.47.0')),
    );

    expect(match.same, isFalse);
    expect(match.reason, contains('3.44.0'));
    expect(match.reason, contains('3.47.0'));
  });

  // The framework can move without the engine, but never the reverse: the
  // engine hash is what decides whether a rounded rect has the same pixels.
  test('one version, two engines, is a mismatch', () async {
    var match = await SdkMatch.of(
      baseRoot: checkout(
        'base',
        pinning: sdk('a', version: '3.47.0', engine: 'engine-1'),
      ),
      headRoot: checkout(
        'head',
        pinning: sdk('b', version: '3.47.0', engine: 'engine-2'),
      ),
    );

    expect(match.same, isFalse);
  });

  // An SDK that wrote nothing down is an SDK this tool does not recognise, and
  // "unknown equals unknown" is the answer that lets a wrong comparison
  // through.
  test('an unreadable SDK never matches a different one', () async {
    var match = await SdkMatch.of(
      baseRoot: checkout('base', pinning: sdk('bare')),
      headRoot: checkout('head', pinning: sdk('known', version: '3.47.0')),
    );

    expect(match.same, isFalse);
  });

  test('a checkout with no SDK at all says so, and names which side', () async {
    var match = await SdkMatch.of(
      baseRoot: checkout('base'),
      headRoot: checkout('head', pinning: sdk('beta', version: '3.47.0')),
    );

    expect(match.same, isFalse);
    expect(match.reason, contains('base'));
  });

  // The exact case the seeded link papers over: a base checkout is handed the
  // head's SDK so it can build, but its own commit pins something else. The
  // committed claim outranks the link.
  test('the flutter_version claim outranks a seeded link', () async {
    var head = sdk('beta', version: '3.47.0');
    var match = await SdkMatch.of(
      baseRoot: checkout('base', pinning: head, claims: '3.44.0'),
      headRoot: checkout('head', pinning: head, claims: '3.47.0'),
    );

    expect(match.same, isFalse);
    expect(match.reason, contains('3.44.0'));
    expect(match.reason, contains('3.47.0'));
  });

  test(
    'flutter_version wins over .fvmrc when a checkout carries both',
    () async {
      var pinned = sdk('beta', version: '3.47.0');
      var match = await SdkMatch.of(
        baseRoot: checkout(
          'base',
          pinning: pinned,
          claims: '3.47.0',
          fvmrc: '3.44.0',
        ),
        headRoot: checkout('head', pinning: pinned, claims: '3.47.0'),
      );

      expect(match.same, isTrue);
    },
  );
}
