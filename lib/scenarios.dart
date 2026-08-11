/// Reporting what the app does while a scenario runs — the transition events
/// the panel shows between two screens.
///
/// Separate from `flutter_test.dart` on purpose: a project's fakes report
/// through here, and a fake that lives in `lib/` must not import
/// `flutter_test`. Outside a scenario run every call is a no-op.
///
/// ```dart
/// import 'package:flutterware/scenarios.dart';
///
/// class FakeApi implements Api {
///   Future<User> login(String email) async {
///     recordScenarioEvent(
///         ScenarioEvent.request(method: 'POST', url: '/login', status: 200));
///     return User(email);
///   }
/// }
/// ```
library;

export 'src/scenarios/events.dart'
    show ScenarioChannel, ScenarioEvent, recordScenarioEvent;
