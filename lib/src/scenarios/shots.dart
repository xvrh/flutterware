/// Whether a scenario captures a screenshot after every high-level action, or
/// only where a [Shot] or `ScenarioTester.screen` asks for one.
///
/// Said per scenario, or once for a whole folder through `runScenarios`. It
/// lives in its own file because both of those doors need it and neither may
/// import the other.
enum Shots { auto, manual }

/// Per-call override of a scenario's screenshot behaviour.
///
/// `Shot('Name')` captures and names the step — a named shot is a primary
/// node in the flow graph, an automatic one is collapsible detail.
/// [Shot.skip] suppresses the capture entirely.
class Shot {
  const Shot(String this.name, {this.tags = const []});

  const Shot._skip() : name = null, tags = const [];

  /// Suppresses the automatic screenshot for one call.
  static const skip = Shot._skip();

  final String? name;
  final List<String> tags;
}
