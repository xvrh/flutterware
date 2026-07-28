const dartExecutableEnvironmentKey = 'DART_EXECUTABLE_PATH';
const appPathEnvironmentKey = 'APP_TOOL_PATH';
const remoteLoggerServerUrlKey = 'REMOTE_LOGGER_URL';
const forceCompileOption = 'force-compile';

/// Set by the launcher when `app/` is the checkout being edited rather than a
/// copy under `~/.flutterware`.
///
/// It is the launcher's `_inPubCache` answer, passed on rather than derived a
/// second time — the process that decided where to run is the one that knows.
const editableSourcesEnvironmentKey = 'FW_EDITABLE_SOURCES';
