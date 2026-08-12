/// How the launcher-icon viewer writes itself into an address.
///
/// The reading half lives in the panel itself, which rebuilds its place from
/// `AddressScope` directly — the inverse parser this file used to carry had
/// no production caller and was deleted rather than left as a second reader
/// to drift.
library;

import '../../launcher_icon/model/role.dart';

/// A place in the viewer: a package, an Android source set within it, and —
/// through the axes — one role seen under one launcher mask.
///
/// The role and mask are **axes rather than segments**, which is the
/// framework's own distinction (`lib/src/plugins/address.dart`): segments are
/// identity, query parameters are the same thing seen differently. An adaptive
/// icon under a circular mask is not a different icon, it is this icon on a
/// different launcher.
class IconPlace {
  const IconPlace(this.package, {this.flavor, this.role, this.mask});

  /// The workspace-relative package path — `.`, `examples/example`.
  final String package;

  /// Which Android source set (`android/app/src/<flavor>/`), or null for the
  /// default `main`.
  final String? flavor;

  /// Null when the address names no role, which is where selecting the plugin
  /// off the rail leaves you — the panel then shows everything.
  final IconRole? role;

  /// Which launcher shape to draw an adaptive icon under. Null falls back to
  /// the panel's default; it means nothing off Android.
  final AdaptiveMask? mask;

  @override
  bool operator ==(Object other) =>
      other is IconPlace &&
      other.package == package &&
      other.flavor == flavor &&
      other.role == role &&
      other.mask == mask;

  @override
  int get hashCode => Object.hash(package, flavor, role, mask);

  @override
  String toString() =>
      'IconPlace($package${flavor == null ? '' : '/$flavor'}'
      '${role == null ? '' : ' ${role!.id}'}'
      '${mask == null ? '' : ' ${mask!.name}'})';
}

/// The address segments naming [package] and, if given, [flavor].
///
/// The package stays one segment even though its path may contain slashes,
/// matching the splash previewer and the asset inspector — a flavour after it
/// would otherwise be indistinguishable from another directory level.
List<String> iconSegments(String package, [String? flavor]) => [
  package,
  if (flavor != null && flavor.isNotEmpty) flavor,
];

/// The axes naming a cell. Empty entries are omitted rather than written blank,
/// so an address that names no cell round-trips to one that names no cell.
Map<String, String> iconAxes({IconRole? role, AdaptiveMask? mask}) => {
  if (role != null) 'role': role.id,
  if (mask != null) 'mask': mask.name,
};
