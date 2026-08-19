import 'dart:convert';
import 'dart:typed_data';

/// A push notification the flow's backend would have sent — what
/// `s.notification` attaches, and what a viewer draws as a banner dropped
/// over the screen it arrived on.
///
/// One class for both ends of the wire: the scenario encodes it, the panel
/// and the exported page decode it, and the schema exists in exactly one
/// place. On the wire it is an ordinary attachment whose [mimeType] says
/// what it is — a viewer that predates a field ignores it, and one that
/// predates the type altogether shows a JSON file, which is the truth.
class ScenarioNotification {
  ScenarioNotification({required this.body, this.title, this.appName});

  /// The attachment mimeType that marks a payload as one of these.
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

  /// [bytes] back as a notification, or null when they are not one — the
  /// viewer's question, asked about an attachment that merely claims the
  /// mimeType.
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
