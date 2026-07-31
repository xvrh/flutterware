import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/inspect/guest_scrolls.dart';
import 'package:flutterware/src/ui_catalog/guest.dart';

/// The one thing this half has to get right: **a scroll counts and nothing else
/// does**. The watch tier above it is tested against a stubbed counter, so this
/// is where a real scrollable gets dragged.
void main() {
  group('GuestScrolls', () {
    testWidgets('a drag counts, and standing still does not', (tester) async {
      var scrolls = GuestScrolls.instance;
      await tester.pumpWidget(_demo(const _List()));

      var before = scrolls.ticks;
      await tester.pump();
      expect(scrolls.ticks, before, reason: 'a frame is not a scroll');

      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(scrolls.ticks, greaterThan(before));
    });

    testWidgets('a rebuild that scrolls nothing is silent', (tester) async {
      var scrolls = GuestScrolls.instance;
      await tester.pumpWidget(_demo(const Text('one')));
      var before = scrolls.ticks;

      // The overwhelmingly common case, and the reason this is a notification
      // listener rather than anything that walks the tree: a demo that rebuilds
      // sixty times a second while scrolling nothing must cost nothing.
      await tester.pumpWidget(_demo(const Text('two')));

      expect(scrolls.ticks, before);
    });

    testWidgets('the notification carries on past it', (tester) async {
      var seen = 0;
      await tester.pumpWidget(
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            seen++;
            return false;
          },
          // A shell standing above the demo — a Scrollbar is the real one —
          // still hears what the demo scrolls. Consuming the notification here
          // would be a bug findable only in somebody else's widget.
          child: _demo(const _List()),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(seen, greaterThan(0));
    });

    testWidgets('and the catalog puts every demo under it', (tester) async {
      var scrolls = GuestScrolls.instance;
      // The wiring, not the counter: a tier the guest never installs reports
      // nothing at all, and nothing is exactly what the bug looked like.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: CatalogGuest(entryId: 'demo.dart#one', child: _List()),
        ),
      );
      var before = scrolls.ticks;

      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(scrolls.ticks, greaterThan(before));
    });
  });
}

Widget _demo(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: GuestScrolls.instance.watching(child: child),
);

class _List extends StatelessWidget {
  const _List();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 100,
      itemExtent: 40,
      itemBuilder: (context, index) => Text('row $index'),
    );
  }
}
