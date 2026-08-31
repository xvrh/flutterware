import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/comparison/web_viewer.dart';

/// The fragment is the contract between three writers — the PR comment's
/// links, the viewer's own address writes, and a hand-edited URL — and one
/// reader. What these pin is that all three spellings decode to the same
/// place.
void main() {
  test('a tab alone, a selection, and everything after the first slash', () {
    expect(parseViewerFragment('previews'), ('previews', null));
    expect(parseViewerFragment('scenarios'), ('scenarios', null));
    expect(parseViewerFragment('previews/demo/card.dart#card'), (
      'previews',
      'demo/card.dart#card',
    ));
    expect(
      parseViewerFragment('scenarios/test/shop.dart#Checkout/guest › Pay'),
      ('scenarios', 'test/shop.dart#Checkout/guest › Pay'),
    );
  });

  test('anything that does not start with a tab is not an address', () {
    expect(parseViewerFragment(''), isNull);
    expect(parseViewerFragment('files'), isNull);
    expect(parseViewerFragment('demo/card.dart'), isNull);
  });

  test('the viewer’s own writes round-trip through the URL', () {
    // What `writeUrlFragment` puts in the address bar…
    var written = Uri(fragment: 'previews/demo/card.dart#card').toString();
    // …reads back through `Uri.fragment`'s decoding to the same place.
    expect(
      parseViewerFragment(Uri.parse('http://host/page$written').fragment),
      ('previews', 'demo/card.dart#card'),
    );
  });

  test('the PR comment’s spelling decodes to the same place', () {
    // The comment escapes every segment fully (`/` included) — a different
    // spelling of the same address, because only the first slash structures.
    var fragment = Uri.parse(
      'http://host/page#scenarios/test%2Fshop.dart%23Checkout/'
      'guest%20%E2%80%BA%20Pay',
    ).fragment;
    expect(parseViewerFragment(fragment), (
      'scenarios',
      'test/shop.dart#Checkout/guest › Pay',
    ));
  });
}
