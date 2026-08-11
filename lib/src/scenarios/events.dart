/// What the app did between two captured steps — the transition's contents.
///
/// Deliberately free of every Flutter import: a project's fakes report through
/// [recordScenarioEvent], and a fake that lives in `lib/` must not drag
/// `flutter_test` into production code. Design:
/// `docs/superpowers/specs/2026-08-11-scenario-transition-events.md`.
library;

/// The channel an event travelled on — what the panel filters and groups by.
///
/// A fixed vocabulary for the kinds that earn a rendering of their own, plus
/// whatever a [ScenarioEvent.custom] names. Strings rather than an enum
/// because the set is open at the far end and every surface serialises it.
abstract final class ScenarioChannel {
  /// An HTTP request, however the app made it.
  static const network = 'network';

  /// A database statement.
  static const db = 'db';

  /// A product analytics event.
  static const analytics = 'analytics';

  /// A `package:logging` record, or anything else log-shaped.
  static const log = 'log';

  /// A `print` or `debugPrint` from the app.
  static const print = 'print';

  /// A platform channel message — a plugin talking to its host.
  static const platform = 'platform';

  /// A framework channel (`flutter/…`). Captured, because "did the app ask for
  /// the keyboard" is a real question, and hidden by default, because on an
  /// ordinary transition it is the only thing you would see.
  static const system = 'system';
}

/// One thing that happened on the way from one step to the next.
class ScenarioEvent {
  const ScenarioEvent.custom({
    required this.channel,
    required this.title,
    this.detail,
    this.data = const {},
    this.body,
    this.error = false,
    this.level,
  });

  /// An HTTP request: `POST /login → 401`.
  ScenarioEvent.request({
    required String method,
    required String url,
    int? status,
    this.data = const {},
    this.body,
  }) : channel = ScenarioChannel.network,
       title = '$method $url',
       detail = status?.toString(),
       error = status != null && status >= 400,
       level = null;

  /// A database statement, with the SQL as the body so it can be read whole.
  ScenarioEvent.query({
    required String sql,
    List<Object?> args = const [],
    int? rows,
  }) : channel = ScenarioChannel.db,
       title = _firstLine(sql),
       detail = rows == null ? null : '$rows ${rows == 1 ? 'row' : 'rows'}',
       data = args.isEmpty ? const {} : {'args': args},
       body = sql,
       error = false,
       level = null;

  /// A product analytics event and its parameters.
  ScenarioEvent.analytics(String name, {Map<String, Object?> params = const {}})
    : channel = ScenarioChannel.analytics,
      title = name,
      detail = null,
      data = params,
      body = null,
      error = false,
      level = null;

  /// A log line.
  ScenarioEvent.log(String message, {this.level, String? logger})
    : channel = ScenarioChannel.log,
      title = message,
      detail = logger,
      data = const {},
      body = null,
      error = level == 'SEVERE' || level == 'SHOUT';

  /// One of [ScenarioChannel]'s constants, or a name of the reporter's own.
  final String channel;

  /// The one-line summary — what the list shows, and what an agent reads.
  final String title;

  /// Trailing detail beside the title: a status code, a row count, a logger
  /// name. Null where the title says everything.
  final String? detail;

  /// The structured payload, shown when a row is expanded.
  final Map<String, Object?> data;

  /// Long text — a SQL statement, a JSON body, a stack. Kept apart from [data]
  /// because it is rendered as text rather than as fields.
  final String? body;

  /// Whether this event is itself a problem: a 4xx/5xx, a severe log, a
  /// channel call that came back an error. Tints the row; never fails a step.
  final bool error;

  /// The log level, for [ScenarioChannel.log] events.
  final String? level;

  Map<String, Object?> toJson() => {
    'channel': channel,
    'title': _cap(title, _maxTitleChars),
    'detail': ?detail,
    if (data.isNotEmpty) 'data': _capData(data),
    if (body != null) 'body': _cap(body!, _maxBodyChars),
    if (error) 'error': true,
    'level': ?level,
  };

  static String _firstLine(String text) {
    var trimmed = text.trim();
    var end = trimmed.indexOf('\n');
    return end < 0 ? trimmed : '${trimmed.substring(0, end)} …';
  }
}

/// Per-event caps. An app that logs in a build method would otherwise write a
/// run measured in tens of megabytes; every one of these leaves a marker
/// rather than truncating quietly.
const _maxTitleChars = 300;
const _maxBodyChars = 4000;
const _maxDataChars = 4000;

/// How many events one transition keeps, and how many one **scenario** keeps
/// in total — the buffer lives for exactly one scenario, so the second is the
/// ceiling across all of its steps, replays included.
const maxScenarioEventsPerStep = 200;
const maxScenarioEventsPerRun = 5000;

String _cap(String text, int limit) => text.length <= limit
    ? text
    : '${text.substring(0, limit)}… (${text.length - limit} more characters)';

Object? _capData(Map<String, Object?> data) {
  var text = data.toString();
  if (text.length <= _maxDataChars) return data;
  return {'truncated': _cap(text, _maxDataChars)};
}

/// Records [event] on the scenario's current transition.
///
/// A no-op — one null check — when nothing is capturing, which is every bare
/// `flutter test` run. That is what makes it safe for a project to leave these
/// calls in its shared fakes forever.
///
/// ```dart
/// class FakeApi implements Api {
///   Future<User> login(String email) async {
///     recordScenarioEvent(ScenarioEvent.request(
///         method: 'POST', url: '/login', status: 200));
///     return User(email);
///   }
/// }
/// ```
void recordScenarioEvent(ScenarioEvent event) =>
    scenarioEventBuffer?.add(event);

/// Set by the harness for the duration of one scenario run; null everywhere
/// else. The seam between the reporting API and the runner, like
/// `scenarioRunListener` — not part of the authoring surface.
ScenarioEventBuffer? scenarioEventBuffer;

/// What has been recorded since the last capture.
///
/// The design's central mechanic: whatever is in here when a step captures is
/// what happened on the way to it.
class ScenarioEventBuffer {
  final _events = <ScenarioEvent>[];

  /// Dropped since the last drain, and over the whole run — reported on the
  /// step, because silence would read as "the app did nothing".
  var _dropped = 0;
  var _total = 0;

  void add(ScenarioEvent event) {
    if (_events.length >= maxScenarioEventsPerStep ||
        _total >= maxScenarioEventsPerRun) {
      _dropped++;
      return;
    }
    _total++;
    _events.add(event);
  }

  /// The transition's events, and how many were dropped to stay inside the
  /// caps. Empties the buffer.
  (List<ScenarioEvent>, int) drain() {
    var drained = (List.of(_events), _dropped);
    _events.clear();
    _dropped = 0;
    return drained;
  }

  /// Throws the buffer away without reporting it — a `split` replay walking a
  /// prefix that was captured on an earlier path. Its events were recorded the
  /// first time through; recording them again would multiply them per branch.
  void discard() {
    _events.clear();
    _dropped = 0;
  }
}
