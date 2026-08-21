import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/assets/model/asset_catalog.dart';
import 'package:flutterware_app/src/previews/asset_transformer.dart';
import 'package:path/path.dart' as p;

import '../support/dart_executable.dart';

/// Running a declaration's `transformers:` so the bundle serves the bytes a
/// build would ship, rather than the source the loader cannot decode.
///
/// The transformers here are real processes, tiny Dart programs written per
/// test and resolved as path dependencies of a real fixture project. A fake
/// would test the cache and not the thing worth testing — that the contract
/// `flutter_tools` spawns against (`dart run <package>`, `--input`, `--output`,
/// chained, exit code, output present) is the contract we spawn. Resolution is
/// offline and costs ~25ms, so the fidelity is close to free.
void main() {
  late Directory root;
  late String dart;

  /// The `dart` of the SDK running this test — never `Platform.
  /// resolvedExecutable`, which under `flutter test` is `flutter_tester` and
  /// hangs every `pub get` in this file for its full timeout.
  setUpAll(() => dart = resolveDartExecutable());

  setUp(() {
    root = Directory.systemTemp.createTempSync('asset_transformer_test');
  });

  tearDown(() => root.deleteSync(recursive: true));

  String projectRoot() => p.join(root.path, 'project');

  void write(String relative, String content) {
    File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Reads `--input`, writes `--output`, and applies [transform] to the text.
  ///
  /// `rest` is every other argument, so a test can prove the declared args
  /// arrive.
  String transformerSource(String transform) =>
      '''
import 'dart:io';
void main(List<String> args) {
  var input = args.firstWhere((a) => a.startsWith('--input=')).substring(8);
  var output = args.firstWhere((a) => a.startsWith('--output=')).substring(9);
  var rest = args.where((a) =>
      !a.startsWith('--input=') && !a.startsWith('--output='));
  var text = File(input).readAsStringSync();
  File(output)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync($transform);
}
''';

  /// A transformer package named [name], living in directory [directory],
  /// whose executable body is [body].
  void writeTransformer(String name, String body, {String? directory}) {
    write('${directory ?? name}/pubspec.yaml', '''
name: $name
environment:
  sdk: ^3.0.0
''');
    write('${directory ?? name}/bin/$name.dart', body);
  }

  /// Resolves the fixture project against [transformers] — a package name to
  /// the directory it lives in — and returns a runner pointed at it.
  Future<AssetTransformerRunner> resolve(
    Map<String, String> transformers,
  ) async {
    write('project/pubspec.yaml', '''
name: project
environment:
  sdk: ^3.0.0
dependencies:
${transformers.entries.map((e) => '  ${e.key}:\n    path: ../${e.value}').join('\n')}
''');
    var result = await Process.run(dart, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: projectRoot());
    expect(
      result.exitCode,
      0,
      reason: 'fixture resolution failed:\n${result.stdout}${result.stderr}',
    );
    return AssetTransformerRunner(
      dart: dart,
      projectRoot: projectRoot(),
      packageConfigPath: p.join(
        projectRoot(),
        '.dart_tool',
        'package_config.json',
      ),
      cacheDir: p.join(root.path, 'cache'),
    );
  }

  AssetFile assetFile(String relative) => AssetFile(
    path: p.join(projectRoot(), relative),
    key: relative,
    scale: null,
  );

  test('serves the transformer output, not the source', () async {
    writeTransformer('upcase', transformerSource('text.toUpperCase()'));
    write('project/assets/logo.svg', 'source bytes');
    var runner = await resolve({'upcase': 'upcase'});

    var path = await runner.pathFor(assetFile('assets/logo.svg'), const [
      AssetTransformer(package: 'upcase'),
    ]);

    expect(File(path).readAsStringSync(), 'SOURCE BYTES');
    expect(
      path,
      isNot(assetFile('assets/logo.svg').path),
      reason: 'the bundle must point somewhere other than the project file',
    );
  });

  test('a file with no transformers is its own path, untouched', () async {
    write('project/assets/logo.png', 'bytes');
    var runner = await resolve(const {});

    var file = assetFile('assets/logo.png');
    expect(await runner.pathFor(file, const []), file.path);
  });

  test('chains, and each output is the next input', () async {
    // Order is the whole contract. Reversed, both transformers still run and
    // the bundle still resolves — to bytes no build would produce.
    writeTransformer('upcase', transformerSource('text.toUpperCase()'));
    writeTransformer('exclaim', transformerSource("text + '!'"));
    write('project/assets/logo.svg', 'hi');
    var runner = await resolve({'upcase': 'upcase', 'exclaim': 'exclaim'});

    var path = await runner.pathFor(assetFile('assets/logo.svg'), const [
      AssetTransformer(package: 'upcase'),
      AssetTransformer(package: 'exclaim'),
    ]);

    expect(File(path).readAsStringSync(), 'HI!');
  });

  test('passes the declared args through', () async {
    writeTransformer('suffix', transformerSource('text + rest.join()'));
    write('project/assets/logo.svg', 'a');
    var runner = await resolve({'suffix': 'suffix'});

    var path = await runner.pathFor(assetFile('assets/logo.svg'), const [
      AssetTransformer(package: 'suffix', args: ['-x', '-y']),
    ]);

    expect(File(path).readAsStringSync(), 'a-x-y');
  });

  test('a second call is a cache hit, and spawns nothing', () async {
    // The cache is what makes this affordable on every bundle sync. Proven by
    // breaking the transformer between the calls: a second spawn could not
    // produce this answer.
    writeTransformer('upcase', transformerSource('text.toUpperCase()'));
    write('project/assets/logo.svg', 'hi');
    var runner = await resolve({'upcase': 'upcase'});
    var file = assetFile('assets/logo.svg');
    const chain = [AssetTransformer(package: 'upcase')];

    var first = await runner.pathFor(file, chain);
    write('upcase/bin/upcase.dart', 'void main() { throw "never runs"; }');

    expect(await runner.pathFor(file, chain), first);
    expect(File(first).readAsStringSync(), 'HI');
  });

  test(
    'edited content is a different key, so a stale hit cannot happen',
    () async {
      writeTransformer('upcase', transformerSource('text.toUpperCase()'));
      write('project/assets/logo.svg', 'first');
      var runner = await resolve({'upcase': 'upcase'});
      var file = assetFile('assets/logo.svg');
      const chain = [AssetTransformer(package: 'upcase')];

      var before = await runner.pathFor(file, chain);
      // Content, not mtime: an edit that keeps the length still moves the key.
      write('project/assets/logo.svg', 'other');
      var after = await runner.pathFor(file, chain);

      expect(after, isNot(before));
      expect(File(after).readAsStringSync(), 'OTHER');
    },
  );

  test('different args are a different key', () async {
    writeTransformer('suffix', transformerSource('text + rest.join()'));
    write('project/assets/logo.svg', 'a');
    var runner = await resolve({'suffix': 'suffix'});
    var file = assetFile('assets/logo.svg');

    var one = await runner.pathFor(file, const [
      AssetTransformer(package: 'suffix', args: ['-x']),
    ]);
    var two = await runner.pathFor(file, const [
      AssetTransformer(package: 'suffix', args: ['-y']),
    ]);

    expect(two, isNot(one));
    expect(File(one).readAsStringSync(), 'a-x');
    expect(File(two).readAsStringSync(), 'a-y');
  });

  test('the same package resolved elsewhere is a different key', () async {
    // What makes a bumped transformer recompile without anything here reading a
    // version: a hosted root carries it, so `…/pkg-1.2.0/` becomes
    // `…/pkg-1.3.0/` and the key moves on its own. Spelled here as the same
    // package name resolved to a second directory, which is what the package
    // config sees a bump as.
    writeTransformer('upcase', transformerSource('text.toUpperCase()'));
    writeTransformer(
      'upcase',
      transformerSource("text.toUpperCase() + '2'"),
      directory: 'upcase_next',
    );
    write('project/assets/logo.svg', 'hi');
    var file = assetFile('assets/logo.svg');
    const chain = [AssetTransformer(package: 'upcase')];

    var before = await (await resolve({
      'upcase': 'upcase',
    })).pathFor(file, chain);
    var after = await (await resolve({
      'upcase': 'upcase_next',
    })).pathFor(file, chain);

    expect(after, isNot(before));
    expect(File(before).readAsStringSync(), 'HI');
    expect(File(after).readAsStringSync(), 'HI2');
  });

  test('a failing transformer throws, naming it and quoting it', () async {
    // Never a fallback to the source. Linking that would put undecodable bytes
    // at a key that resolves, which is the exact failure this ends — and the
    // one that reads as the widget being wrong.
    writeTransformer('broken', '''
import 'dart:io';
void main(List<String> args) {
  stderr.writeln('cannot parse line 3');
  exit(2);
}
''');
    write('project/assets/logo.svg', 'hi');
    var runner = await resolve({'broken': 'broken'});

    await expectLater(
      runner.pathFor(assetFile('assets/logo.svg'), const [
        AssetTransformer(package: 'broken'),
      ]),
      throwsA(
        isA<AssetTransformerException>().having(
          (e) => '$e',
          'message',
          allOf(
            contains('broken'),
            contains('exit 2'),
            contains('cannot parse line 3'),
          ),
        ),
      ),
    );
  });

  test('a transformer that exits 0 and writes nothing is a failure', () async {
    // The tool treats a missing output as a failure too, and it is the shape a
    // misspelled flag takes: the process is content and the bundle has a hole.
    writeTransformer('silent', 'void main(List<String> args) {}\n');
    write('project/assets/logo.svg', 'hi');
    var runner = await resolve({'silent': 'silent'});

    await expectLater(
      runner.pathFor(assetFile('assets/logo.svg'), const [
        AssetTransformer(package: 'silent'),
      ]),
      throwsA(isA<AssetTransformerException>()),
    );
  });

  test('an entry nothing has produced for a month is swept', () async {
    // The cache has no natural bound: every edited asset leaves its predecessor
    // behind for ever. Swept on a miss only, so the warm path stays free — and
    // safely, because an entry is keyed by content and so is only ever stale.
    writeTransformer('upcase', transformerSource('text.toUpperCase()'));
    write('project/assets/logo.svg', 'hi');
    var runner = await resolve({'upcase': 'upcase'});
    var file = assetFile('assets/logo.svg');
    const chain = [AssetTransformer(package: 'upcase')];

    var kept = await runner.pathFor(file, chain);
    var ancient = File(p.join(root.path, 'cache', 'ancient.svg'))
      ..writeAsStringSync('from a project nobody has opened since');
    ancient.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 40)),
    );

    // A fresh runner, because the sweep is once per instance — and a miss,
    // because that is the only thing that triggers it.
    write('project/assets/logo.svg', 'moved on');
    await (await resolve({'upcase': 'upcase'})).pathFor(file, chain);

    expect(ancient.existsSync(), isFalse);
    expect(
      File(kept).existsSync(),
      isTrue,
      reason: 'an entry produced moments ago is not old',
    );
  });
}
