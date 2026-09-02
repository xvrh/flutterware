/// What a scenario that ran out of time was doing, and the sentence that says
/// so.
///
/// A scenario runs under fake time, so a deadline is never slowness: the body
/// is suspended on a future nothing here will complete. The harness's timeout
/// fires in the same isolate, so there is no stack to ask for — the isolate's
/// stack *is* the timeout handler, and the body's frames live in suspended
/// continuations no API enumerates. What can be known is recorded on the way
/// in instead: which verb the body is inside and where it was called from,
/// which platform messages went out and were never seen answered and from
/// where, what the app announced through `RealWork.track`, and — the one
/// discriminating fact — whether the fake zone has microtasks queued that
/// nobody is pumping.
///
/// That last bit is the fingerprint of the case that costs the most: real
/// work *completed*, its completion was scheduled on the fake zone as a
/// microtask, and the body — suspended awaiting that very future — is the only
/// thing that could have pumped it. Zero queued microtasks means the opposite:
/// the awaited future will never complete by pumping, because it belongs to a
/// zone that is gone (an earlier scenario's) or to real time (a channel nobody
/// answers, a real-clock timer outside `s.runAsync`).
library;

import '../real_work/tracker.dart';

/// A verb the body is inside — `tap "Pay"` — and where the scenario called it.
class ScenarioVerbInFlight {
  ScenarioVerbInFlight(this.verb, this.target, this.at);

  final String verb;
  final String? target;

  /// The stack at the verb's entry; its first frame outside this package is
  /// the line of the scenario file that called it.
  final StackTrace at;

  String get label => [verb, ?target].join(' ');

  /// `test/scenarios/shop_test.dart:20`, or null when no frame outside the
  /// framework can be found. The location alone: which closure of `main`
  /// called the verb says nothing the line does not.
  String? get callSite {
    var frame = appFrames(at, max: 1).firstOrNull;
    if (frame == null) return null;
    return _location.firstMatch(frame)?.group(1) ?? frame;
  }
}

/// The verb the body is inside right now, or null between verbs.
ScenarioVerbInFlight? scenarioVerbInFlight;

/// The last verb to return — where the body was when it went on to await
/// something of its own.
ScenarioVerbInFlight? scenarioLastVerb;

/// A platform message this scenario sent whose reply the body has not seen.
class PendingSend {
  PendingSend(this.title, this.at);

  /// `flutter/assets assets/model.glb`, `dev.fluttercommunity.plus/x get`.
  final String title;

  /// The stack at the send — the app's own frames are what says *which* load
  /// this was.
  final StackTrace at;
}

/// Bounded: a scenario that sends hundreds of messages a step keeps the last
/// few dozen, which is plenty for a diagnosis and nothing for memory.
const _pendingSendCap = 64;

final _pendingSends = <int, PendingSend>{};
var _sendToken = 0;

/// Records a send, returning the token [sendAnswered] takes back.
int recordPendingSend(String title) {
  var token = ++_sendToken;
  _pendingSends[token] = PendingSend(title, StackTrace.current);
  if (_pendingSends.length > _pendingSendCap) {
    _pendingSends.remove(_pendingSends.keys.first);
  }
  return token;
}

/// The reply reached the sender's zone — which, under fake time, means a pump
/// ran. A reply whose delivery is still a queued fake microtask stays pending,
/// and that is the point: from the suspended body's side it *is*.
void sendAnswered(int token) => _pendingSends.remove(token);

/// The sends nobody has seen answered, oldest first.
List<PendingSend> get pendingSends => _pendingSends.values.toList();

/// Forgets what an earlier scenario was doing. Called as each begins.
void resetStallFacts() {
  _pendingSends.clear();
  scenarioVerbInFlight = null;
  scenarioLastVerb = null;
}

/// Frames of [trace] that belong to the scenario or the app, oldest call
/// last, as `Owner.member (package:app/file.dart:12)`.
///
/// Everything the framework and the test machinery contribute is dropped: a
/// stack from inside a verb is thirty frames of `flutter_test` before the
/// first line anyone wrote. Third-party packages stay — the load that never
/// landed is usually theirs.
List<String> appFrames(StackTrace trace, {int max = 6}) {
  var kept = <String>[];
  for (var line in '$trace'.split('\n')) {
    var match = _frame.firstMatch(line);
    if (match == null) continue;
    var member = match.group(1)!;
    var location = match.group(2)!;
    if (_framework.any(location.startsWith)) continue;
    // `file:///Users/…/test/scenarios/shop_test.dart:20:7` reads better as
    // the part after the package root, and the column says nothing.
    var parts = _lineAndColumn.firstMatch(location);
    var path = parts?.group(1) ?? location;
    var lineNumber = parts?.group(2);
    var uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      var segments = uri.pathSegments;
      var test = segments.indexOf('test');
      if (test >= 0) path = segments.sublist(test).join('/');
    }
    kept.add('$member ($path${lineNumber == null ? '' : ':$lineNumber'})');
    if (kept.length >= max) break;
  }
  return kept;
}

final _frame = RegExp(r'^#\d+\s+(.+?) \((.+)\)$');

/// `…/file.dart:20:7` → the path and the line; the column is dropped.
final _lineAndColumn = RegExp(r'^(.*?):(\d+)(?::\d+)?$');

/// The parenthesised location at the end of a frame [appFrames] produced.
final _location = RegExp(r'\(([^()]+)\)$');

const _framework = [
  'dart:',
  'package:flutter/',
  'package:flutter_test/',
  'package:flutterware/',
  'package:test_api/',
  'package:test_core/',
  'package:test/',
  'package:stack_trace/',
  'package:fake_async/',
  'package:async/',
  'package:stream_channel/',
  'package:matcher/',
  'package:clock/',
];

/// The sentence a scenario gets for running out its [deadline].
///
/// [watchdog] is what the `runAsync` watchdog already said, when it said
/// anything — that diagnosis is complete on its own. [microtasks] is the fake
/// zone's queue length at the deadline, or null where it could not be read.
/// [previousScenario] is what ran before this one in the same process, since
/// a future created in *its* fake zone is the usual thing a body waits on
/// forever.
String stallDiagnosis({
  required Duration deadline,
  String? watchdog,
  int? microtasks,
  ScenarioVerbInFlight? inFlight,
  ScenarioVerbInFlight? lastVerb,
  List<PendingSend> sends = const [],
  List<TrackedRealWork> tracked = const [],
  int pendingImages = 0,
  String? previousScenario,
  bool eventsOnFailedStep = false,
}) {
  var seconds = deadline.inSeconds > 0
      ? '${deadline.inSeconds}s'
      : '${deadline.inMilliseconds}ms';
  var opening =
      'the scenario did not finish within $seconds. A scenario runs under '
      'fake time, so this is not slowness — '
      '${watchdog ?? _where(inFlight, lastVerb)}';
  var lines = <String>[opening];
  if (watchdog == null) {
    lines.add(_mechanism(microtasks, previousScenario));
  }
  for (var send in sends) {
    var frames = appFrames(send.at);
    lines.add(
      'Sent and never seen answered: ${send.title}'
      '${frames.isEmpty ? '' : ', from ${frames.join(' ← ')}'}.',
    );
  }
  for (var work in tracked) {
    var frames = switch (work.announcedAt) {
      var at? => appFrames(at),
      null => const <String>[],
    };
    lines.add(
      'Tracked real work still pending: `$work`'
      '${frames.isEmpty ? '' : ', announced from ${frames.join(' ← ')}'}.',
    );
  }
  if (pendingImages > 0) {
    lines.add(
      '$pendingImages image decode${pendingImages == 1 ? '' : 's'} still '
      'pending.',
    );
  }
  lines.add(
    'The steps it captured before it stopped are on disk'
    '${eventsOnFailedStep ? ', and what the app printed and did since the last of them is on the failed step (`scenarios read --events`)' : ''}. '
    'Give it longer, or opt out, with `scenario(timeout: …)`.',
  );
  return lines.join(' ');
}

String _where(ScenarioVerbInFlight? inFlight, ScenarioVerbInFlight? lastVerb) {
  if (inFlight != null) {
    var site = inFlight.callSite;
    return 'it was inside `s.${inFlight.label}`'
        '${site == null ? '' : ', called from $site'}, waiting on a future '
        'no pump can complete.';
  }
  if (lastVerb != null) {
    var site = lastVerb.callSite;
    return 'it was between verbs: `s.${lastVerb.label}`'
        '${site == null ? '' : ' ($site)'} had returned, and whatever the '
        'body awaited next never completed.';
  }
  return 'the body was waiting on a real future no pump can complete before '
      'its first verb.';
}

String _mechanism(int? microtasks, String? previousScenario) {
  if (microtasks == null) {
    return "The usual causes: a future created in an earlier scenario's fake "
        'zone, or work that needs the real clock — a platform channel nobody '
        'answers, a real-clock timer outside `s.runAsync`.';
  }
  if (microtasks > 0) {
    return '$microtasks microtask${microtasks == 1 ? ' is' : 's are'} queued '
        "in this scenario's fake zone with nothing pumping: real work "
        'completed and its continuation is waiting for a pump the suspended '
        'body cannot run. Hand that work to `RealWork.track` '
        '(`package:flutterware/real_work.dart`) so the next verb lands it, '
        'or await it with a pump — `while (!done) { await s.tester.pump(); }` '
        '— never bare, and never inside `s.runAsync`.';
  }
  var earlier = previousScenario == null
      ? "an earlier scenario's fake zone"
      : "an earlier scenario's fake zone — `$previousScenario` ran before "
            'this one in the same process';
  return 'Nothing is queued in the fake zone, so the body is waiting on a '
      'future no pump would complete: one created in $earlier, which a '
      'process-wide cache or a static `Future` hands to every scenario after '
      'it — or work that needs the real clock: a platform channel nobody '
      'answers, a real-clock timer outside `s.runAsync`. To reproduce the '
      'first, run the two files together in order: '
      '`--file=<earlier>,<this>`.';
}
