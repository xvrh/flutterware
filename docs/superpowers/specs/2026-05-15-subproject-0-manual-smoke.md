# Sub-project 0 — Manual Smoke Test

Validates the SDK wrap point against a real IDE. Run after the automated
plan tasks pass.

## Setup

1. Compile the wrap executable:
   ```sh
   cd app && dart compile exe bin/wrap.dart -o build/wrap
   ```
2. Mark the example project: write its Flutter version into a marker file:
   ```sh
   flutter --version | head -1   # note the version
   echo "<version>" > examples/example/flutter_version
   ```
3. Install the mirror facade:
   ```sh
   cd app && dart run bin/wrap.dart install \
     --sdk "$(dirname "$(dirname "$(which flutter)")")" \
     --project ../examples/example \
     --wrap-exe "$(pwd)/build/wrap"
   ```
   This creates `examples/example/flutterware/sdk/`.

## Checks

### A. CLI interception
- `cd examples/example/.. ` then run `flutterware/sdk/bin/flutter run -d macos`
  from `examples/example`.
- Expect: a `examples/example/.flutterware/sessions/<id>/` directory with
  `output.log` and `meta.json`; `meta.json` shows the injected marker.
- Expect: `examples/example/.flutterware/wrap-audit.log` has an `interesting`
  line for the run.

### B. IDE interception (IntelliJ)
- Point IntelliJ's Flutter SDK at `examples/example/flutterware/sdk`
  (a non-hidden path — IntelliJ accepts it).
- Do **not** set `FW_MARKER` in the run configuration (the wrap injects it).
- Run the example app from IntelliJ. Hot reload once. Stop.
- Expect: the running app shows `FW_MARKER: <session id>` (not `<none>`) —
  confirming the injected `--dart-define` reached `String.fromEnvironment`.
- Expect: a new `interesting` session in the audit log and a session dir.
- Expect: hot reload, stop, and the debugger still work.

### C. IDE interception (VS Code) — same as B with the Dart-Code extension.

### D. Noise latency
- Watch the audit log while the IDE is open; confirm `dart`/`flutter`
  noise invocations are classified `noise` and the IDE is not visibly slowed.

### E. Degradation
- Temporarily rename `app/build/wrap`; run `flutter run` through the mirror;
  confirm the real command still runs (degraded to plain exec).

## Result

Record pass/fail per check. A negative result (the wrap breaks an IDE
workflow, or noise is misclassified) is a valid finding that escalates to the
parent architecture.
