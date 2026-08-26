import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/store/tree.dart';

/// Where an exported image lands.
///
/// The last test is the one that matters and the rest are its supporting cast.
/// It states the invariant a whole export has to hold — **no two images share a
/// path** — as a property over every layout rather than as a fact about one,
/// because the way it broke was not visible in any single path.
///
/// It broke like this: fastlane's iOS tree gives every display class the same
/// directory per locale, since `deliver` reads the class off the image's
/// dimensions rather than off where it sits. Both classes wrote
/// `01-welcome.png` into `ios/en-US/`. Nothing errored, nothing warned, the
/// result reported thirty images — and fifteen files existed, every one of them
/// an iPad.
void main() {
  var appStore = const AppStoreListing(locales: {'en': 'en-US', 'fr': 'fr-FR'});
  var play = const PlayListing(locales: {'en': 'en-US', 'fr': 'fr-FR'});

  group('the fastlane tree', () {
    test('gives deliver one directory per locale, whatever the class', () {
      var paths = {
        for (var t in appStore.targets)
          t.id: storeDirectoryFor(StoreLayout.fastlane, t, 'en-US'),
      };
      expect(paths['iphone-6-9'], 'ios/en-US');
      expect(paths['ipad-13'], 'ios/en-US');
    });

    test('names the class in the file, since the directory cannot', () {
      var names = {
        for (var t in appStore.targets)
          t.id: storeFileNameFor(StoreLayout.fastlane, t, '01-welcome'),
      };
      expect(names['iphone-6-9'], 'iphone-6-9-01-welcome.png');
      expect(names['ipad-13'], 'ipad-13-01-welcome.png');
    });

    test('gives supply a directory per class, so its names need none', () {
      var paths = {
        for (var t in play.targets)
          t.id: storeDirectoryFor(StoreLayout.fastlane, t, 'fr-FR'),
      };
      expect(paths['phone'], 'android/fr-FR/images/phoneScreenshots');
      expect(paths['tablet-10'], 'android/fr-FR/images/tenInchScreenshots');
      for (var t in play.targets) {
        expect(
          storeFileNameFor(StoreLayout.fastlane, t, '01-welcome'),
          '01-welcome.png',
        );
      }
    });
  });

  test('the plain tree separates every set by directory', () {
    expect(
      storeDirectoryFor(StoreLayout.plain, appStore.targets.first, 'en-US'),
      'app-store/iphone-6-9/en-US',
    );
  });

  group('a slug sorts, survives a filesystem, and still reads', () {
    test('over ASCII', () {
      expect(storeSlug('Cart · large'), 'cart-large');
      expect(storeSlug('Order placed!'), 'order-placed');
    });

    // A listing localized into Japanese is exactly the listing this plugin is
    // for. The ASCII class dropped the name entirely: `02-.png` on disk, `02-`
    // as the viewer's title, and `--shot=メニュー` matching nothing.
    test('and over every other script', () {
      expect(storeSlug('メニュー'), 'メニュー');
      expect(storeSlug('Корзина'), 'корзина');
      expect(storeSlug('الطلب تم'), 'الطلب-تم');
      expect(storeSlug('Café · Größe'), 'café-größe');
    });

    test('falling back only where there is no letter or digit at all', () {
      expect(storeSlug('🎉'), 'shot');
      expect(storeSlug('···'), 'shot');
      expect(storeSlug('🎉 Done'), 'done');
    });
  });

  for (var layout in StoreLayout.values) {
    test('no two images of a whole export share a path — ${layout.name}', () {
      // Every set of a two-store, two-class-each, two-locale listing, with the
      // same three shot names in each, which is exactly the shape that
      // collided.
      var paths = <String>[];
      for (var listing in <Listing>[appStore, play]) {
        for (var target in listing.targets) {
          for (var storeLocale in listing.locales.values) {
            for (var (index, shot) in ['Welcome', 'Menu', 'Cart'].indexed) {
              var stem = '${'${index + 1}'.padLeft(2, '0')}-${storeSlug(shot)}';
              paths.add(
                '${storeDirectoryFor(layout, target, storeLocale)}/'
                '${storeFileNameFor(layout, target, stem)}',
              );
            }
          }
        }
      }
      expect(
        paths.toSet(),
        hasLength(paths.length),
        reason: 'a repeated path is a screenshot silently overwriting another',
      );
    });
  }

  group('which images a set owns', () {
    // Asked by the sweep before a narrowed export, and by the question of what
    // a set currently holds. The two disagreeing would mean an export that
    // deletes an image and then reports it as present.
    test('every PNG, where the directory belongs to the set', () {
      var phone = play.targets.first;
      expect(
        storeOwnsFile(StoreLayout.fastlane, phone, '01-welcome.png'),
        isTrue,
      );
      expect(
        storeOwnsFile(StoreLayout.plain, appStore.targets.first, '01-a.png'),
        isTrue,
      );
    });

    test('only its own, where fastlane makes two classes share one', () {
      var targets = {for (var t in appStore.targets) t.id: t};
      expect(
        storeOwnsFile(
          StoreLayout.fastlane,
          targets['iphone-6-9']!,
          'iphone-6-9-01-welcome.png',
        ),
        isTrue,
      );
      expect(
        storeOwnsFile(
          StoreLayout.fastlane,
          targets['iphone-6-9']!,
          'ipad-13-01-welcome.png',
        ),
        isFalse,
        reason: 'recomposing the iPhone set would delete the iPad set',
      );
    });

    test('and never something that is not an image', () {
      for (var name in ['full_description.txt', 'title.txt', '.DS_Store']) {
        expect(
          storeOwnsFile(StoreLayout.fastlane, play.targets.first, name),
          isFalse,
          reason: 'an export into a metadata tree would delete $name',
        );
      }
    });
  });

  group('a written file, back to the shot it is of', () {
    // A reader that works this out from the string cannot: the App Store's
    // own class id ends in a number, so `iphone-6-9-02-menu` has three
    // plausible numbers in it. The first title the detail page ever drew was
    // `9 02 menu`.
    test('past a class id that ends in a number', () {
      var targets = {for (var t in appStore.targets) t.id: t};
      expect(
        storeTitleOf(
          StoreLayout.fastlane,
          targets['iphone-6-9']!,
          'iphone-6-9-02-menu.png',
        ),
        'Menu',
      );
      expect(
        storeTitleOf(
          StoreLayout.fastlane,
          targets['iphone-6-9']!,
          'iphone-6-9-11-back-at-the-menu.png',
        ),
        'Back at the menu',
      );
    });

    test('where the directory carries the class and the name does not', () {
      expect(
        storeTitleOf(
          StoreLayout.fastlane,
          play.targets.first,
          '04-order-placed.png',
        ),
        'Order placed',
      );
      expect(
        storeTitleOf(StoreLayout.plain, appStore.targets.first, '01-cart.png'),
        'Cart',
      );
    });

    // Round-trips against the function that wrote the name, over every layout
    // and every target — which is the only way to know the two agree.
    for (var layout in StoreLayout.values) {
      test('round-trips whatever storeFileNameFor wrote — ${layout.name}', () {
        for (var target in [...appStore.targets, ...play.targets]) {
          var written = storeFileNameFor(layout, target, '07-order-placed');
          expect(
            storeTitleOf(layout, target, written),
            'Order placed',
            reason: '$written under ${target.id}',
          );
        }
      });
    }
  });

  group('addressing one shot', () {
    test('by position, however it is spelled', () {
      expect(storeShotMatches('02-order-placed', '02'), isTrue);
      expect(storeShotMatches('02-order-placed', '2'), isTrue);
      expect(storeShotMatches('02-order-placed', '3'), isFalse);
    });

    test('by name, however it is spelled', () {
      expect(storeShotMatches('02-order-placed', 'order-placed'), isTrue);
      expect(storeShotMatches('02-order-placed', 'Order placed'), isTrue);
      expect(storeShotMatches('02-order-placed', ' order-placed '), isTrue);
    });

    // The narrowing argument must not quietly do more than it says. Two shots
    // sharing a prefix is the ordinary case — a listing walks one flow — so a
    // substring match would take both and report a green export of the wrong
    // set, which is how the filename collision got out.
    test('and never by a prefix of either', () {
      expect(storeShotMatches('02-cart-empty', 'cart'), isFalse);
      expect(storeShotMatches('02-cart-empty', 'cart-emp'), isFalse);
      expect(storeShotMatches('12-cart-empty', '1'), isFalse);
    });

    test('a name that is only digits is still a position', () {
      // Nothing to do about it, and worth stating: a shot literally called
      // "2024" is addressed by its position, not its name.
      expect(storeShotParts('03-2024'), (3, '2024'));
      expect(storeShotMatches('03-2024', '2024'), isFalse);
      expect(storeShotMatches('03-2024', '3'), isTrue);
    });
  });

  group('what gets composed', () {
    // The promise made when the frame was built: adding it must not change
    // what a project with no frame already exports. Asserted rather than
    // argued — "by construction" is exactly what would have been said about
    // the filename collision the export before this one shipped.
    test('nothing of the App Store, for a project with no frame', () {
      for (var target in appStore.targets) {
        expect(
          storeShouldCompose(hasFrame: false, target: target),
          isFalse,
          reason:
              '${target.id} would start being composed, and every image of '
              'every existing listing would change',
        );
      }
    });

    test("Play's phone, because its canvas is not its device", () {
      var targets = {for (var t in play.targets) t.id: t};
      expect(
        storeShouldCompose(hasFrame: false, target: targets['phone']!),
        isTrue,
      );
      expect(
        storeShouldCompose(hasFrame: false, target: targets['tablet-10']!),
        isFalse,
      );
    });

    test('everything, once a frame is declared', () {
      for (var target in [...appStore.targets, ...play.targets]) {
        expect(storeShouldCompose(hasFrame: true, target: target), isTrue);
      }
    });
  });
}
