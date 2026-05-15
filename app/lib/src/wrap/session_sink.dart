import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// A filesystem-safe, reasonably unique id for one intercepted session.
String newSessionId() {
  final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  return '$ts-$pid';
}

/// The local, provisional observation sink for one interesting run.
/// Lives at `<flutterwareDir>/sessions/<sessionId>/`. Sub-project 1
/// replaces this with the daemon + SQLite DB.
class SessionSink {
  final Directory dir;

  SessionSink(Directory flutterwareDir, String sessionId)
      : dir = Directory(p.join(flutterwareDir.path, 'sessions', sessionId)) {
    dir.createSync(recursive: true);
  }

  /// Opens the captured-output file for streaming writes.
  IOSink openOutput() => File(p.join(dir.path, 'output.log')).openWrite();

  /// Writes the session metadata as pretty-printed JSON.
  void writeMeta(Map<String, Object?> meta) {
    File(p.join(dir.path, 'meta.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
  }
}
