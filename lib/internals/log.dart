
import 'dart:convert';

class Log {
  final String message;
  final int level;

  Log(this.message, this.level);

  factory Log.fromJson(Map<String, dynamic> json) {
    return Log(json['message'] as String, json['level'] as int);
  }

  Map<String, dynamic> toJson() => {
    'message': message,
    'level': level,
  };

  String toJsonString() => jsonEncode(this);

  static Log? tryParse(String input) {
    const flutterPrefix = 'flutter: ';
    if (input.startsWith(flutterPrefix)) {
      input = input.substring(flutterPrefix.length);
    }

    if (input.startsWith('{')) {
      try {
        var decoded = jsonDecode(input) as Map<String, dynamic>;
        return Log.fromJson(decoded);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}