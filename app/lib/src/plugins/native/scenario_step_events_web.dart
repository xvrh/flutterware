import 'scenarios_results.dart';

/// Nothing, on a platform with no filesystem to read from.
///
/// The only caller is `ScenarioRunResult.artifacts`, which exists to hand an
/// MCP client the failing frame and the transition that produced it. On the
/// exported page the transition is already on screen — [ScenarioArtifacts]
/// fetched it over HTTP — and there is no MCP client to hand anything to.
List<Map<String, Object?>> readStepEvents(ScenarioRunStep step) => const [];
