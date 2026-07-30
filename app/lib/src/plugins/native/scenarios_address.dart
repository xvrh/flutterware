/// How the scenarios plugin writes itself into an address, and how it reads
/// itself back out — both directions in one file, with a round-trip test, for
/// the reason `dependencies_address.dart` gives.
///
/// ```
/// <package>                          the package's scenario list
/// <package>/<file…>/<scenario>       one scenario
/// ```
///
/// The package path is one segment (the framework escapes `/`); the source
/// file is split into path segments so the tree reads naturally; the file's
/// end is recognised by its `.dart` suffix, which is what makes the scenario
/// name after it unambiguous. Step addressing (`…/<scenario>/<step>`) arrives
/// with the runner, not the skeleton.
library;

/// A place in the scenarios plugin.
class ScenarioPlace {
  const ScenarioPlace(this.package, {this.file, this.scenario});

  /// The workspace-relative package path whose scenarios are shown.
  final String package;

  /// The package-relative source file, `/`-separated, or null for the list.
  final String? file;

  /// The scenario within [file], or null for the whole file.
  final String? scenario;

  @override
  bool operator ==(Object other) =>
      other is ScenarioPlace &&
      other.package == package &&
      other.file == file &&
      other.scenario == scenario;

  @override
  int get hashCode => Object.hash(package, file, scenario);

  @override
  String toString() =>
      'ScenarioPlace($package'
      '${file == null ? '' : '/$file'}'
      '${scenario == null ? '' : '#$scenario'})';
}

/// The address segments naming [package] and, if given, where inside it.
List<String> scenarioSegments(
  String package, {
  String? file,
  String? scenario,
}) {
  assert(scenario == null || file != null, 'a scenario needs its file');
  return [package, ...?file?.split('/'), ?scenario];
}

/// The inverse of [scenarioSegments].
///
/// A tail this does not recognise — no `.dart` segment, or trailing segments
/// past the scenario name — reads as the nearest place it does recognise,
/// which leaves the panel showing something rather than nothing.
ScenarioPlace? scenarioPlace(List<String> segments) {
  if (segments.isEmpty) return null;
  var package = segments.first;
  var rest = segments.skip(1).toList();
  var dartIndex = rest.indexWhere((s) => s.endsWith('.dart'));
  if (dartIndex < 0) return ScenarioPlace(package);
  var file = rest.take(dartIndex + 1).join('/');
  var scenario = dartIndex + 1 < rest.length ? rest[dartIndex + 1] : null;
  return ScenarioPlace(package, file: file, scenario: scenario);
}
