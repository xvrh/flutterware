import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A core that starts a tester has to end it, or `fw` never exits.
///
/// The CLI returns from `main` and waits for its event loop to drain, and a
/// live `frontend_server`, `flutter_tester` and the service socket to it are
/// three things that never drain. `fw run scene video` shipped that way: it
/// printed its clip and then sat at 0% CPU forever, because `SceneCore` kept a
/// runner per package and had no `dispose` to end them — where `PreviewsCore`,
/// `ScenariosCore` and `StoreCore`, holding the same runners, each did.
///
/// Structural, like `material_drift_test.dart`: the behaviour it protects is a
/// process that does not exit, which a test can only observe by compiling a
/// tester and waiting for nothing to happen.
void main() {
  var root = Directory.current.path;
  var sources = p.join(root, 'lib', 'src');
  var cores = p.join(sources, 'plugins');

  /// Every class that owns a `TesterHost`, and so the processes behind it.
  const owners = {'PreviewTestRunner', 'ScenarioRunner', 'StoreFrameRunner'};

  List<File> dartFiles(String directory) =>
      Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  /// The file with full-line comments removed, so a doc comment may name a
  /// runner without being read as constructing one.
  String code(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the directories this guards are actually there', () {
    expect(
      Directory(cores).existsSync(),
      isTrue,
      reason: 'lib/src/plugins is missing — run this from app/',
    );
  });

  test('every TesterHost is held by a class this test knows', () {
    var construct = RegExp(r'\bTesterHost\(');
    var declares = RegExp(r'^\s*(?:final\s+)?class\s+(\w+)', multiLine: true);
    var unknown = [
      for (var file in dartFiles(sources))
        if (p.basename(file.path) != 'tester_host.dart')
          if (code(file) case var source when construct.hasMatch(source))
            if (!declares
                .allMatches(source)
                .any((m) => owners.contains(m.group(1))))
              p.relative(file.path, from: root),
    ];
    expect(
      unknown,
      isEmpty,
      reason:
          'these construct a TesterHost in a class the list above does not '
          'name — add it to `owners`, so a core holding one is checked too',
    );
  });

  test('a core that starts a tester ends it in dispose', () {
    var construct = RegExp(r'\b(' + owners.join('|') + r')\(');
    var offenders = <String>[];
    for (var file in dartFiles(cores)) {
      var source = code(file);
      var core = _block(source, RegExp(r'extends PluginCore\b[^{]*\{'));
      if (core == null) continue;
      var built = construct.firstMatch(core)?.group(1);
      if (built == null) continue;
      var body = _block(core, RegExp(r'void dispose\(\)\s*\{'));
      if (body == null || !body.contains('.dispose()')) {
        offenders.add(
          '${p.relative(file.path, from: root)}: builds a $built and '
          '${body == null ? 'has no dispose()' : 'its dispose() ends none'}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'override dispose() and call dispose() on every runner the core '
          'holds, as PreviewsCore does — otherwise `fw run` prints its answer '
          'and never exits',
    );
  });
}

/// What sits between the brace [opening] ends on and the one that closes it,
/// or null when [opening] is not in [source].
///
/// Counts braces and nothing else, so a `{` inside a string literal throws it
/// off — which the files it reads do not have in the places it reads.
String? _block(String source, RegExp opening) {
  var start = opening.firstMatch(source);
  if (start == null) return null;
  var depth = 1;
  for (var i = start.end; i < source.length; i++) {
    switch (source[i]) {
      case '{':
        depth++;
      case '}':
        if (--depth == 0) return source.substring(start.end, i);
    }
  }
  return source.substring(start.end);
}
