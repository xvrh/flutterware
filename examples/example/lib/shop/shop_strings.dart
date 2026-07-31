import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The demo shop's copy, in the app's two languages — a hand-rolled
/// `Localizations` entry, because a demo should show localized scenarios
/// without dragging in a codegen pipeline.
class ShopStrings {
  ShopStrings(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<ShopStrings> delegate = _Delegate();

  static ShopStrings of(BuildContext context) =>
      Localizations.of<ShopStrings>(context, ShopStrings)!;

  bool get _fr => locale.languageCode == 'fr';

  String get title => 'Brewline';
  String get tagline => _fr
      ? 'Votre café, prêt avant vous.'
      : 'Your coffee, ready before you are.';
  String get getStarted => _fr ? 'Commencer' : 'Get started';
  String get menuTitle => _fr ? 'La carte' : 'The menu';
  String get addToCart => _fr ? 'Ajouter au panier' : 'Add to cart';
  String get size => _fr ? 'Taille' : 'Size';
  String get sizeSmall => _fr ? 'Petit' : 'Small';
  String get sizeMedium => _fr ? 'Moyen' : 'Medium';
  String get sizeLarge => _fr ? 'Grand' : 'Large';
  String get yourOrder => _fr ? 'Votre commande' : 'Your order';
  String get total => 'Total';
  String get nameOnCup => _fr ? 'Nom sur le gobelet' : 'Name on the cup';
  String get placeOrder => _fr ? 'Commander' : 'Place order';
  String get emptyCart => _fr ? 'Le panier est vide.' : 'Your cart is empty.';
  String thanks(String name) => _fr ? 'Merci, $name !' : 'Thanks, $name!';
  String get onItsWay =>
      _fr ? 'Votre commande est en préparation.' : 'Your order is on its way.';
  String get backToMenu => _fr ? 'Retour à la carte' : 'Back to menu';

  String describe(String drinkId) => switch (drinkId) {
    'cappuccino' =>
      _fr
          ? 'Espresso, lait vapeur, mousse soyeuse.'
          : 'Espresso, steamed milk, silky foam.',
    'flat-white' =>
      _fr
          ? 'Double espresso sous un voile de lait.'
          : 'Double espresso under a thin veil of milk.',
    'matcha' =>
      _fr
          ? 'Thé vert fouetté, doux et végétal.'
          : 'Whisked green tea, soft and grassy.',
    'chai' =>
      _fr ? 'Épices chaudes, lait onctueux.' : 'Warm spices, creamy milk.',
    'cold-brew' =>
      _fr
          ? 'Infusé à froid pendant seize heures.'
          : 'Steeped cold for sixteen hours.',
    _ => '',
  };
}

class _Delegate extends LocalizationsDelegate<ShopStrings> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) =>
      const ['en', 'fr'].contains(locale.languageCode);

  @override
  Future<ShopStrings> load(Locale locale) =>
      SynchronousFuture(ShopStrings(locale));

  @override
  bool shouldReload(_Delegate old) => false;
}
