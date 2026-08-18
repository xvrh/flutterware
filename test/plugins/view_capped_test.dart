import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

/// Capping a projection for a reader that pays by the row.
///
/// The rule being checked is the one [ViewItems.truncated] was written for:
/// *never silently drop rows*. A status reply that looked complete while
/// holding a tenth of a catalog would be worse than the long one it replaced,
/// so every test here is really about the count that comes with the cut.
void main() {
  ViewItems items(int count) =>
      ViewItems([for (var i = 0; i < count; i++) ViewItem('item $i')]);

  test('a short list is returned untouched', () {
    var view = PluginView([items(3)]);
    expect(view.capped(10).toJson(), view.toJson());
  });

  test('a long list keeps the head and counts the tail', () {
    var capped = PluginView([items(28)]).capped(10).toJson().single;

    expect((capped['items']! as List).length, 10);
    expect(capped['truncated'], 18);
    expect(((capped['items']! as List).last as Map)['label'], 'item 9');
  });

  test('a cut adds to a count the plugin already made', () {
    // A plugin that already showed a projection of its own state says so; the
    // reply has to name everything missing, not only what this cut removed.
    var view = PluginView([
      ViewItems([
        for (var i = 0; i < 12; i++) ViewItem('item $i'),
      ], truncated: 40),
    ]);

    expect(view.capped(10).toJson().single['truncated'], 42);
  });

  test('table rows cap the same way, columns survive', () {
    var table = ViewTable(
      ['name', 'size'],
      [
        for (var i = 0; i < 15; i++) ['row $i', '$i kB'],
      ],
    );

    var capped = PluginView([table]).capped(4).toJson().single;
    expect(capped['columns'], ['name', 'size']);
    expect((capped['rows']! as List).length, 4);
    expect(capped['truncated'], 11);
  });

  test('sections cap what they hold, at any depth', () {
    var view = PluginView([
      ViewSection('outer', [
        ViewField('Direct', '18'),
        ViewSection('inner', [items(20)]),
      ]),
    ]);

    var outer = view.capped(5).toJson().single;
    var inner = (outer['children']! as List).last as Map;
    var list = (inner['children']! as List).single as Map;

    // The field is not a row and is not touched — a cap that ate the summary
    // would be cutting the one line worth keeping.
    expect(((outer['children']! as List).first as Map)['value'], '18');
    expect((list['items']! as List).length, 5);
    expect(list['truncated'], 15);
  });

  test('the text projection says how many it left out', () {
    expect(
      PluginView([items(12)]).capped(2).toText(),
      '- item 0\n- item 1\n… 10 more',
    );
  });
}
