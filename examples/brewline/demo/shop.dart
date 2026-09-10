import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutterware/previews.dart';
import 'package:brewline/shop/shop_app.dart';

/// Brewline's screens, one preview each.
///
/// The app the scenarios drive, taken apart: `test/scenarios/mobile/shop_test.dart`
/// walks welcome → menu → drink → cart → confirmation as one flow, and these
/// are the same screens standing still, where a spacing or a dark-mode
/// question can be answered without replaying four taps to reach the screen
/// that asks it.
///
/// Every entry goes through [wrapInShop] rather than `demo/shell.dart`'s
/// `wrapInApp`: these screens read `Cart.of(context)` and
/// `ShopStrings.of(context)`, so a bare widget throws. That is the ordinary
/// case for previewing a screen out of an app, and the wrapper is the ordinary
/// answer to it.

/// The app chrome a Brewline screen needs: its own theme, its own strings, and
/// a cart above the navigator, exactly as `ShopApp` arranges them.
///
/// [cart] is how a screen that is only interesting with contents gets some —
/// an empty cart screen is a picture of the empty state, which is worth having
/// too, and is what the default gives.
Widget wrapInShop(Widget child, {Cart Function()? cart}) => PreviewShell(
  'shop',
  builder: (context, axes) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: shopTheme(
      axes.flag('dark', false) ? Brightness.dark : Brightness.light,
    ),
    locale: axes.picker('locale', {
      'English': const Locale('en'),
      'Français': const Locale('fr'),
    }, const Locale('en')),
    localizationsDelegates: const [
      ShopStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('fr')],
    home: CartScope(cart: (cart ?? Cart.new)(), child: child),
  ),
);

@Preview(name: 'Welcome', group: 'Shop', wrapper: wrapInShop)
Widget shopWelcome() => const WelcomeScreen();

@Preview(name: 'Menu', group: 'Shop', wrapper: wrapInShop)
Widget shopMenu() => const MenuScreen();

@Preview(name: 'Drink', group: 'Shop', wrapper: wrapInShop)
Widget shopDrink() => DrinkScreen(drinks.first);

/// The cart with something in it. A `Cart` per build rather than a shared one:
/// a preview rebuilds whenever a knob moves, and a cart that accumulated a
/// cappuccino on every rebuild would tell you about the preview rather than
/// about the screen.
@Preview(name: 'Cart', group: 'Shop', wrapper: wrapWithFullCart)
Widget shopCart() => const CartScreen();

@Preview(name: 'Order placed', group: 'Shop', wrapper: wrapInShop)
Widget shopConfirmation() => const ConfirmationScreen(name: 'Ada');

/// Public because `@Preview` only accepts public symbols as arguments — the
/// annotation is read by the analyzer, not called.
Widget wrapWithFullCart(Widget child) => wrapInShop(
  child,
  cart: () => Cart()
    ..add(CartItem(drinks[0], DrinkSize.large))
    ..add(CartItem(drinks[2], DrinkSize.small)),
);
