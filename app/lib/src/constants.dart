// The launcher's half of the contract — what `bin/flutterware.dart` puts in
// the environment for this process to read. Re-exported rather than imported
// at each use site, matching `utils/list_files.dart`: the names have to be
// written once or the two packages can disagree about them.
export 'package:flutterware/src/constants.dart';
// The GUI half of the same contract: where the built binary is, and whether
// the launcher already built it.
// ignore: implementation_imports
export 'package:flutterware/src/desktop_gui.dart'
    show guiBuildResultEnvironmentKey;

const projectDefineKey = 'FW_PROJECT_PATH';
const appToolPathKey = 'FW_APP_TOOL_PATH';
const flutterSdkDefineKey = 'FW_FLUTTER_SDK_PATH';
