import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/plugins/native/translations_address.dart';

void main() {
  test('a place round-trips through its segments and axes', () {
    var place = const TranslationPlace(
      'packages/app',
      catalog: 'app',
      key: 'checkout.title',
      locale: 'nl',
      filter: TranslationFilter.missing,
    );

    var back = translationPlace(
      translationSegments(
        place.package,
        catalog: place.catalog,
        key: place.key,
      ),
      locale: translationAxes(
        locale: place.locale,
        filter: place.filter,
      )['locale'],
      filter: translationAxes(
        locale: place.locale,
        filter: place.filter,
      )['filter'],
    );

    expect(back, place);
  });

  test('a package alone is the table', () {
    var place = translationPlace(['packages/app']);

    expect(place?.key, isNull);
    expect(place?.filter, TranslationFilter.all);
  });

  test('the defaults are absent from the axes, not spelled out', () {
    // An address that names every default is one nobody can read at a glance.
    expect(translationAxes(), isEmpty);
    expect(translationAxes(filter: TranslationFilter.all), isEmpty);
  });

  test('a key containing a slash survives the trip', () {
    var back = translationPlace(['packages/app', 'app', 'a', 'b']);

    expect(back?.key, 'a/b');
  });

  test('an unknown filter reads as all, not as nothing', () {
    expect(TranslationFilter.byId('nonsense'), TranslationFilter.all);
    expect(TranslationFilter.byId(null), TranslationFilter.all);
  });
}
