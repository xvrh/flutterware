import 'package:flutter_studio_app/src/test_runner/ui/menu_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TreePath startsWith', () {
    expect(TreePath(['aa', 'bb']).startsWith(TreePath(['aa'])), isTrue);
    expect(TreePath(['aa', 'bb']).startsWith(TreePath(['bb'])), isFalse);
    expect(TreePath(['aa', 'bb']).startsWith(TreePath(['aa', 'bb', 'c'])),
        isFalse);
    expect(TreePath(['a', 'b']).startsWith(TreePath(['a', 'b'])), isTrue);
    expect(TreePath(['a']).startsWith(TreePath(['a'])), isTrue);
  });

  test('TreePath encoded', () {
    expect(TreePath(['aa', 'bb']).encoded, 'aa/bb');
    expect(TreePath.fromEncoded('aa/bb'), TreePath(['aa', 'bb']));

    expect(TreePath(['aa/12', 'bb']).encoded, 'aa%2F12/bb');
    expect(
        TreePath.fromEncoded(Uri.decodeComponent(
            Uri.encodeComponent(TreePath(['aa/12', 'bb']).encoded))),
        TreePath(['aa/12', 'bb']));
  });
}
