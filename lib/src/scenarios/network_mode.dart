/// What a scenario's http requests reach.
///
/// A scenario runs under fake time, and `flutter_test` answers every request
/// with an empty 400 — so an app that loads an avatar renders a blank box and
/// says nothing about why. This is the setting that decides what happens
/// instead, and it is said in the same places [Shots] is: a folder's
/// `runScenarios(network: ...)`, one run's `--network=`, one
/// `scenario(network: ...)`. Nearest wins, except that a run beats a folder.
///
/// Whatever the mode, a `s.network` stub always beats it — the mode governs
/// what happens to the requests the scenario did not state an answer for.
///
/// It lives in its own file, like [Shots], because the CLI reads it to
/// validate an argument and must not reach Flutter to do so, while the
/// funnel that acts on it is nothing but Flutter.
library;

enum ScenarioNetwork {
  /// Nothing leaves the process.
  ///
  /// A request nothing stubbed fails **immediately**, with a message naming
  /// the url and how to answer it, and lands on the step as a network event.
  /// It does not fail the scenario: a decorative avatar is not a reason to
  /// throw away a flow's other twelve assertions, and a scenario that wants
  /// the picture says so with a stub or with [live].
  ///
  /// The default, and an improvement on what it replaces even for a suite that
  /// never configures anything: `flutter_test`'s own answer hangs rather than
  /// fails when the url is https.
  off,

  /// Requests go out, and what comes back is whatever the network says today.
  ///
  /// The easy mode and the honest one — the app talks to the thing it talks
  /// to. It costs the property every other default here exists to protect:
  /// two runs of the same suite are no longer the same run, an aeroplane or a
  /// rate limit turns a green suite red, and the image cache is emptied per
  /// scenario by design, so a suite pays its round trips once *per scenario*
  /// rather than once.
  live,
}

/// [raw] as a mode, or a refusal listing the ones there are.
///
/// Refused rather than defaulted: a typo that quietly means `off` is a suite
/// whose pictures are all blank for a reason nothing on the screen says.
ScenarioNetwork parseScenarioNetwork(String raw) =>
    ScenarioNetwork.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => throw ArgumentError.value(
        raw,
        'network',
        'Not a network mode. One of: ${scenarioNetworkNames.join(', ')}',
      ),
    );

/// Every mode's name, in the order they are worth offering in.
const scenarioNetworkNames = ['off', 'live'];
