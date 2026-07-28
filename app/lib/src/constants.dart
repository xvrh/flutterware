// The launcher's half of the contract — what `bin/flutterware.dart` puts in
// the environment for this process to read. Re-exported rather than imported
// at each use site, matching `utils/list_files.dart`: the names have to be
// written once or the two packages can disagree about them.
export 'package:flutterware/src/constants.dart';

const projectDefineKey = 'FW_PROJECT_PATH';
const appToolPathKey = 'FW_APP_TOOL_PATH';
const flutterSdkDefineKey = 'FW_FLUTTER_SDK_PATH';
const remoteLoggerUrlKey = 'FW_REMOTE_LOGGER_URL';
