import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/shop/shop_app.dart';

/// The Brewline demo suite. Tap targets are [ShopKeys], so the same flow
/// runs under every language axis; drink names are proper nouns and safe to
/// tap by text.
void main() {
  scenario('Order a cappuccino', (s) async {
    await s.pumpWidget(const ShopApp(), shot: Shot('Welcome'));
    await s.tap(ShopKeys.getStarted, shot: Shot('Menu'));
    await s.tap('Cappuccino');
    await s.tap(ShopKeys.size(DrinkSize.large));
    await s.tap(ShopKeys.addToCart, shot: Shot('Cart'));
    await s.enterText(ShopKeys.cupName, 'Xavier');
    await s.tap(ShopKeys.placeOrder, shot: Shot('Order placed'));
  });

  scenario('An empty cart says so', (s) async {
    await s.pumpWidget(const ShopApp(), shot: Shot.skip);
    await s.tap(ShopKeys.getStarted, shot: Shot.skip);
    await s.tap(ShopKeys.openCart, shot: Shot('Empty cart'));
  });
}
