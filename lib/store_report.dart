/// What a store export wrote to disk, typed.
///
/// See `src/store/report.dart` for the whole of it. Separate from
/// `package:flutterware/store.dart` — which carries the frame widget and
/// therefore Flutter — because a script that reads an export runs under a bare
/// `dart run`. The same split `scenarios_report.dart` makes against
/// `flutter_test.dart`.
library;

export 'src/store/report.dart';
