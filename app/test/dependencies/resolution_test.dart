import 'dart:io';

import 'package:flutterware_app/src/dependencies/model/package_origin.dart';
import 'package:flutterware_app/src/dependencies/model/pub_deps.dart';
import 'package:flutterware_app/src/dependencies/model/pubspec_lock.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

/// Runs off a captured `dart pub deps --json` for this repo — a three-member
/// pub workspace — so nothing here needs a resolved project, an SDK, or a
/// subprocess.
void main() {
  var pubDeps = PubDeps.parse(
    File('test/dependencies/fixtures/pub_deps.json').readAsStringSync(),
  );

  Dependencies resolveFor(String name, {PubspecLock? lock}) =>
      Dependencies.resolve(
        pubspec: Pubspec.parse('name: $name\nenvironment:\n  sdk: ^3.6.0\n'),
        pubDeps: pubDeps,
        lock: lock,
        packageConfig: null,
        readPubspec: (_) => null,
      );

  group('pub deps', () {
    test('reports the whole workspace, not the directory it ran in', () {
      expect(pubDeps.packages, hasLength(174));
      expect(
        pubDeps.members.map((e) => e.name),
        containsAll(['flutterware_example', 'flutterware', 'flutterware_app']),
      );
      // The trap this model exists to route around: `root` names the workspace
      // root package regardless of which member the command ran in.
      expect(pubDeps.root, 'flutterware');
    });

    test('carries the constraint each package declared', () {
      var test = pubDeps['test']!;
      expect(test.dependencyConstraints['async'], '^2.5.0');
      expect(test.dependencyConstraints['analyzer'], '>=8.0.0 <14.0.0');
    });

    test('devDependencies are populated only for members', () {
      expect(
        pubDeps.memberNamed('flutterware_example')!.devDependencies,
        isNotEmpty,
      );
      expect(pubDeps['test']!.devDependencies, isEmpty);
    });

    test('memberNamed refuses a package that is not a member', () {
      expect(pubDeps.memberNamed('test'), isNull);
      expect(pubDeps.memberNamed('nope'), isNull);
    });
  });

  group('scoping to one member', () {
    test('classifies against the member, not the workspace', () {
      var dependencies = resolveFor('flutterware_example');

      // The regression. This member declares 14 dependencies and 4 dev
      // dependencies; the workspace resolves 174 packages. Deriving direct-ness
      // from the (absent) member lockfile reported 170 direct, 0 transitive.
      expect(dependencies.directs, hasLength(14));
      expect(dependencies.devs, hasLength(4));
      expect(dependencies.transitives, isNotEmpty);
      expect(dependencies.dependencies.length, lessThan(174));

      expect(dependencies.directs.map((e) => e.name), contains('flutterware'));
      expect(dependencies.devs.map((e) => e.name), contains('flutter_test'));
    });

    test('excludes what only a sibling member reaches', () {
      var names = resolveFor('flutterware_example').dependencies
          .map((e) => e.name)
          .toSet();

      // `file_picker` and `dart_mcp` are dependencies of flutterware_app. They
      // are in the shared resolution but unreachable from this member — 107 of
      // the 174 resolved packages are.
      expect(names, isNot(contains('file_picker')));
      expect(names, isNot(contains('dart_mcp')));
      expect(names, hasLength(107));
    });

    test('a sibling member reaches its own dependencies', () {
      var names = resolveFor('flutterware_app').dependencies
          .map((e) => e.name)
          .toSet();
      expect(names, contains('file_picker'));
      expect(names, hasLength(147));
    });

    test('a member is never listed among its own dependencies', () {
      var dependencies = resolveFor('flutterware_example');
      expect(
        dependencies.dependencies.map((e) => e.name),
        isNot(contains('flutterware_example')),
      );
    });

    test("does not propagate a dependency's dev_dependencies", () {
      // The member depends on `flutterware`, which is itself a workspace member
      // and so is the one kind of dependency that *has* resolved
      // dev_dependencies to leak. Traversal follows directDependencies for
      // exactly this reason: pub does not resolve a dependency's dev deps for
      // its consumers, so propagating them would invent edges.
      var names = resolveFor('flutterware_example').dependencies
          .map((e) => e.name)
          .toSet();
      expect(names, contains('flutterware'));
      for (var devOnly in [
        'build_runner',
        'json_serializable',
        'dart_style',
        'process_runner',
      ]) {
        expect(
          names,
          isNot(contains(devOnly)),
          reason:
              '$devOnly is a dev dependency of flutterware, and not '
              'something the example ever asked for',
        );
      }
    });

    test('falls back to the sole member when the name does not match', () {
      // A rename between `pub get` and now is still unambiguous in a
      // single-package project — but not here, where there are three.
      expect(
        () => resolveFor('renamed_since_pub_get'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('dependants', () {
    test('are confined to the reachable subgraph', () {
      var dependencies = resolveFor('flutterware_example');
      for (var dependency in dependencies.dependencies) {
        for (var dependant in dependency.dependants) {
          expect(
            dependant == dependencies.memberName ||
                dependencies[dependant] != null,
            isTrue,
            reason:
                '${dependency.name} claims a dependant ($dependant) that is '
                'outside the graph of this member',
          );
        }
      }
    });

    test('a chain starts at the member and ends at the package', () {
      var dependencies = resolveFor('flutterware_example');
      var async = dependencies['async']!;

      expect(async.isTransitive, isTrue);
      expect(async.dependencyPaths, isNotEmpty);
      for (var path in async.dependencyPaths) {
        expect(path.first, 'flutterware_example');
        expect(path.last, 'async');
      }
    });

    test('a direct dependency reports the one-hop chain first', () {
      var dependencies = resolveFor('flutterware_example');
      expect(dependencies['flutterware']!.dependencyPaths.first, [
        'flutterware_example',
        'flutterware',
      ]);
    });

    test('chains are cached rather than recomputed', () {
      var dependency = resolveFor('flutterware_example')['async']!;
      expect(
        identical(dependency.dependencyPaths, dependency.dependencyPaths),
        isTrue,
      );
    });
  });

  group('version and origin', () {
    var lock = PubspecLock.parse('''
packages:
  path:
    dependency: transitive
    description:
      name: path
      sha256: "abc"
      url: "https://pub.dev"
    source: hosted
    version: "1.9.1"
  pub_scores:
    dependency: transitive
    description:
      path: "."
      ref: master
      resolved-ref: "2461ab5f79f44c8a4dccd932503697af5779b417"
      url: "https://github.com/xvrh/pub-scores.git"
    source: git
    version: "1.0.0"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
''');

    test('resolved version comes from the lock, not the package pubspec', () {
      var dependencies = resolveFor('flutterware_example', lock: lock);
      expect(dependencies['path']!.resolvedVersion, '1.9.1');
    });

    test('a constraint is carried for what the member declared', () {
      var dependencies = resolveFor('flutterware_example', lock: lock);
      // The example declares bare `path:`, which is the constraint `any`.
      expect(dependencies['path']!.constraint, 'any');
    });

    test('a transitive dependency has no constraint from this member', () {
      var dependencies = resolveFor('flutterware_example', lock: lock);
      expect(dependencies['async']!.constraint, isNull);
    });

    test('SDK packages are not described by their version', () {
      var flutter = resolveFor('flutterware_example', lock: lock)['flutter']!;
      expect(flutter.hasMeaningfulVersion, isFalse);
      expect(flutter.origin, isA<SdkOrigin>());
      expect(flutter.origin.label, 'Flutter SDK');
    });

    test('a git dependency reports its repository and ref', () {
      var scores = resolveFor('flutterware_app', lock: lock)['pub_scores']!;
      var origin = scores.origin;
      expect(origin, isA<GitOrigin>());
      origin as GitOrigin;
      expect(origin.slug, 'xvrh/pub-scores');
      expect(origin.shortRef, 'master@2461ab5');
      // `.` means the package is at the repository root — not worth showing.
      expect(origin.subPath, isNull);
      expect(origin.detail, 'xvrh/pub-scores');
    });

    test('a package with no lock entry still reports a source', () {
      // No lock at all — the case that used to produce a blank cell for every
      // package of every workspace member.
      var dependencies = resolveFor('flutterware_example');
      var path = dependencies['path']!;
      expect(path.origin, isA<HostedOrigin>());
      expect(path.node.source, 'hosted');
      expect(dependencies['flutterware']!.origin, isA<WorkspaceOrigin>());
    });
  });
}
