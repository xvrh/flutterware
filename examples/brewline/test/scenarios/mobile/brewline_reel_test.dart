import 'package:flutterware/flutter_test.dart';
import 'package:brewline/shop/shop_app.dart';

import 'brewline_reel.dart';

/// The shop, cut for a landing page.
///
/// An ordinary scenario — it runs under `flutter test` and in the panel like
/// every other, and there it is evidence: the titles and cues below cost
/// nothing and change no picture. Rendered with `--reel=true` it is cut by
/// [BrewlineReel], which reads them back as types.
///
/// ```sh
/// dart run flutterware run scenarios video \
///   --file=test/scenarios/mobile/brewline_reel_test.dart --reel=true
/// ```
void main() {
  scenario('Brewline in twenty seconds', reel: const BrewlineReel(), (s) async {
    await s.pumpWidget(const ShopApp());
    s.title('Ordered before you are awake.');
    await s.tap(ShopKeys.getStarted);

    s.title('Five drinks. Pick one.');
    await s.tap('Cappuccino');

    s.film.emit(const Callout('Pick a size'));
    await s.tap(ShopKeys.size(DrinkSize.large));
    s.film.emit(const Callout('Into the cart'));
    await s.tap(ShopKeys.addToCart);

    s.title('Your name on the cup.');
    await s.enterText(ShopKeys.cupName, 'Ada');
    await s.tap(ShopKeys.placeOrder);
    expect(find.textContaining('Ada'), findsOneWidget);

    var cappuccino = drinks.firstWhere((d) => d.id == 'cappuccino');
    s.film.emit(
      Receipt(
        name: 'Ada',
        order: 'Large ${cappuccino.name.toLowerCase()}',
        price: formatPrice(CartItem(cappuccino, DrinkSize.large).price),
      ),
    );
  });
}
