import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/shop/shop_app.dart';

/// The Brewline demo suite. Tap targets are [ShopKeys], so the same flow
/// runs under every language axis; drink names are proper nouns and safe to
/// tap by text.
void main() {
  // The multi-path flagship: one visit to the shop, split at the menu into
  // every way it can go — the flow graph fans out where the app does. Each
  // branch replays the body from the top, so it starts from the exact state
  // the menu was reached with.
  scenario('Around the shop', (s) async {
    await s.pumpWidget(const ShopApp(), shot: Shot('Welcome'));
    await s.tap(ShopKeys.getStarted, shot: Shot('Menu'));
    await s.split({
      'a cappuccino': () async {
        await s.tap('Cappuccino');
        // Splits nest: two cup sizes, and everything after this inner split
        // — the cart, the order — runs once per size, because by then the
        // paths have genuinely diverged.
        await s.split({
          'small cup': () async {
            await s.tap(ShopKeys.size(DrinkSize.small));
            await s.tap(ShopKeys.addToCart, shot: Shot('Cart · small'));
          },
          'large cup': () async {
            await s.tap(ShopKeys.size(DrinkSize.large));
            await s.tap(ShopKeys.addToCart, shot: Shot('Cart · large'));
          },
        });
        await s.enterText(ShopKeys.cupName, 'Xavier');
        await s.tap(ShopKeys.placeOrder, shot: Shot('Order placed'));
      },
      'a cold brew': () async {
        await s.tap('Cold brew');
        await s.tap(ShopKeys.addToCart, shot: Shot('Cart'));
        await s.tap(ShopKeys.placeOrder, shot: Shot('Order placed'));
      },
      'the empty cart': () async {
        await s.tap(ShopKeys.openCart, shot: Shot('Empty cart'));
      },
    });
  });

  // The linear reference next to the fan-out — and the one this project ships
  // to the store: `tags: ['store']` is what `fw run scenarios shots --tag`
  // narrows to, so a listing gets three deliberate screenshots rather than
  // every frame the suite happens to capture.
  scenario('Order a cappuccino', (s) async {
    await s.pumpWidget(const ShopApp(), shot: Shot('Welcome', tags: ['store']));
    await s.tap(ShopKeys.getStarted, shot: Shot('Menu', tags: ['store']));
    await s.tap('Cappuccino');
    await s.tap(ShopKeys.size(DrinkSize.large));
    await s.tap(ShopKeys.addToCart, shot: Shot('Cart'));
    await s.enterText(ShopKeys.cupName, 'Xavier');
    await s.tap(
      ShopKeys.placeOrder,
      shot: Shot('Order placed', tags: ['store']),
    );
  });
}
