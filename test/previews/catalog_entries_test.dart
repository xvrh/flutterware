import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/previews_guest.dart';

void main() {
  var entries = CatalogEntries.instance;

  /// Mounts the switch the way the generated entrypoint does, and renders the
  /// id it resolves so a test can read it off the screen.
  Future<void> pump(WidgetTester tester, String fromFile) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: entries.build(
        fromFile: fromFile,
        builder: (context, entryId) => Text(entryId),
      ),
    ),
  );

  setUp(() => entries.install(() => const ['a', 'b', 'c']));

  testWidgets('builds what the file names', (tester) async {
    await pump(tester, 'a');
    expect(find.text('a'), findsOneWidget);
    expect(entries.showing, 'a');
  });

  testWidgets('a switch is a rebuild, with no reload involved', (tester) async {
    await pump(tester, 'a');

    expect(entries.show('b'), 'b');
    await tester.pump();

    expect(find.text('b'), findsOneWidget);
    expect(entries.showing, 'b');
  });

  testWidgets('an id the program does not hold is refused', (tester) async {
    // Answered rather than thrown, and answered with the truth: the host reads
    // the mismatch and recovers with the compile and reload it would otherwise
    // have done.
    await pump(tester, 'a');

    expect(entries.show('nope'), 'a');
    await tester.pump();

    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('a reload naming another entry outranks a switch', (
    tester,
  ) async {
    // How the panel switches demos: regenerate the entrypoint, recompile,
    // reload. Nothing sends `showEntry`, so the file has to win — otherwise
    // the panel would sit on whatever an agent last asked for.
    await pump(tester, 'a');
    entries.show('b');
    await tester.pump();
    expect(find.text('b'), findsOneWidget);

    await pump(tester, 'c');

    expect(find.text('c'), findsOneWidget);
    expect(entries.showing, 'c');
  });

  testWidgets('a reload that changes nothing leaves the switch alone', (
    tester,
  ) async {
    // An ordinary source edit reloads with the same entry named. Rebasing on
    // that would yank the screen back to the file's entry every time someone
    // saved a file.
    await pump(tester, 'a');
    entries.show('b');
    await tester.pump();

    await pump(tester, 'a');

    expect(find.text('b'), findsOneWidget);
    expect(entries.showing, 'b');
  });

  testWidgets('nothing mounted is answered, not thrown', (tester) async {
    await pump(tester, 'a');
    await tester.pumpWidget(const SizedBox());

    expect(entries.show('b'), isNull);
    expect(entries.showing, isNull);
  });
}
