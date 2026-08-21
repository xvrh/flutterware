import 'dart:async';
import 'dart:io';

import 'package:flutterware/plugins.dart';

/// One invocation of one plugin action, from the moment it was asked for.
///
/// The return type of `Session.invoke`, and the reason that method exists: a
/// bare `Future<Object?>` has nowhere to put the things every renderer will
/// want and no renderer should implement itself — an id to write down, a
/// duration, the artifacts it produced, and a place for progress to arrive.
///
/// Nothing here crosses a process boundary yet. The events are in-memory
/// and deliberately not serialisable: a wire format for them earns nothing
/// until a job can run somewhere other than here, and guessing one now is the
/// retrofit this architecture keeps avoiding.
class Job {
  Job._({
    required this.id,
    required this.plugin,
    required this.action,
    required this.arguments,
    required this.startedAt,
  });

  /// Unique across processes, and sortable by when it started.
  final String id;

  /// The resolved plugin id — `flutterware.dependencies`, never `dependencies`.
  /// A run written down under whatever the caller typed is not identifiable.
  final String plugin;

  final String action;

  final Map<String, Object?> arguments;

  final DateTime startedAt;

  final _emitted = <JobEvent>[];
  // Closed by JobController when the job finishes — which the analyzer cannot
  // see, the two halves being different classes.
  // ignore: close_sinks
  final _live = StreamController<JobEvent>.broadcast();
  final _done = Completer<JobResult>();

  /// Everything that has happened, and everything still to happen.
  ///
  /// Replays. A broadcast controller drops events for subscribers that
  /// arrive late, and here the caller cannot subscribe until [Job] is returned
  /// — which is already after the job started. So a subscriber gets what it
  /// missed before it gets what is next, and a subscriber that arrives after
  /// the job finished still sees the whole thing.
  Stream<JobEvent> get events {
    var out = StreamController<JobEvent>();
    out.onListen = () {
      // No await between the replay and the subscription, so nothing can be
      // emitted in the gap and no event is delivered twice.
      for (var event in _emitted) {
        out.add(event);
      }
      if (_done.isCompleted) {
        unawaited(out.close());
        return;
      }
      var subscription = _live.stream.listen(out.add, onDone: out.close);
      out.onCancel = subscription.cancel;
    };
    return out.stream;
  }

  /// Completes when the action has finished — successfully or not.
  ///
  /// Never completes with an error. A failed run is a run: it has a
  /// duration, it belongs in the log, and every renderer has to report it
  /// rather than let it escape. `JobResult.error` carries the reason.
  Future<JobResult> get done => _done.future;

  bool get isFinished => _done.isCompleted;
}

/// The writing half of a [Job].
///
/// Separate because a [Job] handed to a renderer must be read-only: the one
/// thing this whole indirection buys is that every invocation is recorded the
/// same way, and that stops being true the moment a caller can finish a job
/// itself. Held by `Session.invoke`, and later by a core reporting progress.
class JobController {
  JobController({
    required String id,
    required String plugin,
    required String action,
    Map<String, Object?> arguments = const {},
    DateTime? startedAt,
  }) : job = Job._(
         id: id,
         plugin: plugin,
         action: action,
         arguments: Map.unmodifiable(arguments),
         startedAt: startedAt ?? DateTime.now().toUtc(),
       ) {
    emit(JobStarted(job.startedAt));
  }

  final Job job;

  final _watch = Stopwatch()..start();

  /// How long the job has been running, measured monotonically.
  ///
  /// Deliberately not `DateTime.now().difference(startedAt)`: a wall clock can
  /// step sideways mid-run and produce a negative duration, and the run log is
  /// about to keep these numbers.
  Duration get elapsed => _watch.elapsed;

  void emit(JobEvent event) {
    if (job._done.isCompleted) return;
    job._emitted.add(event);
    job._live.add(event);
  }

  /// Records what the action produced and closes the job.
  JobResult succeed(Object? value) {
    var artifacts = <Artifact>[
      if (value is Artifact) value,
      // A result whose answer is data, carrying the one file worth looking at
      // — the failing frame of a run, say. The data is still the result; these
      // only give a surface that can render a picture something to render.
      if (value is ProducesArtifacts) ...value.artifacts,
    ];
    for (var artifact in artifacts) {
      emit(JobArtifactProduced(artifact));
    }
    return _finish(
      JobResult(value: value, artifacts: artifacts, duration: elapsed),
    );
  }

  /// Records why the action did not produce anything and closes the job.
  JobResult fail(Object error, [StackTrace? stackTrace]) => _finish(
    JobResult(error: error, stackTrace: stackTrace, duration: elapsed),
  );

  JobResult? _result;

  JobResult _finish(JobResult result) {
    // Finishing twice is a caller bug, but the first outcome is the true one
    // and throwing here would replace a real failure with a confusing one.
    if (_result case var already?) return already;
    _result = result;
    emit(JobFinished(result));
    job._done.complete(result);
    unawaited(job._live.close());
    _watch.stop();
    return result;
  }
}

/// What happened to a job, and when.
///
/// Sealed and small on purpose. `JobLog` and `JobProgress` belong here the day
/// a [PluginCore] can report either — which needs a sink threaded into
/// `PluginCore.invoke` — and declaring them before anything emits them would
/// make every renderer handle a case that cannot occur.
sealed class JobEvent {
  const JobEvent();
}

class JobStarted extends JobEvent {
  const JobStarted(this.at);

  final DateTime at;
}

class JobArtifactProduced extends JobEvent {
  const JobArtifactProduced(this.artifact);

  final Artifact artifact;
}

class JobFinished extends JobEvent {
  const JobFinished(this.result);

  final JobResult result;
}

/// The outcome of a job — the whole outcome, including the unhappy one.
class JobResult {
  JobResult({
    this.value,
    this.artifacts = const [],
    this.error,
    this.stackTrace,
    required this.duration,
  });

  /// Whatever the action returned, unchanged. The CLI prints it, MCP encodes
  /// it, the GUI ignores it.
  final Object? value;

  /// Artifacts the action produced, in the order they were produced.
  ///
  /// A list although an action returns at most one today, because the interface
  /// that only ever describes what exists right now is the one that breaks when
  /// a second screenshot shows up.
  final List<Artifact> artifacts;

  final Object? error;
  final StackTrace? stackTrace;

  /// Monotonic, so it is safe to record.
  final Duration duration;

  bool get ok => error == null;
}

/// A failed job, as a line a person or a model can act on.
///
/// One function because both renderers need it and they had a copy each — and
/// the copies agreed on dropping the most useful part. `ArgumentError` keeps
/// the offending value in `invalidValue`, and "expected red or blue" without
/// "you said purple" is half an error message.
/// A failure that is a fact about the project, not a fault in flutterware.
///
/// The marker decides whether a stack is printed, and that is all it is for.
/// [FwCli] prints one for anything it does not recognise,
/// deliberately — a plugin bug has to be reportable from the surface that has
/// a terminal. But a stack is also an accusation: it names files in this
/// package, and a reader who gets one starts debugging this package.
///
/// The case that motivated it is an app whose `main` threw before `runApp`.
/// Every surface answered that with something either wrong or internal, and a
/// stack out of `RunCore` was the worst of them — it sent a consumer to debug
/// the wrong program. Nothing here is broken in that situation; their app is.
/// Implement this on the exceptions that say so.
abstract interface class ProjectFault implements Exception {}

String describeJobError(Object error) {
  if (error is! ArgumentError) return '$error';
  var named = error.name == null
      ? '${error.message}'
      : '${error.message} (${error.name})';
  // Null is what a *missing* required argument looks like, and "(entry: null)"
  // reads as though null were the problem rather than the absence.
  return error.invalidValue == null ? named : '$named: ${error.invalidValue}';
}

/// A job id: sortable by start time, unique across processes.
///
/// The shape `SessionSink.newSessionId` already uses for intercepted runs —
/// the two become one id space when the run log lands, and it would be a poor
/// joke to have arrived at that point with two conventions.
String newJobId() {
  var timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
  return '$timestamp-$pid-${_counter++}';
}

var _counter = 0;
