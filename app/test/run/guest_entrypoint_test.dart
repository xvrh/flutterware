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

  test('an entrypoint outside lib/ launches unwrapped, with the reason', () {
    var result = writeGuestEntrypoint(
      packageRoot: root.path,
      entrypoint: 'tool/spike.dart',
    );

    expect(result.guest, isFalse);
    expect(result.target, 'tool/spike.dart');
    expect(result.reason, contains('not under lib/'));
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

    test('a value that does not fit its kind is not written', () {
      // The action refuses these first; this is the second line, so a bad value
      // can never reach the compiler as generated source.
      var content = wrapperFor('void main({int port = 1}) {}', {
        'port': 'eight',
      });

      expect(content, isNot(contains('port:')));
    });

    test('a string needing escapes stops being raw', () {
      var content = wrapperFor("void main({String label = 'x'}) {}", {
        'label': "it's",
      });

      expect(content, isNot(contains("r'it's")));
      expect(content, contains(r"label: 'it\'s',"));
    });
  });
}
