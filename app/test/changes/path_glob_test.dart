import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/path_glob.dart';

/// Every case here was measured against `package:glob` first, and the ones
/// marked below are the ones it gets wrong for this use. They are not
/// hypothetical: `**/*.g.dart` is the spelling everybody carries over from
/// `.gitignore`, and a rule that silently never fires is the exact failure the
/// Dart config exists to prevent.
void main() {
  void expectMatch(String pattern, String path, {required bool matches}) {
    expect(
      PathGlobSet([pattern]).firstMatch(path) != null,
      matches,
      reason: '$pattern vs $path',
    );
  }

  group('the .gitignore anchoring rules', () {
    test('a leading **/ also matches at the repository root', () {
      // package:glob says false for the second one.
      expectMatch('**/*.g.dart', 'lib/a.g.dart', matches: true);
      expectMatch('**/*.g.dart', 'a.g.dart', matches: true);
      expectMatch('**/*.g.dart', 'lib/src/deep/a.g.dart', matches: true);

      expectMatch('**/migrations/**', 'db/migrations/1.sql', matches: true);
      expectMatch('**/migrations/**', 'migrations/1.sql', matches: true);
    });

    test('a pattern with no slash matches the name at any depth', () {
      // package:glob says false for everything but the first.
      expectMatch('*.sql', 'a.sql', matches: true);
      expectMatch('*.sql', 'db/a.sql', matches: true);
      expectMatch('pubspec.lock', 'app/pubspec.lock', matches: true);
      expectMatch('pubspec.lock', 'pubspec.lock', matches: true);
    });

    test('a pattern with a slash is anchored, as .gitignore anchors it', () {
      expectMatch('openapi.yaml', 'api/openapi.yaml', matches: true);
      expectMatch('api/openapi.yaml', 'openapi.yaml', matches: false);
      expectMatch('api/openapi.yaml', 'v2/api/openapi.yaml', matches: false);
    });

    test('a trailing slash means the directory and everything under it', () {
      expectMatch('build/', 'build/app/x.dill', matches: true);
      expectMatch('build/', 'build/x', matches: true);
      // The directory entry itself is not a file and never appears as a path,
      // but a *sibling* whose name merely starts the same must not match.
      expectMatch('build/', 'buildings/x.dart', matches: false);
    });

    test('a separator is never crossed by a single star', () {
      expectMatch('lib/*.dart', 'lib/a.dart', matches: true);
      expectMatch('lib/*.dart', 'lib/src/a.dart', matches: false);
    });

    test('backslashes and a leading ./ are the same path', () {
      expectMatch(r'lib\src\*.dart', 'lib/src/a.dart', matches: true);
      expectMatch('lib/src/*.dart', r'lib\src\a.dart', matches: true);
      expectMatch('./lib/*.dart', 'lib/a.dart', matches: true);
    });
  });

  test('a pattern that will not compile costs that rule and nothing else', () {
    // The probe runs inside an isolate: a stray bracket in one attention rule
    // must cost that rule, not the file list.
    late PathGlobSet set;
    expect(() => set = PathGlobSet(['lib/[.dart', 'lib/**']), returnsNormally);
    expect(set.firstMatch('lib/a.dart'), 'lib/**');
  });

  group('PathGlobSet', () {
    test('names the first pattern that matched, in written order', () {
      var set = PathGlobSet(['**/*.g.dart', 'lib/**']);
      expect(set.firstMatch('lib/a.g.dart'), '**/*.g.dart');
      expect(set.firstMatch('lib/a.dart'), 'lib/**');
      expect(set.firstMatch('bin/a.dart'), isNull);
    });

    test('an empty set matches nothing', () {
      expect(PathGlobSet(const []).firstMatch('lib/a.dart'), isNull);
      expect(PathGlobSet(const []).isEmpty, isTrue);
    });
  });
}
