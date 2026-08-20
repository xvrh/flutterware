import 'dart:convert';
import 'dart:typed_data';

/// A push notification the flow's backend would have sent — what
/// `s.notification` records, and what a viewer draws as a banner over the
/// screen it landed on.
///
/// One class for both ends of the wire: the scenario writes it, the panel and
/// the exported page read it, and the schema exists in exactly one place. It
/// rides the step **inline** — three short strings, typed on both ends, so
/// there is no file to fetch and nothing to decode before a banner can be
/// drawn.
///
/// [encode] and [decode] serve the standalone lane, where a bare
/// `flutter test` with a destination writes each beat as a file rather than a
/// report.
class ScenarioNotification {
  ScenarioNotification({required this.body, this.title, this.appName});

  /// What the standalone lane's `.notification.json` is, for a reader that
  /// wants to say so.
  static const mimeType = 'application/x-notification+json';

  /// The notification's message — the one line a banner always has.
  final String body;

  /// The bold first line, when the sender set one.
  final String? title;

  /// Who sent it, as the banner names the app. A viewer that knows the
  /// project supplies its own default — the project itself.
  final String? appName;

  Uint8List encode() => utf8.encode(
    jsonEncode({'body': body, 'title': ?title, 'appName': ?appName}),
  );

  /// [bytes] back as a notification, or null when they are not one.
  static ScenarioNotification? decode(List<int> bytes) {
    try {
      var decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['body'] is! String) return null;
      return ScenarioNotification(
        body: decoded['body'] as String,
        title: decoded['title'] as String?,
        appName: decoded['appName'] as String?,
      );
    } on FormatException {
      return null;
    }
  }
}
