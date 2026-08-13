const dartExecutableEnvironmentKey = 'DART_EXECUTABLE_PATH';
const appPathEnvironmentKey = 'APP_TOOL_PATH';
const forceCompileOption = 'force-compile';

/// What `fw --version` answers, and what the MCP server announces as its
/// implementation version.
///
/// Here rather than read off `pubspec.yaml` at run time because the CLI is a
/// compiled binary that may be running from a copy under `~/.flutterware`, and
/// a version read from whichever pubspec happens to sit beside it is a version
/// that can be wrong. Compiled in, it is a fact about the build.
///
/// `test/version_test.dart` fails if this and the two pubspecs disagree.
const flutterwareVersion = '0.5.2';

/// Set by the global `fw` when it forwards to a project, carrying its own
/// version across the exec.
///
/// The walker is installed once and never refreshed while the package it runs
/// comes from the project, so the two can be far apart — which is exactly the
/// question `fw --version` exists to answer. Nothing else needs it, and a `fw`
/// too old to set it simply reports one version instead of two.
const walkerVersionEnvironmentKey = 'FW_WALKER_VERSION';

/// Set by the launcher when `app/` is the checkout being edited rather than a
/// copy under `~/.flutterware`.
///
/// It is the launcher's `_inPubCache` answer, passed on rather than derived a
/// second time — the process that decided where to run is the one that knows.
const editableSourcesEnvironmentKey = 'FW_EDITABLE_SOURCES';
