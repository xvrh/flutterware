/// The live half of the verb engine: scenarios' vocabulary executed against a
/// running app's real binding. For generated entrypoints and the guest
/// runtime, not for projects to import directly — a project's own tests want
/// `package:flutterware/flutter_test.dart`.
library;

export 'src/drive/drive.dart' show Drive, DriveStep;
export 'src/drive/live_settle.dart' show LiveSettleResult, settleLive;
export 'src/drive/resolve.dart'
    show TargetError, TargetFailure, TargetMessages, visibleTextsOf;
export 'src/scenarios/target.dart' show Target;
