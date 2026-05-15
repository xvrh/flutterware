import 'package:flutterware_app/src/tui/render/render.dart';
import 'package:flutterware_app/src/tui/widgets/widgets.dart';
import 'package:test/test.dart';

import '_harness.dart';

List<RenderText> texts(TuiBinding binding) =>
    (binding.renderView.child! as RenderFlex)
        .children
        .cast<RenderText>()
        .toList();

void main() {
  test('keyed reorder reuses the same RenderText instances', () {
    var binding = pumpHosted(const Column(children: [
      Text('a', key: ValueKey('a')),
      Text('b', key: ValueKey('b')),
      Text('c', key: ValueKey('c')),
    ]));
    var before = {for (var t in texts(binding)) t.text: t};
    expect(before.keys.toList(), ['a', 'b', 'c']);

    rebuild(
        binding,
        const Column(children: [
          Text('c', key: ValueKey('c')),
          Text('a', key: ValueKey('a')),
          Text('b', key: ValueKey('b')),
        ]));

    var after = texts(binding);
    expect(after.map((t) => t.text).toList(), ['c', 'a', 'b']);
    // Identity preserved: keyed children moved, not rebuilt.
    expect(identical(after[0], before['c']), isTrue);
    expect(identical(after[1], before['a']), isTrue);
    expect(identical(after[2], before['b']), isTrue);
  });

  test('mid-list insert keeps the surrounding keyed children', () {
    var binding = pumpHosted(const Column(children: [
      Text('a', key: ValueKey('a')),
      Text('c', key: ValueKey('c')),
    ]));
    var before = {for (var t in texts(binding)) t.text: t};

    rebuild(
        binding,
        const Column(children: [
          Text('a', key: ValueKey('a')),
          Text('b', key: ValueKey('b')),
          Text('c', key: ValueKey('c')),
        ]));

    var after = texts(binding);
    expect(after.map((t) => t.text).toList(), ['a', 'b', 'c']);
    expect(identical(after[0], before['a']), isTrue);
    expect(identical(after[2], before['c']), isTrue);
    // The inserted child is a fresh render object.
    expect(before.containsValue(after[1]), isFalse);
  });

  test('removal drops the render object and keeps the others', () {
    var binding = pumpHosted(const Column(children: [
      Text('a', key: ValueKey('a')),
      Text('b', key: ValueKey('b')),
      Text('c', key: ValueKey('c')),
    ]));
    var before = {for (var t in texts(binding)) t.text: t};

    rebuild(
        binding,
        const Column(children: [
          Text('a', key: ValueKey('a')),
          Text('c', key: ValueKey('c')),
        ]));

    var after = texts(binding);
    expect(after.map((t) => t.text).toList(), ['a', 'c']);
    expect(identical(after[0], before['a']), isTrue);
    expect(identical(after[1], before['c']), isTrue);
    expect(after.contains(before['b']), isFalse);
  });

  test('a type change tears down the old render object and inflates a new one',
      () {
    var binding = pumpHosted(const Column(children: [Text('only')]));
    var oldChild = (binding.renderView.child! as RenderFlex).children.single;
    expect(oldChild, isA<RenderText>());

    rebuild(
        binding,
        const Column(children: [
          ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: 2), child: Text('x'))
        ]));

    var newChild = (binding.renderView.child! as RenderFlex).children.single;
    expect(newChild, isA<RenderConstrainedBox>());
    expect(identical(oldChild, newChild), isFalse);
  });

  test('keyless same-type children update in place', () {
    var binding = pumpHosted(const Column(children: [Text('a'), Text('b')]));
    var before = texts(binding);

    rebuild(binding, const Column(children: [Text('a2'), Text('b2')]));

    var after = texts(binding);
    // No keys, same type, same position => same elements/render objects.
    expect(identical(after[0], before[0]), isTrue);
    expect(identical(after[1], before[1]), isTrue);
    expect(after.map((t) => t.text).toList(), ['a2', 'b2']);
  });
}
