/// What to say to somebody who has no demos yet.
///
/// One string, in one place, reached by four surfaces: the `entries` result an
/// agent reads, the panel's empty state, the sidebar's status, and the daemon's
/// refusal. They used to say nothing, three different ways, and the fourth said
/// it thirty seconds late under a stack trace.
library;

/// Where demos live when a package does not say otherwise.
///
/// Duplicated nowhere: the plugin's own default reads this, and so does every
/// message that names it — a convention that is spelled twice is a convention
/// that eventually disagrees with itself.
const defaultCatalogDirectory = 'demo';

/// The annotations that mark an entry when a package registers none of its own.
///
/// `Preview` is Flutter's; `Demo` extends it, so one declaration serves both
/// this catalog and Flutter's own previewer.
const defaultPreviewAnnotations = ['Preview', 'Demo'];

/// How to write the first demo in [directory].
///
/// The directory is interpolated rather than assumed, so a project that moved
/// it is told about *its* directory and not about `demo/`.
String catalogAuthoringHint(String directory) =>
    '''
A demo is an ordinary function returning a Widget, annotated. There is no map to
register it in — every `.dart` file under `$directory/` is scanned.

  // $directory/buttons.dart
  import 'package:flutter/material.dart';
  import 'package:flutterware/ui_catalog.dart';

  @Demo(name: 'Buttons')
  Widget buttons() => const Column(
        children: [
          ElevatedButton(onPressed: null, child: Text('Elevated')),
          OutlinedButton(onPressed: null, child: Text('Outlined')),
        ],
      );

- The target must be callable with no arguments — a top-level function, a static
  method, or a constructor.
- `@Demo(group: 'Forms')` groups it; a file holding more than one entry derives
  a group from its own name.
- Two `@Demo`s on one declaration are two entries, which is how variants are
  spelled.
- `context.uiCatalog.parameters.string('label', 'Hello')` inside the demo
  declares a knob you can turn from the panel, the CLI and an agent.

`fw run ui_catalog new --name='Buttons'` writes that file for you.''';

/// The file `new` writes for a demo called [name].
String catalogFileName(String name) {
  var slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '${slug.isEmpty ? 'demo' : slug}.dart';
}

/// Dart's reserved words, which cannot be an identifier at all.
///
/// Only the truly reserved ones. Built-in identifiers — `get`, `set`, `late`,
/// `required` and the rest — are legal names for a function, so renaming those
/// would be officious. `await` and `yield` are in for safety: they are reserved
/// only inside async and generator bodies, but a demo named either of them is
/// a coin flip nobody needs to win.
const _dartReservedWords = {
  'assert',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

/// The symbol inside it — the file's slug, lowerCamelCased.
///
/// **Must be a legal Dart identifier**, because the scaffold declares a
/// top-level function with this name and the generated entrypoint imports it by
/// name. Two things a demo's name can do that an identifier cannot: start with
/// a digit (`404 page`), and be a reserved word — and `Switch` is close to the
/// most likely name in a UI catalog, so this is not a corner. Both are answered
/// the same way, by prefixing `demo`, which reads as a name somebody might have
/// chosen rather than as an escape.
String catalogSymbolName(String name) {
  var words = catalogFileName(
    name,
  ).replaceAll('.dart', '').split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return 'demo';
  var symbol = [
    words.first,
    for (var word in words.skip(1)) word[0].toUpperCase() + word.substring(1),
  ].join();
  if (!_dartReservedWords.contains(symbol) &&
      !RegExp(r'^[0-9]').hasMatch(symbol)) {
    return symbol;
  }
  return 'demo${symbol[0].toUpperCase()}${symbol.substring(1)}';
}

/// The file `new` writes: one entry that renders as written, and a second,
/// commented out, showing the knob API.
///
/// It renders green on purpose. Somebody who has never written a demo gets the
/// API in a file that already works, rather than a template to debug.
String catalogScaffold(String name) {
  var symbol = catalogSymbolName(name);
  return '''
import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog.dart';

@Demo(name: '$name')
Widget $symbol() => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text('$name', style: const TextStyle(fontSize: 24)),
            const Text('Replace this with the widget you are building.'),
            FilledButton(onPressed: () {}, child: const Text('A button')),
          ],
        ),
      ),
    );

// A knob is whatever the demo asks for while it builds — no registration, and
// the panel, the CLI and an agent all get the same control:
//
// @Demo(name: '$name, parameterised')
// Widget ${symbol}Knobs(BuildContext context) {
//   var label = context.uiCatalog.parameters.string('label', 'A button');
//   return Center(child: FilledButton(onPressed: () {}, child: Text(label)));
// }
''';
}

/// Why there are no entries, and what to do about it — the sentence above the
/// hint.
///
/// [directory] is package-relative, as the config declares it; [package] names
/// the declared package when there is more than one, since "no entries in
/// demo/" is ambiguous in a monorepo.
String catalogEmptyReason({
  required String directory,
  required bool directoryExists,
  String? package,
}) {
  var where = package == null || package == '.'
      ? '$directory/'
      : '$package/$directory/';
  if (directoryExists) return 'No demos in $where yet.';

  // What to say next depends on whether anybody chose this directory. Telling
  // someone who wrote `directory: 'examples'` to try `directory: 'demo'` reads
  // as the tool not having noticed what they set — which was the whole
  // complaint that started this.
  return directory == defaultCatalogDirectory
      ? 'No demos: $where does not exist.\n'
            'Demos live in `$defaultCatalogDirectory/` by default. Create it, '
            'or point the catalog at wherever yours are with '
            "`UiCatalog(packages: [.new(app, directory: 'lib/demos')])` in "
            'tool/flutterware.dart.'
      : 'No demos: $where does not exist.\n'
            "tool/flutterware.dart declares `directory: '$directory'` for this "
            'package, so that is the only place scanned. Either the path is '
            'wrong, or the demos are somewhere else.';
}
