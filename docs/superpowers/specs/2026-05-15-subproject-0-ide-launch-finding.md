# Sub-project 0 — IDE Launch Finding (Phase A spike)

**Date:** 2026-05-15
**Status:** Empirical finding. Produced by the Phase A diagnostic spike described
in `2026-05-15-subproject-0-sdk-wrap-point.md`. This resolves the open risk that
threatened the parent architecture.

## What was done

A throwaway diagnostic wrapper was placed around a real Flutter SDK:

- A full SDK *mirror* at `~/flutterware-spike/sdk/` — every SDK entry symlinked
  to the pristine SDK (`/Users/xavier/flutter`) except `bin/flutter` and
  `bin/dart`, which are shim scripts.
- The shims call `spike-wrap.sh`, which logs the full argv, the process
  environment, and a tee of stdin/stdout, then runs the real binary.

IntelliJ's Flutter SDK path was pointed at the mirror. A `--dart-define` was
added to the run configuration (`--dart-define=FW_MARKER=spike123`). The example
app (`examples/example`) was launched from IntelliJ, hot-reloaded once, stopped.

## What IntelliJ actually did

IntelliJ accepted the mirror SDK without complaint. It ran `flutter --no-color
--version` three times to validate the SDK, then launched the run as a single
direct invocation:

```
flutter --no-color run --machine --track-widget-creation --device-id=macos \
  --start-paused --dart-define=FW_MARKER=spike123 \
  --dart-define=flutter.inspector.structuredErrors=true \
  --devtools-server-address=http://127.0.0.1:9101 lib/main.dart
```

The run process had piped (non-TTY) stdin and stdout. Over those pipes IntelliJ
drove the session with daemon-protocol JSON-RPC — e.g.
`app.callServiceExtension` calls for the inspector. Hot reload spawned **no new
process**; it flowed over the existing run process's pipe.

## Findings

1. **IntelliJ launches runs as a direct `flutter run --machine`** — not via a
   separate, long-lived `flutter daemon` process. The feared branch (an IDE
   daemon that receives launch parameters over JSON-RPC *after* start) did not
   occur.

2. **`--dart-define` values are passed in plain argv at launch.** Both the
   user's define (`FW_MARKER=spike123`) and IntelliJ's own
   (`flutter.inspector.structuredErrors=true`) appear as ordinary `argv`
   entries. Injecting an additional `--dart-define` therefore requires only an
   **argv rewrite** — no protocol-aware proxy, no JSON-RPC splicing.

3. **`--machine` is a control channel, not a config channel.** It makes
   `flutter run` speak the daemon JSON-RPC protocol over its own stdin/stdout so
   the IDE can drive hot reload, service extensions, and stop. That traffic
   carries *no* dart-defines — defines are fixed at launch in argv. The wrap can
   tee this traffic verbatim; it never needs to parse it.

4. **IDE runs use pipes, not a PTY.** The heavy path for an IDE/`--machine` run
   is a plain bidirectional pipe passthrough. The phase-1 `runUnderPty` is only
   needed for an interactive CLI `flutter run` in a real terminal.

5. **The mirror facade is accepted by IntelliJ** when placed at a non-hidden
   path. IntelliJ rejects SDK paths containing a hidden (dot-prefixed) directory
   component — confirmed from prior experience and accounted for in the mirror
   location decision below.

6. **dart-define is not an environment variable.** It was confirmed absent from
   the process environment. A compiled Flutter app on a device cannot receive
   host environment variables; `--dart-define` (read via
   `String.fromEnvironment`) is the only host→app launch-config channel. The
   parent architecture's "inject an env var (the channel address)" framing is
   wrong for mobile targets and must become "inject a `--dart-define`".

## Caveats

- One IntelliJ version, macOS host, desktop (`macos`) device. Behaviour could
  differ on older IntelliJ, other platforms, or other device types.
- IntelliJ may still spawn a `flutter daemon` for device discovery; none was
  observed in the capture window. Such a daemon launches no app, so it is
  harmless noise even if present.
- The marker reaching the *running app* via `String.fromEnvironment` was not
  verified here (the probe app is a Phase B deliverable). It is verifiable in
  principle: the define is present in the real `flutter run` argv, which is the
  ordinary, supported way dart-defines reach an app.

## Decisions this resolves

- **No daemon JSON-RPC proxy.** All three launch paths (CLI `flutter run`,
  VS Code `flutter run --machine`, IntelliJ `flutter run --machine`) carry
  dart-defines in argv. The heavy path is: argv rewrite + transport passthrough.
- **Two transport modes for the heavy path:** PTY passthrough for an interactive
  terminal run; plain pipe passthrough for a `--machine` run. Both are dumb tees
  — neither parses the stream.
- **Mirror location is non-hidden.** The SDK mirror lives at a non-hidden,
  IDE-referenced path (`<project>/flutterware/sdk/`). The audit log and session
  sink — not referenced by any IDE config — stay under `<project>/.flutterware/`.
