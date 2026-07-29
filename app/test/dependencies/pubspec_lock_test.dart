import 'dart:io';

import 'package:flutterware_app/src/dependencies/model/package_origin.dart';
import 'package:flutterware_app/src/dependencies/model/pubspec_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every `description:` shape pub writes, taken from real lockfiles. The one
/// that used to break things is `sdk`, whose description is a bare string where
/// the other three are maps.
const _lock = '''
packages:
  path_provider:
    dependency: transitive
    description:
      name: path_provider
      sha256: a7f4874f987173da295a61c181b8ee71dab59b332a486b391babf26a1b884825
      url: "https://pub.dev"
    source: hosted
    version: "2.1.6"
  internal_thing:
    dependency: "direct main"
    description:
      name: internal_thing
      sha256: "deadbeef"
      url: "https://pub.mycompany.dev"
    source: hosted
    version: "3.0.0"
  pub_scores:
    dependency: transitive
    description:
      path: "."
      ref: master
      resolved-ref: "2461ab5f79f44c8a4dccd932503697af5779b417"
      url: "https://github.com/xvrh/pub-scores.git"
    source: git
    version: "1.0.0"
  nested_git:
    dependency: transitive
    description:
      path: "packages/inner"
      ref: v2
      resolved-ref: "0123456789abcdef0123456789abcdef01234567"
      url: "git@github.com:acme/monorepo.git"
    source: git
    version: "1.0.0"
  vendor:
    dependency: "direct dev"
    description:
      path: ".."
      relative: true
    source: path
    version: "1.4.0"
  sky_engine:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.0"
''';

void main() {
  var lock = PubspecLock.parse(_lock);

  PackageOrigin originOf(String name) => PackageOrigin.fromLock(lock[name]!);

  test('the resolved version is kept', () {
    expect(lock['path_provider']!.version, '2.1.6');
    expect(lock['sky_engine']!.version, '0.0.0');
  });

  test('the description survives parsing', () {
    // It used to be read and dropped, which is why a git dependency and a pub
    // dependency were indistinguishable in the UI.
    expect(lock['pub_scores']!.description, isA<Map<String, Object?>>());
    expect(
      (lock['pub_scores']!.description! as Map)['url'],
      'https://github.com/xvrh/pub-scores.git',
    );
  });

  group('origin', () {
    test('a pub.dev package says only that', () {
      var origin = originOf('path_provider');
      expect(origin, isA<HostedOrigin>());
      expect((origin as HostedOrigin).isPubDev, isTrue);
      expect(origin.label, 'pub.dev');
      expect(origin.detail, isNull);
    });

    test('a private server is worth showing', () {
      var origin = originOf('internal_thing') as HostedOrigin;
      expect(origin.isPubDev, isFalse);
      expect(origin.label, 'hosted');
      expect(origin.detail, 'https://pub.mycompany.dev');
    });

    test('git reports slug, ref and resolved commit', () {
      var origin = originOf('pub_scores') as GitOrigin;
      expect(origin.slug, 'xvrh/pub-scores');
      expect(origin.shortRef, 'master@2461ab5');
      expect(origin.subPath, isNull, reason: '"." is the repository root');
      expect(origin.detail, 'xvrh/pub-scores');
    });

    test('git keeps a subdirectory when there is one', () {
      var origin = originOf('nested_git') as GitOrigin;
      expect(origin.subPath, 'packages/inner');
      expect(origin.detail, endsWith('/packages/inner'));
      expect(origin.shortRef, 'v2@0123456');
    });

    test('a path dependency reports its path', () {
      var origin = originOf('vendor') as PathOrigin;
      expect(origin.path, '..');
      expect(origin.relative, isTrue);
      expect(origin.label, 'path');
    });

    test('an SDK package survives its scalar description', () {
      // `description: flutter` is a string, not a map. Reading it as a map is
      // how this used to throw.
      var origin = originOf('sky_engine') as SdkOrigin;
      expect(origin.sdk, 'flutter');
      expect(origin.label, 'Flutter SDK');
    });

    test('an unrecognised source reports itself instead of throwing', () {
      var odd = PubspecLock.parse('''
packages:
  weird:
    dependency: transitive
    description: something
    source: some_future_source
    version: "1.0.0"
''');
      expect(
        PackageOrigin.fromLock(odd['weird']!),
        isA<UnknownOrigin>().having(
          (e) => e.label,
          'label',
          'some_future_source',
        ),
      );
    });
  });

  group('finding the file', () {
    test('walks up to the workspace root', () async {
      var temp = await Directory.systemTemp.createTemp('fw_lock_test');
      addTearDown(() => temp.delete(recursive: true));

      var member = Directory(p.join(temp.path, 'packages', 'member'))
        ..createSync(recursive: true);
      File(p.join(temp.path, 'pubspec.lock')).writeAsStringSync(_lock);

      // A pub workspace has one lockfile at the root and none in the members.
      // Looking only beside the package — which is what this used to do — found
      // nothing, and every package then classified as direct.
      var found = await PubspecLock.load(member.path);
      expect(found, isNotNull);
      expect(found!['path_provider']!.version, '2.1.6');
    });

    test("prefers the package's own lockfile when it has one", () async {
      var temp = await Directory.systemTemp.createTemp('fw_lock_test');
      addTearDown(() => temp.delete(recursive: true));

      var member = Directory(p.join(temp.path, 'standalone'))
        ..createSync(recursive: true);
      File(p.join(temp.path, 'pubspec.lock')).writeAsStringSync(_lock);
      File(p.join(member.path, 'pubspec.lock')).writeAsStringSync('''
packages:
  path_provider:
    dependency: transitive
    description:
      name: path_provider
      url: "https://pub.dev"
    source: hosted
    version: "9.9.9"
''');

      var found = await PubspecLock.load(member.path);
      expect(found!['path_provider']!.version, '9.9.9');
    });

    test('is null when nothing above has one', () async {
      var temp = await Directory.systemTemp.createTemp('fw_lock_test');
      addTearDown(() => temp.delete(recursive: true));
      // Nothing is written, and the walk runs out at the filesystem root.
      expect(await PubspecLock.load(temp.path), isNull);
    });
  });
}
