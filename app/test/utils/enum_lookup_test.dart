import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/enum_lookup.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// The bounded lookup entry-point knobs and catalog demos both ask.
///
/// The shapes here are the ones people write — a barrel with a combinator, a
/// prefixed import, an enum whose values take arguments — rather than the one
/// that is easy to support.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw-enum-'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String content) => File(p.join(root.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  String at(String path) => p.join(root.path, path);

  /// The resolution a `dart pub get` would have left, for `package:app/…`.
  ///
  /// `packageUriRoot` is `lib/` — the thing a hand-built config gets wrong and
  /// pub never does, which is why it is spelled out here.
  PackageConfig configFor(String packageRoot) => PackageConfig([
    Package(
      'app',
      Uri.directory(p.join(root.path, packageRoot, '')),
      packageUriRoot: Uri.directory(p.join(root.path, packageRoot, 'lib', '')),
    ),
  ]);

  test('finds an enum declared in the file itself', () {
    write('main.dart', '''
enum Backend { dev, staging, prod }
void main({Backend backend = Backend.dev}) {}
''');

    var found = EnumLookup().lookup(file: at('main.dart'), name: 'Backend');

    expect(found.found, isTrue);
    expect(found.values, ['dev', 'staging', 'prod']);
    expect(found.declaredIn, at('main.dart'));
  });

  test('follows a direct import', () {
    write('src/backend.dart', 'enum Backend { dev, prod }');
    write('main.dart', "import 'src/backend.dart';");

    expect(EnumLookup().lookup(file: at('main.dart'), name: 'Backend').values, [
      'dev',
      'prod',
    ]);
  });

  test('follows a barrel, through its show combinator, under a prefix', () {
    // The shape measured working end to end 2026-08-13: the wrapper copies
    // `import 'models.dart' as m` and writes `m.Backend.staging`.
    write('src/backend.dart', '''
enum Backend { dev, staging, prod }
enum Hidden { a, b }
''');
    write('models.dart', "export 'src/backend.dart' show Backend;");
    write('main.dart', "import 'models.dart' as m;");

    var lookup = EnumLookup();
    var backend = lookup.lookup(
      file: at('main.dart'),
      name: 'Backend',
      prefix: 'm',
    );
    expect(backend.values, ['dev', 'staging', 'prod']);
    expect(backend.declaredIn, at('src/backend.dart'));

    // `show Backend` means the barrel does not offer `Hidden`, and neither do
    // we — the combinator is honoured rather than ignored.
    expect(
      lookup.lookup(file: at('main.dart'), name: 'Hidden', prefix: 'm').problem,
      contains('no enum Hidden'),
    );
  });

  test('a value with arguments is still just its name', () {
    write('main.dart', '''
enum Level {
  low(1),
  high(9);

  const Level(this.weight);
  final int weight;
}
''');

    expect(EnumLookup().lookup(file: at('main.dart'), name: 'Level').values, [
      'low',
      'high',
    ]);
  });

  test('a prefixed import cannot answer an unprefixed name, or the reverse', () {
    write('src/backend.dart', 'enum Backend { dev }');
    write('main.dart', "import 'src/backend.dart' as m;");

    var lookup = EnumLookup();
    // Written bare, it cannot come from a prefixed import — that is a language
    // rule, not a limit of the search.
    expect(
      lookup.lookup(file: at('main.dart'), name: 'Backend').problem,
      isNotNull,
    );
    expect(
      lookup.lookup(file: at('main.dart'), name: 'Backend', prefix: 'm').values,
      ['dev'],
    );
    // A prefix nothing declares is a miss, not a match on the same-named import.
    expect(
      lookup
          .lookup(file: at('main.dart'), name: 'Backend', prefix: 'other')
          .problem,
      isNotNull,
    );
  });

  test('one enum reached two ways is one enum, not an ambiguity', () {
    // Importing both a barrel and the file behind it is ordinary code, and
    // refusing it would refuse ordinary code.
    write('src/backend.dart', 'enum Backend { dev }');
    write('models.dart', "export 'src/backend.dart';");
    write('main.dart', '''
import 'models.dart';
import 'src/backend.dart';
''');

    expect(EnumLookup().lookup(file: at('main.dart'), name: 'Backend').values, [
      'dev',
    ]);
  });

  test('two different declarations are refused, naming both', () {
    write('a.dart', 'enum Backend { dev }');
    write('b.dart', 'enum Backend { prod }');
    write('main.dart', '''
import 'a.dart';
import 'b.dart';
''');

    var problem = EnumLookup()
        .lookup(file: at('main.dart'), name: 'Backend')
        .problem;
    expect(problem, contains('2 different declarations'));
    expect(problem, allOf(contains('a.dart'), contains('b.dart')));
  });

  test('a local declaration shadows an imported one', () {
    write('src/backend.dart', 'enum Backend { imported }');
    write('main.dart', '''
import 'src/backend.dart';
enum Backend { local }
''');

    expect(EnumLookup().lookup(file: at('main.dart'), name: 'Backend').values, [
      'local',
    ]);
  });

  test('an enum in a part belongs to the library that has the part', () {
    write('src/models.g.dart', "part of 'models.dart';\nenum Backend { dev }");
    write('models.dart', "part 'src/models.g.dart';");
    write('main.dart', "import 'models.dart';");

    expect(EnumLookup().lookup(file: at('main.dart'), name: 'Backend').values, [
      'dev',
    ]);
  });

  test('resolves a package: import when it has a config', () {
    write('pkg/lib/src/backend.dart', 'enum Backend { dev }');
    write('pkg/lib/models.dart', "export 'src/backend.dart';");
    write('main.dart', "import 'package:app/models.dart';");

    expect(
      EnumLookup(
        packageConfig: configFor('pkg'),
      ).lookup(file: at('main.dart'), name: 'Backend').values,
      ['dev'],
    );
  });

  test('without a config, a package: import is a miss rather than a crash', () {
    write('main.dart', "import 'package:app/models.dart';");

    expect(
      EnumLookup().lookup(file: at('main.dart'), name: 'Backend').problem,
      contains('no enum Backend'),
    );
  });

  test('import chains are the bound, and the refusal says what to do', () {
    // `deep.dart` is imported by `middle.dart`, not by `main.dart`. Following
    // it would be following an import chain, which is exactly the cost this
    // lookup exists to avoid.
    write('deep.dart', 'enum Backend { dev }');
    write('middle.dart', "import 'deep.dart';");
    write('main.dart', "import 'middle.dart';");

    var problem = EnumLookup()
        .lookup(file: at('main.dart'), name: 'Backend')
        .problem;
    expect(problem, contains('direct imports'));
    expect(problem, contains('export it from a file that entry point already'));
  });

  test('mutually exporting libraries terminate', () {
    write('a.dart', "export 'b.dart';");
    write('b.dart', "export 'a.dart';");
    write('main.dart', "import 'a.dart';");

    expect(
      EnumLookup().lookup(file: at('main.dart'), name: 'Backend').found,
      isFalse,
    );
  });

  test('a file that will not parse is recovered as far as it can be', () {
    // Measured rather than assumed: the parser recovers this into `Backend`
    // with constants `[dev, '', '']`. Answering from a file the compiler would
    // reject is fine — the compiler will say so, loudly, seconds later — but a
    // picker offering two blank options is not, so the blanks are dropped.
    write('broken.dart', 'enum Backend { dev,,,');
    write('main.dart', "import 'broken.dart';");

    expect(EnumLookup().lookup(file: at('main.dart'), name: 'Backend').values, [
      'dev',
    ]);
  });

  test('a file that is not there at all is a miss, not a crash', () {
    write('main.dart', "import 'gone.dart';");

    expect(
      EnumLookup().lookup(file: at('main.dart'), name: 'Backend').found,
      isFalse,
    );
  });
}
