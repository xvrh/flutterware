import '../session/job.dart';

/// A run action refusing, in a sentence written to be read.
///
/// An error crossing the channel travels as its message and nothing else,
/// landing verbatim in the cockpit's error pane and in an MCP reply — so
/// `StateError` would put *"Bad state:"* in front of a sentence somebody has
/// to read. Same reasoning as `DatabaseUnavailable` on the published side and
/// `AppNotStarted` beside this one.
///
/// A [ProjectFault], because every refusal here states a fact about the
/// project or the run — an app still building, a panel that does not exist, a
/// knob `main` does not take — and a stack out of this package would send the
/// reader to debug the wrong program.
class RunRefusal implements ProjectFault {
  RunRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}
