/// What the app did — one report, and whichever surfaces are listening.
///
/// The app calls [recordAppEvent] once. A scenario run reads it off
/// [appEventBuffer] and shows it on the step's Events pane; a mounted devbar
/// reads it off [addAppEventListener] and shows it on its own tabs. Neither
/// is wired by the project, and neither knows about the other.
///
/// Deliberately free of every Flutter import: a project's fakes report through
/// [recordAppEvent], and a fake that lives in `lib/` must not drag
/// `flutter_test` into production code. That is also why the devbar registers
/// *into* here rather than being called from here. Design:
/// `docs/superpowers/specs/2026-08-11-scenario-transition-events.md` for the
/// model and the lanes, `2026-08-21-app-events-unification.md` for the
/// fan-out.
library;

import 'dart:async';

/// The channel an event travelled on — what the panel filters and groups by.
///
/// A fixed vocabulary for the kinds that earn a rendering of their own, plus
/// whatever a [AppEvent.custom] names. Strings rather than an enum
/// because the set is open at the far end and every surface serialises it.
abstract final class AppChannel {
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
class AppEvent {
  const AppEvent.custom({
    required this.channel,
    required this.title,
    this.detail,
    this.data = const {},
    this.body,
    this.error = false,
    this.level,
  });

  /// An HTTP request: `POST /login → 401`.
  AppEvent.request({
    required String method,
    required String url,
    int? status,
    this.data = const {},
    this.body,
  }) : channel = AppChannel.network,
       title = '$method $url',
       detail = status?.toString(),
       error = status != null && status >= 400,
       level = null;

  /// A database statement, with the SQL as the body so it can be read whole.
  AppEvent.query({
    required String sql,
    List<Object?> args = const [],
    int? rows,
  }) : channel = AppChannel.db,
       title = _firstLine(sql),
       detail = rows == null ? null : '$rows ${rows == 1 ? 'row' : 'rows'}',
       data = args.isEmpty ? const {} : {'args': args},
       body = sql,
       error = false,
       level = null;

  /// A product analytics event and its parameters.
  AppEvent.analytics(String name, {Map<String, Object?> params = const {}})
    : channel = AppChannel.analytics,
      title = name,
      detail = null,
      data = params,
      body = null,
      error = false,
      level = null;

  /// A log line.
  AppEvent.log(String message, {this.level, String? logger})
    : channel = AppChannel.log,
      title = message,
      detail = logger,
      data = const {},
      body = null,
      error = level == 'SEVERE' || level == 'SHOUT';

  /// Decodes what [toJson] wrote — an entry of a step's `.events.json`.
  ///
  /// Lenient like every published reader here: an event a fake reported with
  /// a channel of its own still decodes, and a field this version does not
  /// know is ignored. The caps [toJson] applies are already in the text, so a
  /// round-tripped title reads exactly as the panel showed it.
  factory AppEvent.fromJson(Map<String, Object?> json) => AppEvent.custom(
    channel: json['channel'] as String? ?? '',
    title: json['title'] as String? ?? '',
    detail: json['detail'] as String?,
    data: switch (json['data']) {
      Map data => data.cast<String, Object?>(),
      _ => const {},
    },
    body: json['body'] as String?,
    error: json['error'] == true,
    level: json['level'] as String?,
  );

  /// One of [AppChannel]'s constants, or a name of the reporter's own.
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

  /// The log level, for [AppChannel.log] events.
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
const maxAppEventsPerStep = 200;
const maxAppEventsPerRun = 5000;

String _cap(String text, int limit) => text.length <= limit
    ? text
    : '${text.substring(0, limit)}… (${text.length - limit} more characters)';

Object? _capData(Map<String, Object?> data) {
  var text = data.toString();
  if (text.length <= _maxDataChars) return data;
  return {'truncated': _cap(text, _maxDataChars)};
}

/// Reports [event] to every surface that is listening.
///
/// Inside a scenario it lands on the current transition, and the step's Events
/// pane shows it. Inside a running app it lands on a mounted devbar's tabs.
/// Both at once, if both are there; neither is wired by the project.
///
/// A no-op — one null check and an empty list — when nothing is listening,
/// which is every bare `flutter test` run. That is what makes it safe for a
/// project to leave these calls in its shared fakes forever, and it holds all
/// the way: a listener that throws is reported to the [Zone] and skipped
/// rather than surfacing here, and one that unregisters itself mid-report
/// costs its neighbours nothing.
///
/// ```dart
/// class FakeApi implements Api {
///   Future<User> login(String email) async {
///     recordAppEvent(AppEvent.request(
///         method: 'POST', url: '/login', status: 200));
///     return User(email);
///   }
/// }
/// ```
///
/// [source] names the reporter, for the one case where a surface has already
/// been handed this event by another route: a listener registered with a
/// matching `ignoreSource` skips it. Everybody else — the buffer, and every
/// other listener — sees it normally. See [addAppEventListener].
void recordAppEvent(AppEvent event, {Object? source}) {
  appEventBuffer?.add(event);
  if (_listeners.isEmpty) return;
  // Over a copy, and never over the live list. A listener that unregisters on
  // its way out — a devbar disposing mid-report — shifts everything behind it
  // down a slot, so a walk by index silently *skips* its neighbour and a
  // for-in throws a concurrent modification. Neither is acceptable: the whole
  // promise of this call is that reporting cannot disturb the app.
  for (var registration in List.of(_listeners)) {
    if (source != null && registration.ignoreSource == source) continue;
    try {
      registration.listener(event);
    } on Object catch (e, stack) {
      // A surface that breaks may not take the app's own call with it — this
      // is a line in somebody's fake, not a place to fail. Loud, but not here:
      // the zone reports it the way an unhandled async error is reported.
      Zone.current.handleUncaughtError(e, stack);
    }
  }
}

/// Set by the harness for the duration of one scenario run; null everywhere
/// else. The seam between the reporting API and the runner, like
/// `scenarioRunListener` — not part of the authoring surface.
AppEventBuffer? appEventBuffer;

final _listeners = <_Registration>[];

class _Registration {
  _Registration(this.listener, this.ignoreSource);

  final void Function(AppEvent) listener;
  final Object? ignoreSource;
}

/// Subscribes [listener] to every event reported from now on, and returns the
/// call that unsubscribes it.
///
/// The seam a live surface uses, where a scenario run uses [appEventBuffer].
/// A devbar registers one while it is mounted; a project can register its own.
///
/// Pass [ignoreSource] to skip events a particular reporter tagged, for a
/// surface that reporter already handed a copy to directly. That is how a
/// devbar avoids listing a `DevbarHttpClient` request twice — it is given the
/// exchange in two halves as it happens, so it ignores the one-piece report
/// the same client makes for everybody else.
///
/// A listener that throws is reported to the current [Zone] and skipped; it
/// never reaches the app code that called [recordAppEvent].
///
/// Applies no cap of its own — a live surface keeps whatever history it wants,
/// and the devbar's tabs already bound theirs.
void Function() addAppEventListener(
  void Function(AppEvent) listener, {
  Object? ignoreSource,
}) {
  var registration = _Registration(listener, ignoreSource);
  _listeners.add(registration);
  return () => _listeners.remove(registration);
}

/// What has been recorded since the last capture.
///
/// The design's central mechanic: whatever is in here when a step captures is
/// what happened on the way to it.
class AppEventBuffer {
  final _events = <AppEvent>[];

  /// Dropped since the last drain, and over the whole run — reported on the
  /// step, because silence would read as "the app did nothing".
  var _dropped = 0;
  var _total = 0;

  void add(AppEvent event) {
    if (_events.length >= maxAppEventsPerStep || _total >= maxAppEventsPerRun) {
      _dropped++;
      return;
    }
    _total++;
    _events.add(event);
  }

  /// The transition's events, and how many were dropped to stay inside the
  /// caps. Empties the buffer.
  (List<AppEvent>, int) drain() {
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
