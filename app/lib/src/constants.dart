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

/// Set by `fw capture` to mean: go here, wait until the window stops moving,
/// photograph it, exit.
///
/// A JSON object rather than one variable per option, because this grows —
/// window size and theme are the next two — and a launcher that has to learn a
/// new variable name per option is how an environment contract rots.
///
/// Here rather than beside the code that reads it, because the writer is `fw`
/// and `fw` must not import Flutter: the reader parses this into a
/// `CaptureRequest`, which owns a render tree and could never be linked into
/// the CLI. The name is the only thing both halves need.
const captureRequestKey = 'FW_CAPTURE';
