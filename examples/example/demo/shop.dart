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
Widget shopConfirmation() => Builder(
  builder: (context) =>
      ConfirmationScreen(name: context.knobs.string('name', 'Sam')),
);

/// One component in every state it has, on one sheet — the badge that
/// stands for a drink, for every drink at the three sizes the screens use.
/// Not a screen: what a reader checks here is that the set reads as one
/// family, which no screen shows at once.
@Preview(name: 'Drink badges', group: 'Brewline', wrapper: wrapInShop)
Widget shopBadges() => const _BadgeSheet();

class _BadgeSheet extends StatelessWidget {
  const _BadgeSheet();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (var size in const [40.0, 56.0, 80.0]) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${size.round()} points',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var drink in drinks) DrinkBadge(drink, size: size),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
