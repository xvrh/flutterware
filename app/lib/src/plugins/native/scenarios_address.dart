/// How the scenarios plugin writes itself into an address, and how it reads
/// itself back out — both directions in one file, with a round-trip test, for
/// the reason `dependencies_address.dart` gives.
///
/// ```
/// <package>                            the package's scenario list
/// <package>/help                       how to write one
/// <package>/<file…>/<scenario>         one scenario
/// <package>/<file…>/<scenario>/<n>     one step of its run
/// <package>/<file…>/<scenario>/<n>/<i> one attachment of that step
/// ```
///
/// The package path is one segment (the framework escapes `/`); the source
/// file is split into path segments so the tree reads naturally; the file's
/// end is recognised by its `.dart` suffix, which is what makes the scenario
/// name after it unambiguous. The step is a bare index — it is the same
/// segment the `run` action's per-step addresses carry — and the attachment
/// is the bare position in the step's attachment list.
library;

/// A place in the scenarios plugin.
class ScenarioPlace {
  const ScenarioPlace(
    this.package, {
    this.file,
    this.scenario,
    this.step,
    this.attachment,
    this.help = false,
  }) : assert(scenario != null || step == null, 'a step needs its scenario'),
       assert(
         step != null || attachment == null,
         'an attachment needs its step',
       ),
       assert(!help || file == null, 'help is not inside a file');

  /// The workspace-relative package path whose scenarios are shown.
  final String package;

  /// The authoring help page — a place of its own, so it survives a reload and
  /// can be linked to.
  final bool help;

  /// The package-relative source file, `/`-separated, or null for the list.
  final String? file;

  /// The scenario within [file], or null for the whole file.
  final String? scenario;

  /// The selected step of [scenario]'s run, or null for the scenario itself.
  final int? step;

  /// The selected attachment of [step], by its position in the step's list,
  /// or null for the step itself.
  final int? attachment;

  @override
  bool operator ==(Object other) =>
      other is ScenarioPlace &&
      other.package == package &&
      other.file == file &&
      other.scenario == scenario &&
      other.step == step &&
      other.attachment == attachment &&
      other.help == help;

  @override
  int get hashCode =>
      Object.hash(package, file, scenario, step, attachment, help);

  @override
  String toString() =>
      'ScenarioPlace($package'
      '${help ? '/help' : ''}'
      '${file == null ? '' : '/$file'}'
      '${scenario == null ? '' : '#$scenario'}'
      '${step == null ? '' : '@$step'}'
      '${attachment == null ? '' : '+$attachment'})';
}

/// The address segments naming [package] and, if given, where inside it.
List<String> scenarioSegments(
  String package, {
  String? file,
  String? scenario,
  int? step,
  int? attachment,
  bool help = false,
}) {
  assert(scenario == null || file != null, 'a scenario needs its file');
  assert(step == null || scenario != null, 'a step needs its scenario');
  assert(attachment == null || step != null, 'an attachment needs its step');
  assert(!help || file == null, 'help is not inside a file');
  if (help) return [package, helpSegment];
  return [
    package,
    ...?file?.split('/'),
    ?scenario,
    if (step != null) '$step',
    if (step != null && attachment != null) '$attachment',
  ];
}

/// What names the help page. Not a file name and never ends in `.dart`, which
/// is what keeps it out of the file lane below.
const helpSegment = 'help';

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
  if (dartIndex < 0) {
    return ScenarioPlace(
      package,
      help: rest.isNotEmpty && rest.first == helpSegment,
    );
  }
  var file = rest.take(dartIndex + 1).join('/');
  var scenario = dartIndex + 1 < rest.length ? rest[dartIndex + 1] : null;
  var step = dartIndex + 2 < rest.length
      ? int.tryParse(rest[dartIndex + 2])
      : null;
  var attachment = step != null && dartIndex + 3 < rest.length
      ? int.tryParse(rest[dartIndex + 3])
      : null;
  return ScenarioPlace(
    package,
    file: file,
    scenario: scenario,
    step: step,
    attachment: attachment,
  );
}
