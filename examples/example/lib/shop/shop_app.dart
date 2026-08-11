import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'shop_screens.dart';
import 'shop_strings.dart';

export 'shop_screens.dart';
export 'shop_strings.dart';

/// Brewline — the scenario demo app: a small coffee shop that looks like a
/// product rather than a fixture. Welcome → menu → drink → cart →
/// confirmation, localized in English and French, themed light and dark, so
/// every axis of the scenario runner has something real to move.
///
/// Interactive targets carry [ShopKeys], which is what lets one scenario run
/// under every language: `tap(ShopKeys.addToCart)` does not care what the
/// button says.
class ShopApp extends StatefulWidget {
  const ShopApp({super.key, this.navigatorKey, this.overlay});

  /// Reaches the navigator from outside the widget tree. Ordinary app
  /// machinery: a notification tapped on a lock screen is delivered to a
  /// callback, not to a widget, so something has to hold the key.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Painted above every screen, below nothing. Brewline has nothing of its
  /// own to put here; the push demo puts its banner there.
  final Widget? overlay;

  @override
  State<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends State<ShopApp> {
  final _cart = Cart();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brewline',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('en'), Locale('fr')],
      localizationsDelegates: const [
        ShopStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      navigatorKey: widget.navigatorKey,
      // Above the navigator, so every pushed route sees the cart.
      builder: (context, child) => CartScope(
        cart: _cart,
        child: widget.overlay == null
            ? child!
            : Stack(
                children: [
                  child!,
                  // Positioned rather than a plain child: an overlay sized to
                  // the whole stack would swallow every tap meant for the app
                  // underneath it.
                  Positioned(top: 0, left: 0, right: 0, child: widget.overlay!),
                ],
              ),
      ),
      home: const WelcomeScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    var scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6F4E37),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// The stable identities scenarios drive — translation-proof tap targets.
class ShopKeys {
  static const getStarted = Key('shop.getStarted');
  static const addToCart = Key('shop.addToCart');
  static const cupName = Key('shop.cupName');
  static const placeOrder = Key('shop.placeOrder');
  static const backToMenu = Key('shop.backToMenu');
  static const openCart = Key('shop.openCart');
  static Key size(DrinkSize size) => Key('shop.size.${size.name}');
}

enum DrinkSize { small, medium, large }

class Drink {
  const Drink(this.id, this.name, this.price, this.emoji, this.colors);

  /// Also the key into [ShopStrings.describe] — proper nouns stay
  /// untranslated, descriptions do not.
  final String id;

  final String name;
  final double price;
  final String emoji;
  final (Color, Color) colors;
}

const drinks = [
  Drink('cappuccino', 'Cappuccino', 4.20, '☕', (
    Color(0xFFB08968),
    Color(0xFF7F5539),
  )),
  Drink('flat-white', 'Flat white', 4.60, '🥛', (
    Color(0xFFDDB892),
    Color(0xFFB08968),
  )),
  Drink('matcha', 'Matcha latte', 5.10, '🍵', (
    Color(0xFF9CAF88),
    Color(0xFF606C38),
  )),
  Drink('chai', 'Chai latte', 4.80, '🫖', (
    Color(0xFFE6B980),
    Color(0xFFB4764F),
  )),
  Drink('cold-brew', 'Cold brew', 3.90, '🧊', (
    Color(0xFF8D99AE),
    Color(0xFF2B2D42),
  )),
];

String formatPrice(double price) => '${price.toStringAsFixed(2)} €';

class CartItem {
  const CartItem(this.drink, this.size);

  final Drink drink;
  final DrinkSize size;

  double get price =>
      drink.price +
      switch (size) {
        DrinkSize.small => -0.5,
        DrinkSize.medium => 0.0,
        DrinkSize.large => 0.7,
      };
}

/// The cart, scoped to the app — a demo does not need more state machinery
/// than an inherited notifier.
class Cart extends ChangeNotifier {
  final items = <CartItem>[];

  double get total => items.fold(0, (sum, item) => sum + item.price);

  void add(CartItem item) {
    items.add(item);
    notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }

  static Cart of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CartScope>()!.notifier!;
}

class CartScope extends InheritedNotifier<Cart> {
  const CartScope({super.key, required Cart cart, required super.child})
    : super(notifier: cart);
}

/// The round drink artwork — a gradient and an emoji instead of shipped
/// bitmaps, so the demo stays a single Dart file deep and the color emoji
/// font gets exercised on every capture.
class DrinkBadge extends StatelessWidget {
  const DrinkBadge(this.drink, {super.key, this.size = 56});

  final Drink drink;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [drink.colors.$1, drink.colors.$2],
        ),
      ),
      child: Text(drink.emoji, style: TextStyle(fontSize: size * 0.45)),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var strings = ShopStrings.of(context);
    var scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.primaryContainer, scheme.surface],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Text('☕', style: TextStyle(fontSize: 44)),
                ),
                const SizedBox(height: 28),
                Text(
                  strings.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  strings.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(flex: 3),
                FilledButton(
                  key: ShopKeys.getStarted,
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => const MenuScreen()),
                  ),
                  child: Text(strings.getStarted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
