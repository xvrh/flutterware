import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_example/shop/shop_app.dart';

/// Naming the cup, on a phone, with the keyboard where a phone would put it.
///
/// **This is what the feature is for.** Every other scenario in this folder
/// photographs the cart screen at its full 852 points and calls that the
/// picture; on a real phone the moment somebody touches that field the screen
/// is 516, the button they are reaching for has moved, and whether the layout
/// survives it is the question nothing here could ask.
///
/// Nothing below asks for a keyboard. `enterText` focuses the field, the
/// framework asks the platform for one, and the run raises it — which is the
/// whole design: a flow that fills a form is a flow a phone could have
/// performed, and its shots are pictures a phone could have taken.
///
/// The one verb that *is* about the keyboard is the dismissal, and it is here
/// because a user does it: swiping the keyboard away is how you get at what
/// was under it, and it makes the app let go of the field rather than making
/// artwork disappear.
void main() {
  scenario('Naming the cup', (s) async {
    await s.pumpWidget(const ShopApp());
    await s.tap(ShopKeys.getStarted);
    await s.tap('Cappuccino');
    await s.tap(ShopKeys.size(DrinkSize.small));
    await s.tap(ShopKeys.addToCart, shot: Shot('Cart'));
    // The keyboard comes up here, unasked, because the field took focus.
    await s.enterText(ShopKeys.cupName, 'Ada', shot: Shot('Typing the name'));
    expect(s.keyboard.isUp, isTrue);
    expect(s.keyboard.isRequested, isTrue);
    await s.keyboard.dismiss(shot: Shot('Ready to order'));
    // And the app let go of the field, which is what a dismissal means.
    expect(s.keyboard.isRequested, isFalse);
    await s.tap(ShopKeys.placeOrder, shot: Shot('Order placed'));
  });
}
