/// How the dependencies plugin writes itself into an address, and how it reads
/// itself back out.
///
/// Both directions in one file for the reason
/// `ui_catalog_address.dart` gives: encode and decode that live apart drift,
/// and the symptom is an app that navigates without throwing and shows the
/// wrong thing. The round trip is the contract, and a test enforces it.
///
/// ```
/// <package>                        the dependency list
/// <package>/packages/<dependency>  one dependency's detail page
/// <package>/upgrade                the upgrade screen
/// ```
///
/// `packages/<dependency>` stays two segments rather than one because the
/// literal is what tells it apart from `upgrade` — read positionally, not
/// matched against a pattern.
library;

/// A place in the dependencies plugin.
class DependencyPlace {
  const DependencyPlace(this.package, {this.dependency, this.upgrade = false});

  /// The workspace-relative package path — `app`, `examples/example` — whose
  /// dependencies are being shown. The sub-entry the shell's rail selects.
  final String package;

  /// The dependency whose detail page is open, or null for the list.
  final String? dependency;

  /// The upgrade screen. Nothing links to it; an address can still name it.
  final bool upgrade;

  @override
  bool operator ==(Object other) =>
      other is DependencyPlace &&
      other.package == package &&
      other.dependency == dependency &&
      other.upgrade == upgrade;

  @override
  int get hashCode => Object.hash(package, dependency, upgrade);

  @override
  String toString() =>
      'DependencyPlace($package${upgrade ? '/upgrade' : ''}'
      '${dependency == null ? '' : '/packages/$dependency'})';
}

/// The address segments naming [package] and, if given, where inside it.
List<String> dependencySegments(
  String package, {
  String? dependency,
  bool upgrade = false,
}) => [
  package,
  if (upgrade)
    'upgrade'
  else if (dependency != null) ...[
    'packages',
    dependency,
  ],
];

/// The inverse of [dependencySegments].
///
/// A tail this does not recognise — `packages` naming nothing after it, or a
/// word from an address written against some older shape — reads as the list.
/// That is the package's own screen and the least surprising place to be left;
/// the alternative is a panel that renders nothing and says nothing.
DependencyPlace? dependencyPlace(List<String> segments) {
  if (segments.isEmpty) return null;
  var package = segments.first;
  return switch (segments.skip(1).toList()) {
    ['upgrade'] => DependencyPlace(package, upgrade: true),
    ['packages', var dependency] when dependency.isNotEmpty => DependencyPlace(
      package,
      dependency: dependency,
    ),
    _ => DependencyPlace(package),
  };
}
