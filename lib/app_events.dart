/// Reporting what the app did — network calls, queries, analytics, logs.
///
/// One call, and whichever surfaces are listening pick it up: a scenario run
/// shows it on the step's Events pane, a mounted devbar shows it on its own
/// tabs. Outside both, every call is a no-op.
///
/// Separate from `flutter_test.dart` on purpose: a project's fakes and its
/// real clients report through here, and neither may import `flutter_test`.
///
/// ```dart
/// import 'package:flutterware/app_events.dart';
///
/// class FakeApi implements Api {
///   Future<User> login(String email) async {
///     recordAppEvent(
///         AppEvent.request(method: 'POST', url: '/login', status: 200));
///     return User(email);
///   }
/// }
/// ```
library;

export 'src/app_events/events.dart'
    show AppChannel, AppEvent, recordAppEvent, addAppEventListener;
