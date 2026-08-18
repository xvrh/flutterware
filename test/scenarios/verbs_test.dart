import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/run_listener.dart';

/// The verbs beyond tap and enterText, and the target vocabulary behind them.
void main() {
  var captures = <ScenarioStepCapture>[];
  setUp(() {
    captures = [];
    scenarioRunListener = captures.add;
  });
  tearDown(() => scenarioRunListener = null);

  scenario('scrollTo walks a list until the item is on screen', (s) async {
    await s.pumpWidget(const _ListApp());
    expect(find.text('Item 40'), findsNothing);

    await s.scrollTo('Item 40', shot: Shot('Item 40'));

    expect(find.text('Item 40'), findsOneWidget);
    expect(captures.last.texts, contains('Item 40'));
  });

  scenario('scrollTo walks back up with a negative step', (s) async {
    await s.pumpWidget(const _ListApp());
    await s.scrollTo('Item 40');

    await s.scrollTo('Item 0', step: -200);

    expect(find.text('Item 0'), findsOneWidget);
  });

  scenario('scrollTo says so when the item never turns up', (s) async {
    await s.pumpWidget(const _ListApp());

    await expectLater(
      () => s.scrollTo('Item 500', maxScrolls: 3),
      throwsA(
        isA<ScenarioTargetError>().having(
          (e) => '$e',
          'message',
          allOf(
            contains('scrolled 3 times'),
            contains('"Item 500"'),
            contains('negative step'),
          ),
        ),
      ),
    );
  });

  scenario('scrollTo says so when nothing scrolls', (s) async {
    await s.pumpWidget(const _StaticApp());

    await expectLater(
      () => s.scrollTo('anywhere'),
      throwsA(
        isA<ScenarioTargetError>().having(
          (e) => '$e',
          'message',
          contains('nothing on screen scrolls'),
        ),
      ),
    );
  });

  scenario('drag dismisses, and longPress opens what a tap does not', (
    s,
  ) async {
    await s.pumpWidget(const _GestureApp());

    await s.longPress('Hold me');
    expect(find.text('held'), findsOneWidget);

    await s.drag('Swipe me', const Offset(-500, 0));
    expect(find.text('Swipe me'), findsNothing);
  });

  scenario('wait moves the clock a settle would not', (s) async {
    await s.pumpWidget(const _SplashApp());
    // The trap the verb exists for: the timer schedules no frames, so no
    // amount of settling reaches the second screen.
    expect(find.text('Splash'), findsOneWidget);

    await s.wait(const Duration(seconds: 3), shot: Shot('Home'));

    expect(find.text('Home'), findsOneWidget);
  });

  scenario('back pops the route the platform way', (s) async {
    await s.pumpWidget(const _RoutedApp());
    await s.tap('Open details');
    expect(find.text('Details'), findsOneWidget);

    await s.back(shot: Shot('Back on the list'));

    expect(find.text('Details'), findsNothing);
  });

  scenario('a semantics label is a target — the only handle on an icon', (
    s,
  ) async {
    await s.pumpWidget(const _LabelledApp());

    await s.tap(const Target.label('Add to cart'));

    expect(find.text('added'), findsOneWidget);
  });

  scenario('a tooltip is a target', (s) async {
    await s.pumpWidget(const _LabelledApp());

    await s.tap(const Target.tooltip('Remove'));

    expect(find.text('removed'), findsOneWidget);
  });

  scenario('within scopes a target, and nth picks one of many', (s) async {
    await s.pumpWidget(const _CardsApp());

    // A 'Buy' button on every card: ambiguous alone, exact once scoped.
    await expectLater(
      () => s.tap(const Target.containing('Buy')),
      throwsA(
        isA<ScenarioTargetError>().having(
          (e) => '$e',
          'message',
          // The target reads back as what was written, not as
          // `Instance of '_Containing'`.
          contains('2 widgets match Target.containing("Buy")'),
        ),
      ),
    );

    await s.tap(
      const Target.within(ValueKey('second'), Target.containing('Buy')),
    );
    expect(find.text('bought second'), findsOneWidget);

    await s.tap(const Target.nth(Target.containing('Buy'), 0));
    expect(find.text('bought first'), findsOneWidget);
  });

  scenario('containing matches part of a string', (s) async {
    await s.pumpWidget(const _CardsApp());

    await s.tap(const Target.containing('the second'));

    expect(find.text('bought second'), findsOneWidget);
  });

  /// **Reported by a consumer driving a form.** A point is the target for a
  /// control with no words, a field labelled from its decoration is one, and
  /// `enterText` at a point resolves *below* the editable — so the search the
  /// verb makes downwards found nothing to type into.
  scenario('a point inside a field types into it', (s) async {
    await s.pumpWidget(const _FormApp());
    var box = s.tester.getRect(find.byType(TextField));

    await s.enterText(Target.at(box.center.dx, box.center.dy), '918406');

    expect(find.text('918406'), findsOneWidget);
  });

  scenario('frames the verbs did not draw are counted onto the next step', (
    s,
  ) async {
    await s.pumpWidget(const _CardsApp());
    expect(captures.last.strayFrames, 0);

    // The escape hatch, used for something a verb covers: the app changes,
    // and the flow has no picture of it.
    await s.tester.tap(find.text('Buy the first'));
    await s.tester.pump();

    await s.screen('after a raw tap');
    expect(captures.last.strayFrames, greaterThan(0));
  });
}

class _StaticApp extends StatelessWidget {
  const _StaticApp();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: Text('nothing to scroll')));
}

class _ListApp extends StatelessWidget {
  const _ListApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          for (var i = 0; i < 60; i++)
            SizedBox(height: 80, child: Text('Item $i')),
        ],
      ),
    ),
  );
}

class _GestureApp extends StatefulWidget {
  const _GestureApp();

  @override
  State<_GestureApp> createState() => _GestureAppState();
}

class _GestureAppState extends State<_GestureApp> {
  var _note = '';
  var _swiped = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          GestureDetector(
            onLongPress: () => setState(() => _note = 'held'),
            child: const Text('Hold me'),
          ),
          if (!_swiped)
            Dismissible(
              key: const ValueKey('dismissible'),
              onDismissed: (_) => setState(() => _swiped = true),
              child: const SizedBox(height: 60, child: Text('Swipe me')),
            ),
          Text(_note),
        ],
      ),
    ),
  );
}

/// A splash that navigates on a timer — no animation, so nothing to settle.
class _SplashApp extends StatefulWidget {
  const _SplashApp();

  @override
  State<_SplashApp> createState() => _SplashAppState();
}

class _SplashAppState extends State<_SplashApp> {
  var _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(
      const Duration(seconds: 2),
      () => setState(() => _done = true),
    );
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: Text(_done ? 'Home' : 'Splash')));
}

class _RoutedApp extends StatelessWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Details')),
            ),
          ),
          child: const Text('Open details'),
        ),
      ),
    ),
  );
}

class _LabelledApp extends StatefulWidget {
  const _LabelledApp();

  @override
  State<_LabelledApp> createState() => _LabelledAppState();
}

class _LabelledAppState extends State<_LabelledApp> {
  var _note = '';

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          // An icon button with no text and no tooltip: the semantics label
          // is the only handle on it, which is what `Target.label` is for.
          // (A `tooltip:` would not do — Material puts that on the semantics
          // node's *tooltip*, not its label.)
          Semantics(
            label: 'Add to cart',
            child: IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              onPressed: () => setState(() => _note = 'added'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Remove',
            onPressed: () => setState(() => _note = 'removed'),
          ),
          Text(_note),
        ],
      ),
    ),
  );
}

class _FormApp extends StatelessWidget {
  const _FormApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: TextField(decoration: InputDecoration(labelText: 'Phone number')),
    ),
  );
}

class _CardsApp extends StatefulWidget {
  const _CardsApp();

  @override
  State<_CardsApp> createState() => _CardsAppState();
}

class _CardsAppState extends State<_CardsApp> {
  var _note = '';

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          for (var name in ['first', 'second'])
            Card(
              key: ValueKey(name),
              child: Column(
                children: [
                  Text('The $name card'),
                  TextButton(
                    onPressed: () => setState(() => _note = 'bought $name'),
                    child: Text('Buy the $name'),
                  ),
                ],
              ),
            ),
          Text(_note),
        ],
      ),
    ),
  );
}
