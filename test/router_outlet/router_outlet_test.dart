import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/router_outlet/path.dart';
import 'package:flutterware/src/router_outlet/router_outlet.dart';
import 'package:flutterware/src/router_outlet/router_root.dart';
import 'package:flutterware/src/router_outlet/url_source_fake.dart';

void main() {
  Widget app(UrlSourceFake source) {
    return RouterRoot(
      urlSource: source,
      child: RouterOutlet({
        'detail/:id': (c) => _RouteState(id: c['id']),
        '': (c) => const Text('home', textDirection: TextDirection.ltr),
      }),
    );
  }

  testWidgets('changing a path argument tears down the route state', (
    tester,
  ) async {
    var source = UrlSourceFake(initial: PagePath('/detail/1'));
    await tester.pumpWidget(app(source));
    expect(find.text('init:1 current:1'), findsOneWidget);

    source.go(PagePath('/detail/2'));
    await tester.pump();
    expect(find.text('init:2 current:2'), findsOneWidget);
  });

  testWidgets('changing only query parameters keeps the route state', (
    tester,
  ) async {
    var source = UrlSourceFake(initial: PagePath('/detail/1'));
    await tester.pumpWidget(app(source));
    expect(find.text('init:1 current:1'), findsOneWidget);

    source.go(PagePath('/detail/1?tab=2'));
    await tester.pump();
    expect(find.text('init:1 current:1'), findsOneWidget);
  });

  testWidgets('navigating to another route swaps the widget', (tester) async {
    var source = UrlSourceFake(initial: PagePath('/detail/1'));
    await tester.pumpWidget(app(source));

    source.go(PagePath.root);
    await tester.pump();
    expect(find.text('home'), findsOneWidget);

    source.go(PagePath('/detail/3'));
    await tester.pump();
    expect(find.text('init:3 current:3'), findsOneWidget);
  });
}

class _RouteState extends StatefulWidget {
  final String id;

  const _RouteState({required this.id});

  @override
  State<_RouteState> createState() => _RouteStateState();
}

class _RouteStateState extends State<_RouteState> {
  // Captured once: only survives navigation if the State is reused.
  late final String initialId = widget.id;

  @override
  Widget build(BuildContext context) {
    return Text(
      'init:$initialId current:${widget.id}',
      textDirection: TextDirection.ltr,
    );
  }
}
