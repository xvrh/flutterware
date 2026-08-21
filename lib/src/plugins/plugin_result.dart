/// What an action hands back when it hands back *data* rather than a file.
///
/// A marker interface, nothing more. Two things needed one:
///
/// Renderers were guessing: `fw` decided how to print a result by asking
/// `value is Map || value is List`, which is a test that says "this is a map"
/// rather than "this is a result". The moment a core returns a typed
/// object that test goes false and the output quietly degrades to
/// `toString()`.
///
/// Cores were building maps by hand, nested three deep, which is where a
/// key spelled `entires` lives for months. A class with fields is checked by
/// the compiler, and — since the shape of an action's result is extracted
/// statically from that class — it is also what the capability document and an
/// agent get told.
///
/// `jsonEncode` calls [toJson] through its default `toEncodable`, so nothing
/// downstream needs to know about this type to encode one.
abstract interface class PluginResult {
  /// The wire form. Keys here are what every surface shows and what an agent
  /// parses, so they are part of the action's contract.
  Map<String, Object?> toJson();
}

/// A result whose *action* succeeded while the thing it ran did not — a red
/// scenario suite, a failing analysis, a build that produced diagnostics.
///
/// The job succeeded: it compiled, it spawned, and it came back with data. But
/// `fw run … && deploy` has to stop, so `fw` exits 1 on one of these. MCP needs
/// nothing — it reads the result.
///
/// Separate from [PluginResult] rather than a member of it because that one is
/// an `interface class`: a getter there is a getter all seventeen implementers
/// must write, and only a handful can fail in this sense at all.
abstract interface class ReportsFailure {
  /// False when the action ran and what it ran did not pass.
  bool get ok;
}
