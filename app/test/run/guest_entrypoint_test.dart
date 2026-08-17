import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/guest_entrypoint.dart';
import 'package:path/path.dart' as p;

/// The generated wrapper that turns a plain launch into a driveable app —
/// and the two ways generation declines, both of which launch uninstrumented
/// rather than failing.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('guest_entrypoint_test');
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: shop_app\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('wraps a lib/ entrypoint in the run guest', () {
    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'lib/main_dev.dart',
    );

    expect(result.guest, isTrue);
    expect(result.target, '.dart_tool/flutterware/run/main_dev_guest.dart');
    var content = File(
      p.joinAll([root.path, ...p.posix.split(result.target)]),
    ).readAsStringSync();
    expect(content, contains("import 'package:shop_app/main_dev.dart'"));
    expect(content, contains("import 'package:flutterware/run_guest.dart'"));
    // The wrapper forwards `args` when the app's main takes them — a
    // `void main(List<String> args)` entrypoint is legal and must not turn
    // the launch into a compile failure.
    expect(content, contains('void main(List<String> args)'));
    expect(content, contains('FutureOr<void> Function(List<String>)'));
    expect(content, contains('runGuest(() => entryMain(args))'));
  });

  test('regenerates in place on a second launch', () {
    writeGuestEntrypoint(packageRoot: root.path, entrypoint: 'lib/main.dart');
    var again = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'lib/main.dart',
    );
    expect(again.guest, isTrue);
  });

  test('wraps an entrypoint outside lib/, by path', () {
    // `demo/` is where a project that keeps dev-only entry points out of what
    // it ships puts them — the same `demo/` the previews plugin scans. This
    // used to launch uninstrumented, so those projects got no knobs, no
    // inspect and no act: the wrapper wanted a `package:` URI, which a file
    // outside `lib/` has none of. It does not need one. It sits inside the
    // package, so a path reaches the file, and a file with no `package:`
    // spelling cannot be reached under two URIs by anything else either.
    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'demo/main_desktop_dev.dart',
    );

    expect(result.guest, isTrue);
    expect(
      result.target,
      '.dart_tool/flutterware/run/main_desktop_dev_guest.dart',
    );
    var content = File(
      p.joinAll([root.path, ...p.posix.split(result.target)]),
    ).readAsStringSync();
    // Three levels out of `.dart_tool/flutterware/run/`, then back down.
    expect(
      content,
      contains("import '../../../demo/main_desktop_dev.dart' as entry;"),
    );
  });

  group('on web', () {
    test('an entrypoint outside lib/ launches unwrapped, with the way out', () {
      // The path spelling is a fact about a disk the browser's compiler does
      // not share: it roots the world at the wrapper's own directory, so the
      // `../../../` that reaches `demo/` on every other platform climbs out of
      // it. This used to be written anyway and fail the *compile*, reporting a
      // missing file and an undefined `main` in generated source nobody wrote.
      var result = writeGuestEntrypoint(
        packageRoot: root.path,
        entrypoint: 'demo/main_dev.dart',
        targetsWeb: true,
      );

      expect(result.guest, isFalse);
      expect(result.target, 'demo/main_dev.dart');
      expect(result.reason, contains('outside lib/'));
      expect(
        result.reason,
        contains('Move it under lib/'),
        reason: 'a refusal with no way out is a dead end',
      );
    });

    test('a lib/ entrypoint is wrapped as it always was', () {
      // No file-system root is added for a target that has a `package:` URI, so
      // there is nothing to climb out of and nothing to refuse.
      var result = writeGuestEntrypoint(
        packageRoot: root.path,
        entrypoint: 'lib/main_dev.dart',
        targetsWeb: true,
      );

      expect(result.guest, isTrue);
      var content = File(
        p.joinAll([root.path, ...p.posix.split(result.target)]),
      ).readAsStringSync();
      expect(content, contains("import 'package:shop_app/main_dev.dart'"));
    });

    test('outside the package is reported as that, not as web', () {
      // Both are true of this entrypoint; only one of them is the reason. A
      // refusal naming the browser for a file that no platform can reach sends
      // the reader to change the device.
      var result = writeGuestEntrypoint(
        packageRoot: root.path,
        entrypoint: '../other_app/lib/main.dart',
        targetsWeb: true,
      );

      expect(result.guest, isFalse);
      expect(result.reason, contains('outside'));
      expect(result.reason, isNot(contains('web build')));
    });
  });

  test('an entrypoint outside the package launches unwrapped', () {
    // The wrapper is written inside the package. A target above it can be
    // spelled as a path, and must not be: a file in a sibling package is
    // reached by `package:` URI from everywhere else in the checkout, and one
    // library under two URIs is two libraries.
    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: '../other_app/lib/main.dart',
    );

    expect(result.guest, isFalse);
    expect(result.target, '../other_app/lib/main.dart');
    expect(result.reason, contains('outside'));
  });

  test('a missing package name launches unwrapped, with the reason', () {
    File(p.join(root.path, 'pubspec.yaml')).deleteSync();

    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'lib/main.dart',
    );

    expect(result.guest, isFalse);
    expect(result.target, 'lib/main.dart');
    expect(result.reason, contains('package name'));
  });

  group('knobs the wrapper passes', () {
    /// Writes an entry point and returns the wrapper generated for it.
    String wrapperFor(String main, Map<String, Object?> knobs) {
      File(p.join(root.path, 'lib', 'main.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(main);
      var result = writeGuestEntrypoint(
        packageRoot: root.path,
        entrypoint: 'lib/main.dart',
        knobs: knobs,
      );
      return File(
        p.joinAll([root.path, ...p.posix.split(result.target)]),
      ).readAsStringSync();
    }

    void writeLib(String relative, String content) =>
        File(p.join(root.path, 'lib', relative))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);

    test('writes each value as a named argument', () {
      var content = wrapperFor(
        'void main({String host = "h", int port = 1, bool loud = false}) {}',
        {'host': '192.168.1.24', 'port': 8186, 'loud': true},
      );

      expect(content, contains('entry.main('));
      expect(content, contains("host: r'192.168.1.24',"));
      expect(content, contains('port: 8186,'));
      expect(content, contains('loud: true,'));
      // Named arguments make the runtime shape check moot — the compiler is
      // checking this call now.
      expect(content, isNot(contains('entryMain')));
    });

    test('copies the entry point imports so a value can name a type', () {
      // Without this the wrapper says `Undefined name: Backend`, which is what
      // every app keeping its enums in a config file would have hit.
      writeLib('src/backend.dart', 'enum Backend { dev, staging }');

      var content = wrapperFor(
        "import 'src/backend.dart';\n"
        'void main({Backend backend = Backend.dev}) {}',
        {'backend': 'staging'},
      );

      // Rewritten to a package: URI: the wrapper does not sit where the entry
      // point sits.
      expect(content, contains("import 'package:shop_app/src/backend.dart';"));
      expect(content, contains('backend: Backend.staging,'));
    });

    test("rewrites a demo/ entry point's imports from the wrapper", () {
      // The two halves of one wrapper: the entry point named by path because
      // it is outside `lib/`, an enum beside it named by path for the same
      // reason, and a shared enum in `lib/` named by its `package:` URI. One
      // function spells all three, so they cannot disagree.
      File(p.join(root.path, 'demo', 'src', 'seed.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('enum Seed { empty, full }');
      writeLib('src/backend.dart', 'enum Backend { dev, staging }');
      File(p.join(root.path, 'demo', 'main_dev.dart')).writeAsStringSync(
        "import 'src/seed.dart';\n"
        "import '../lib/src/backend.dart';\n"
        'void main({Seed seed = Seed.empty, Backend backend = Backend.dev}) {}',
      );

      var result = writeGuestEntrypoint(
        packageRoot: root.path,
        entrypoint: 'demo/main_dev.dart',
        knobs: {'seed': 'full', 'backend': 'staging'},
      );
      var content = File(
        p.joinAll([root.path, ...p.posix.split(result.target)]),
      ).readAsStringSync();

      expect(content, contains("import '../../../demo/src/seed.dart';"));
      expect(content, contains("import 'package:shop_app/src/backend.dart';"));
      expect(content, contains('seed: Seed.full,'));
      expect(content, contains('backend: Backend.staging,'));
    });

    test('writes a picker back through the type as it was written', () {
      writeLib('models.dart', 'enum Backend { dev, prod }');

      var content = wrapperFor(
        "import 'models.dart' as m;\n"
        'void main({m.Backend backend = m.Backend.dev}) {}',
        {'backend': 'prod'},
      );

      expect(content, contains("import 'package:shop_app/models.dart' as m;"));
      expect(content, contains('backend: m.Backend.prod,'));
    });

    test('the guest is imported under a prefix, so nothing can collide', () {
      var content = wrapperFor('void main({int port = 1}) {}', {'port': 2});

      expect(
        content,
        contains("import 'package:flutterware/run_guest.dart' as guest;"),
      );
      expect(content, contains('guest.runGuest('));
    });

    test('a value for a parameter that is not there is dropped', () {
      // A wish outliving the parameter it was for is ordinary — somebody
      // renamed it. Writing it would fail the build; dropping it leaves a knob
      // that does nothing, which the form reports separately.
      var content = wrapperFor('void main({int port = 1}) {}', {
        'port': 2,
        'gone': 'x',
      });

      expect(content, contains('port: 2,'));
      expect(content, isNot(contains('gone')));
    });

    test('an entry point taking nothing keeps the untouched wrapper', () {
      var content = wrapperFor('void main() {}', {'port': 2});

      expect(content, isNot(contains('entry.main(')));
      expect(content, contains('entryMain'));
    });

    test('a value is written for the type the signature declares', () {
      // Found by an end-to-end launch, not by these tests: every value from the
      // CLI or MCP is a String, so writing the literal from the *value's* type
      // handed an `int` parameter `r'8186'` and the build died on
      // "String can't be assigned to int".
      var content = wrapperFor(
        'void main({int port = 1, double ratio = 1.0, bool loud = false}) {}',
        {'port': '8186', 'ratio': '1.5', 'loud': 'true'},
      );

      expect(content, contains('port: 8186,'));
      expect(content, contains('ratio: 1.5,'));
      expect(content, contains('loud: true,'));
      expect(content, isNot(contains("r'8186'")));
    });

    test('a value that does not fit its kind throws rather than vanishing', () {
      // Both launch paths and setKnobs refuse these first; this is the second
      // line. It used to drop the argument, and dropping was the quiet version
      // of the same mistake: with nothing left to write the wrapper came out in
      // its no-knobs shape, so the app ran on `1` while the run's handle
      // reported `eight` — the cockpit showing a value the app was not using.
      expect(
        () => wrapperFor('void main({int port = 1}) {}', {'port': 'eight'}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            allOf(contains('port'), contains('integer'), contains('eight')),
          ),
        ),
      );
    });

    test('a string needing escapes stops being raw', () {
      var content = wrapperFor("void main({String label = 'x'}) {}", {
        'label': "it's",
      });

      expect(content, isNot(contains("r'it's")));
      expect(content, contains(r"label: 'it\'s',"));
    });

    test('a line break is escaped rather than closing the literal', () {
      // A single-quoted literal cannot span lines whether it is raw or not, so
      // this used to end the string mid-value and leave the wrapper
      // unparseable — a syntax error in generated source, about a value typed
      // somewhere else entirely. A JSON "\n" over MCP is one character.
      var content = wrapperFor("void main({String banner = 'x'}) {}", {
        'banner': 'first\nsecond',
      });

      expect(content, contains(r"banner: 'first\nsecond',"));
      // Every line of the wrapper is still a line of the wrapper.
      expect(
        content.split('\n').where((l) => l.contains('banner:')),
        hasLength(1),
      );
    });

    test('a picker value the enum does not declare throws', () {
      // `Backend.whatever` is a perfectly writable literal that does not
      // compile. A script source can compute one, so the type alone is not
      // enough — the constants are the check.
      writeLib('src/backend.dart', 'enum Backend { dev, prod }');

      expect(
        () => wrapperFor(
          "import 'src/backend.dart';\n"
          'void main({Backend backend = Backend.dev}) {}',
          {'backend': 'whatever'},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            allOf(contains('backend'), contains('whatever')),
          ),
        ),
      );
    });
  });
}
