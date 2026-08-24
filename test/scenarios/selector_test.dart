import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/src/scenarios/selector.dart';

/// What `--file` picks. One rule, read by two halves — the harness inside the
/// user's test process and the plugin that counts and refuses — so a
/// disagreement here is a run that reports a total it did not run.
void main() {
  test('a file picks itself and nothing else', () {
    expect(
      selectsFile(
        'test/app/checkout/cart_test.dart',
        'test/app/checkout/cart_test.dart',
      ),
      isTrue,
    );
    expect(
      selectsFile(
        'test/app/checkout/cart_test.dart',
        'test/app/checkout/receipt_test.dart',
      ),
      isFalse,
    );
  });

  test('a directory picks everything under it, however deep', () {
    expect(
      selectsFile('test/app/checkout', 'test/app/checkout/cart_test.dart'),
      isTrue,
    );
    expect(
      selectsFile(
        'test/app/checkout',
        'test/app/checkout/sizes/picker_test.dart',
      ),
      isTrue,
    );
    expect(
      selectsFile('test/app/checkout', 'test/app/desktop/order_test.dart'),
      isFalse,
    );
  });

  // The reason the match is separator-anchored rather than a bare prefix: a
  // suite with a folder beside the one asked for would have run both, and a
  // selector that quietly runs *more* than it names is worse than one that
  // refuses.
  test('a sibling whose name starts the same is not under it', () {
    expect(
      selectsFile(
        'test/app/checkout',
        'test/app/checkout_archive/old_test.dart',
      ),
      isFalse,
    );
  });

  test('a trailing slash is the same directory — a shell completes one', () {
    expect(
      selectsFile('test/app/checkout/', 'test/app/checkout/cart_test.dart'),
      isTrue,
    );
    expect(
      selectsFile(
        'test/app/checkout/',
        'test/app/checkout_archive/old_test.dart',
      ),
      isFalse,
    );
  });
}
