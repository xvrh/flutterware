import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/launcher_icon/model/role.dart';
import 'package:flutterware_app/src/plugins/native/icon_address.dart';

/// The round trip is the contract: an address written by the panel has to read
/// back as the same cell, or a finding opens the right plugin showing the wrong
/// icon.
void main() {
  IconPlace? roundTrip(IconPlace place) => iconPlace(
    iconSegments(place.package, place.flavor),
    iconAxes(role: place.role, mask: place.mask),
  );

  test('a package on its own round-trips', () {
    var place = const IconPlace('examples/example');
    expect(roundTrip(place), place);
  });

  test('a package with slashes stays one segment', () {
    expect(iconSegments('packages/nested/app'), ['packages/nested/app']);
    expect(iconPlace(['packages/nested/app'])!.package, 'packages/nested/app');
  });

  test('every role round-trips', () {
    for (var role in IconRole.values) {
      var place = IconPlace('.', role: role);
      expect(roundTrip(place), place, reason: role.id);
    }
  });

  test('every launcher mask round-trips', () {
    for (var mask in AdaptiveMask.values) {
      var place = IconPlace(
        '.',
        role: IconRole.androidAdaptiveForeground,
        mask: mask,
      );
      expect(roundTrip(place), place, reason: mask.name);
    }
  });

  test('a flavour round-trips alongside a role', () {
    var place = const IconPlace(
      '.',
      flavor: 'production',
      role: IconRole.androidMonochrome,
      mask: AdaptiveMask.circle,
    );
    expect(roundTrip(place), place);
  });

  test('role ids are stable and spelled for humans', () {
    // The id is explicit rather than derived from the enum constant precisely
    // so a rename cannot break a saved link. Pin a couple of them.
    expect(
      IconRole.androidAdaptiveForeground.id,
      'android.adaptive-foreground',
    );
    expect(IconRole.webMaskable.id, 'web.maskable');
    expect(IconRole.byId('ios.tinted'), IconRole.iosTinted);
  });

  test('no axes means no cell, rather than a defaulted one', () {
    // Selecting the plugin off the rail lands here, and the panel shows
    // everything. Defaulting to a role would silently pick one.
    var place = iconPlace(['.']);
    expect(place!.role, isNull);
    expect(place.mask, isNull);
    expect(iconAxes(), isEmpty);
  });

  test('an unknown axis value reads back as null rather than throwing', () {
    // An address is a thing people type.
    var place = iconPlace(['.'], {'role': 'android.hexagon', 'mask': 'blob'});
    expect(place!.role, isNull);
    expect(place.mask, isNull);
  });

  test('empty segments address nothing', () {
    expect(iconPlace([]), isNull);
  });

  test('the role and mask are axes, not segments', () {
    // Identity is the package; a mask is that icon seen on another launcher, so
    // it must survive as a query parameter on a parsed Address.
    var address = Address(
      worktree: 'main',
      plugin: 'flutterware.launcher_icon',
      segments: iconSegments('.'),
      axes: iconAxes(
        role: IconRole.androidAdaptiveForeground,
        mask: AdaptiveMask.teardrop,
      ),
    );
    var parsed = Address.parse('$address');
    expect(parsed.segments, ['.']);
    expect(parsed.axes, {
      'role': 'android.adaptive-foreground',
      'mask': 'teardrop',
    });
  });
}
