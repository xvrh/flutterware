import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/shop/shop_app.dart';

/// Brewline in a desktop window — the same app the mobile folder walks, at the
/// size a laptop gives it.
///
/// Nothing here names a device. The folder's `flutter_test_config.dart` does,
/// once, for every scenario beside it: `s.assignment` below reports what it
/// resolved to, so the caption on the last shot reads back the screen the
/// picture was taken on.
void main() {
  scenario('Order a cold brew on a laptop', (s) async {
    await s.pumpWidget(const ShopApp(), shot: Shot('Welcome'));
    await s.tap(ShopKeys.getStarted, shot: Shot('Menu'));
    await s.tap('Cold brew');
    await s.tap(ShopKeys.addToCart, shot: Shot('Cart'));
    await s.tap(ShopKeys.placeOrder, shot: Shot('Order placed'));

    // Written as a scenario would write it: the body adapts its own
    // expectation to the screen it was handed, rather than pinning one.
    expect(s.assignment?.device?.kind, anyOf(isNull, DeviceKind.desktop));
  });
}
