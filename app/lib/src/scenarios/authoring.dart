/// How to write a scenario, in one string.
///
/// The panel's empty state used to be the only place this was said, which made
/// it the one thing about the feature an agent could not find: `list` and
/// `actions` describe how to *run* scenarios, and nothing described how to
/// write one. So it lives here and three surfaces render it — the empty scan
/// in `list`, the empty panel, and the header of the file `new` scaffolds.
///
/// [directory] is the package's configured scenario directory, because "where
/// does the file go" is the half of the answer that is per-project.
String scenarioAuthoringHint(String directory) =>
    '''
A scenario is an ordinary widget test with a screenshot per step — `flutter
test $directory` runs it with no daemon and no GUI.

  // $directory/shop_test.dart
  import 'package:flutterware/flutter_test.dart';

  void main() {
    scenario('Around the shop', (s) async {
      await s.pumpWidget(const ShopApp());
      await s.tap('Get started', shot: Shot('Menu'));
      await s.enterText('Search', 'flat white');
      await s.screen('Results');
      expect(find.text('Flat white'), findsOneWidget);
    });
  }

The import is `package:flutterware/flutter_test.dart` — a strict superset of
`package:flutter_test`, so an existing test compiles with only its import
changed.

- `s.tap` / `s.enterText` take a String (visible text), a Key, an IconData, a
  Type or a Finder. Each settles, then captures.
- `Shot('Name')` names a capture; `Shot.skip` suppresses one; `s.screen(name)`
  captures without acting.
- `scenario(..., shots: Shots.manual)` captures only where a Shot asks.
- `s.split({'pays': () async {…}, 'declines': () async {…}})` forks: every
  branch runs, the shared prefix is captured once.
- `s.tester` is the real WidgetTester — the whole flutter_test surface, no
  capture.

`fw run scenarios new --file=$directory/shop_test.dart --name="Around the shop"`
writes a runnable one to edit — as does the panel's New scenario button.''';

/// `Around the shop` → `around_the_shop_test.dart`.
///
/// Where `new` writes when the caller names no file. Public because the GUI's
/// dialog previews the path while you type: the action never overwrites, so
/// which file a name lands in is half of what pressing Create does.
String scenarioFileName(String name) {
  var slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '${slug.isEmpty ? 'scenario' : slug}_test.dart';
}

/// The file `new` writes: a stub app and a scenario that drives it.
///
/// It runs green as written, on purpose. `scenarios_new_test.dart` scaffolds
/// one and runs it, so the day `tap` or `Shot` changes shape this template
/// fails its own test instead of quietly teaching an API that no longer
/// exists — which is the failure mode a doc has and a scaffold does not.
String scenarioScaffold(String name) =>
    '''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

/// Replace `_Stub` with the app you want to walk through; the scenario below
/// is the shape. Every action screenshots itself — `Shot('Name')` names one,
/// `Shot.skip` drops one, `s.screen('Name')` captures without acting.
void main() {
  scenario('${_escape(name)}', (s) async {
    await s.pumpWidget(const _Stub());
    await s.tap('Continue', shot: Shot('Tapped continue'));
    expect(find.text('Tapped'), findsOneWidget);
  });
}

class _Stub extends StatefulWidget {
  const _Stub();

  @override
  State<_Stub> createState() => _StubState();
}

class _StubState extends State<_Stub> {
  var _tapped = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _tapped
              ? const Text('Tapped')
              : TextButton(
                  onPressed: () => setState(() => _tapped = true),
                  child: const Text('Continue'),
                ),
        ),
      ),
    );
  }
}
''';

/// A name arrives from a command line and lands inside a single-quoted Dart
/// literal, so an apostrophe in it would write a file that does not parse.
String _escape(String name) =>
    name.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');
