/// What to say to somebody who has no previews yet.
///
/// One string, in one place, reached by four surfaces: the `entries` result an
/// agent reads, the panel's empty state, the sidebar's status, and the daemon's
/// refusal. They used to say nothing, three different ways, and the fourth said
/// it thirty seconds late under a stack trace.
library;

/// Where previews live when a package does not say otherwise.
///
/// Duplicated nowhere: the plugin's own default reads this, and so does every
/// message that names it — a convention that is spelled twice is a convention
/// that eventually disagrees with itself.
const defaultCatalogDirectory = 'demo';

/// The annotations that mark an entry when a package registers none of its own.
///
/// Flutter's `@Preview`, and nothing of ours — one declaration serves both this
/// catalog and Flutter's own previewer because it *is* their declaration. A
/// project wanting fields the annotation does not carry declares its own
/// subclass and registers it here; the scan reads arguments by name, so
/// whatever it calls itself, an `id:` on it is still an `id:`.
const defaultPreviewAnnotations = ['Preview'];

/// How to write the first preview in [directory].
///
/// The directory is interpolated rather than assumed, so a project that moved
/// it is told about *its* directory and not about `demo/`.
String catalogAuthoringHint(String directory) =>
    '''
A preview is an ordinary function returning a Widget, annotated with Flutter's
own `@Preview`. Nothing of flutterware's is imported, and there is no map to
register it in — every `.dart` file under `$directory/` is scanned.

  // $directory/buttons.dart
  import 'package:flutter/material.dart';
  import 'package:flutter/widget_previews.dart';

  @Preview(name: 'Buttons')
  Widget buttons() => const Column(
        children: [
          ElevatedButton(onPressed: null, child: Text('Elevated')),
          OutlinedButton(onPressed: null, child: Text('Outlined')),
        ],
      );

- The target must be callable with no arguments — a top-level function, a static
  method, or a constructor.
- `@Preview(group: 'Forms')` groups it; a file holding more than one entry
  derives a group from its own name.
- Two `@Preview`s on one declaration are two entries, which is how variants are
  spelled.
- `context.previews.parameters.string('label', 'Hello')` inside the preview
  declares a knob you can turn from the panel, the CLI and an agent. That one
  needs `package:flutterware/previews.dart`; nothing above it does.

`fw run previews new --name='Buttons'` writes that file for you.''';

/// The file `new` writes for a preview called [name].
String catalogFileName(String name) {
  var slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '${slug.isEmpty ? 'preview' : slug}.dart';
}

/// Dart's reserved words, which cannot be an identifier at all.
///
/// Only the truly reserved ones. Built-in identifiers — `get`, `set`, `late`,
/// `required` and the rest — are legal names for a function, so renaming those
/// would be officious. `await` and `yield` are in for safety: they are reserved
/// only inside async and generator bodies, but a preview named either of them is
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
/// name. Two things a preview's name can do that an identifier cannot: start with
/// a digit (`404 page`), and be a reserved word — and `Switch` is close to the
/// most likely name in a catalog of previews, so this is not a corner. Both are answered
/// the same way, by prefixing `preview`, which reads as a name somebody might have
/// chosen rather than as an escape.
String catalogSymbolName(String name) {
  var words = catalogFileName(
    name,
  ).replaceAll('.dart', '').split('_').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return 'preview';
  var symbol = [
    words.first,
    for (var word in words.skip(1)) word[0].toUpperCase() + word.substring(1),
  ].join();
  if (!_dartReservedWords.contains(symbol) &&
      !RegExp(r'^[0-9]').hasMatch(symbol)) {
    return symbol;
  }
  return 'preview${symbol[0].toUpperCase()}${symbol.substring(1)}';
}

/// The file `new` writes: one entry that renders as written, and a second,
/// commented out, showing the knob API.
///
/// It renders green on purpose. Somebody who has never written a preview gets
/// the API in a file that already works, rather than a template to debug.
String catalogScaffold(String name) {
  var symbol = catalogSymbolName(name);
  return '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: '$name')
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

// A knob is whatever the preview asks for while it builds — no registration,
// and the panel, the CLI and an agent all get the same control. This one needs
// `package:flutterware/previews.dart` for `context.previews`:
//
// @Preview(name: '$name, parameterised')
// Widget ${symbol}Knobs(BuildContext context) {
//   var label = context.previews.parameters.string('label', 'A button');
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
  if (directoryExists) return 'No previews in $where yet.';

  // What to say next depends on whether anybody chose this directory. Telling
  // someone who wrote `directory: 'examples'` to try `directory: 'demo'` reads
  // as the tool not having noticed what they set — which was the whole
  // complaint that started this.
  return directory == defaultCatalogDirectory
      ? 'No previews: $where does not exist.\n'
            'Previews live in `$defaultCatalogDirectory/` by default. Create it, '
            'or point Previews at wherever yours are with '
            "`Previews(packages: [.new(app, directory: 'lib/demos')])` in "
            'tool/flutterware.dart.'
      : 'No previews: $where does not exist.\n'
            "tool/flutterware.dart declares `directory: '$directory'` for this "
            'package, so that is the only place scanned. Either the path is '
            'wrong, or the previews are somewhere else.';
}
