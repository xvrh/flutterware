import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/previews.dart';
import 'package:flutterware_example/shop/shop_app.dart';

/// The coffee shop's screens, one preview each — the same app the scenarios
/// walk, drawn a screen at a time under its own theme, strings and cart.
///
/// The shell is the shop itself: `ShopApp` takes the screen as its home, so
/// a preview reads the shop's theme rather than the demo shell's, and the
/// two axes a reader can turn are the ones the app supports — dark, and the
/// two languages of its strings.
Widget wrapInShop(Widget child) => PreviewShell(
  'shop',
  builder: (context, axes) => ShopApp(
    home: child,
    cart: _sampleCart(),
    themeMode: axes.flag('dark', false) ? ThemeMode.dark : ThemeMode.light,
    locale: axes.picker('locale', {
      'English': const Locale('en'),
      'Français': const Locale('fr'),
    }, const Locale('en')),
  ),
);

/// Two drinks, so the cart and its total have something to say.
Cart _sampleCart() => Cart()
  ..add(CartItem(drinks[0], DrinkSize.large))
  ..add(CartItem(drinks[4], DrinkSize.small));

@Preview(name: 'Welcome', group: 'Brewline', wrapper: wrapInShop)
Widget shopWelcome() => const WelcomeScreen();

@Preview(name: 'Menu', group: 'Brewline', wrapper: wrapInShop)
Widget shopMenu() => const MenuScreen();

@Preview(name: 'A drink', group: 'Brewline', wrapper: wrapInShop)
Widget shopDrink() => DrinkScreen(drinks[0]);

@Preview(name: 'Cart', group: 'Brewline', wrapper: wrapInShop)
Widget shopCart() => const CartScreen();

@Preview(name: 'Order placed', group: 'Brewline', wrapper: wrapInShop)
Widget shopConfirmation() => const ConfirmationScreen(name: 'Sam');
