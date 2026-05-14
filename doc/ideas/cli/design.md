# Flutterware — design notes

Forward-looking design doc for the `fw` tooling. The bash bits (`bin/fw`,
`tool/fw`) are landed and being dogfooded; everything past "What's landed
today" is roadmap, captured here so we don't lose the thinking.

This document is meant to evolve. Where decisions are tentative, they are
marked **[OPEN]** with the alternatives we considered.

---

## 1. What problem we're solving

A developer-and-AI-friendly tool that:

1. Replaces fvm with a project-pinned, breaking-change-tolerant version
   manager (this is the part that's landed).
2. Wraps Flutter / Dart processes transparently, so every command run in
   the project can be observed, recorded, and orchestrated by a GUI.
3. Provides a side-channel for cooperating processes (e.g. `server_local.dart`)
   to negotiate richer interactions with that GUI.
4. Lets the team add high-level shortcuts (`fw open admin`) and project-wide
   behavior tweaks (auto `--dart-define`, IDE interception) without each
   developer rolling their own.

Audience for the resulting tool: humans at terminals, humans in IDEs, and
AI agents — all benefit from the same observability and the same shortcuts.

---

## 2. What's landed today (May 2026)

- `bin/fw` — frozen shell shim. Walks up from `$PWD` looking for `tool/fw`,
  errors if not found or not executable.
- `tool/fw` — bash dispatcher. Built-ins: `install`, `flutter`, `dart`,
  `doctor`, `help`. Anything else is forwarded to a (currently absent)
  binary at `.dart_tool/flutterware/bin/fw`.
- `fw install` — clones Flutter at the version pinned in `.fvmrc` into
  `~/.cache/flutter/<version>`, runs `flutter precache`, symlinks
  `<root>/.fvm/flutter_sdk` to the cache. Cross-runner concurrency-safe
  (per-version mkdir mutex, atomic publish via tempdir + rename).
- `fw flutter` / `fw dart` auto-symlink on cache hit; error on cache miss.

Migration plan: solo dogfood → quiet team availability → CI parallel →
flip CLAUDE.md/README. Coexists with real `fvm` indefinitely.

---

## 3. Architecture: bash dispatcher + Dart helper

The bash script stays small and handles everything that must work
*before* the Dart SDK exists:

| Command | Owner | Why |
|---|---|---|
| `install` | bash | Has to clone Flutter from scratch; can't rely on Dart |
| `doctor` | bash | Diagnostic for the bootstrap state |
| `help` | bash | No-op listing |
| `flutter` / `dart` | **helper** | Goes through the supervisor for tee + registry + control socket |
| anything else | **helper** | Shortcuts, custom commands, project glue |

The "helper" is a Dart binary, AOT-compiled at install time, written
once and reused. It lives in a separate Dart package owned by the
flutterware repo (see §10).

```
fw <cmd>
└── tool/fw (bash dispatcher)
    ├── install/doctor/help → bash
    └── flutter/dart/<other> → exec .dart_tool/flutterware/bin/fw <cmd> "$@"
```

The bash dispatcher is the only piece distributed by the project itself.
It's frozen — no version changes, no features. All evolution happens
inside the helper.

---

## 4. Process supervision (the supervisor)

The headline behavior. When `fw flutter run -d chrome` is invoked, the
helper:

1. Resolves the real `flutter` binary from `.fvm/flutter_sdk/bin/flutter`.
2. Applies project-defined transformations (shortcut expansion, `--dart-define`
   injection). Prints a one-line notice when it changes the args.
3. Allocates a `run_id` (ULID).
4. Writes a registry entry (see §6).
5. Spawns the child under a **PTY** — child sees a real TTY.
6. Forwards stdin → child stdin, child stdout/stderr → user's terminal.
7. Tees the same bytes into a log file and any connected GUI socket clients.
8. Forwards signals (SIGINT, SIGTERM, SIGWINCH) verbatim.
9. Exits with the child's exit code.

### 4.1 Why PTY day-one

Pipes break terminal-aware programs in subtle ways: colors disappear,
buffering changes, progress bars stop animating, `flutter run` interactive
keys (`r`, `R`, `q`) don't work. PTY makes the wrapper invisible to the
child.

Implementation: `dart:ffi` against `forkpty(3)` and `ioctl(TIOCSWINSZ)`.
~150 lines of Dart for a clean Unix wrapper. Windows ConPTY is a separate
effort, deferred.

**[OPEN]** We considered `package:pty`. Rejected for v1: foundational
tooling shouldn't depend on a third-party PTY library; the API surface
we need is small enough to own.

### 4.2 Transparency rules

| Concern | Approach |
|---|---|
| User's stdout/stderr looks identical to running flutter directly | Direct passthrough of PTY master output |
| TTY-aware programs work normally | Real PTY (not pipes) |
| Stdin (interactive keys, prompts) | Forward the user's TTY into the child's PTY |
| Ctrl-C / Ctrl-Z / window resize | Trap signals, forward verbatim |
| Helper crash | Child runs in its own process group; orphaned but alive |
| Exit code | Wrapper exits with child's exit code |
| GUI presence/absence | Zero impact on the user-visible output |

The supervisor is the same regardless of who invoked it: CLI (`fw flutter run`),
shortcut (`fw open admin`), or IDE (via the shim layer in §8).

---

## 5. The four headline features

### 5.1 GUI showing all running commands

The GUI is a separate Flutter desktop app. Run at the project root, it:
- Watches the registry directory (`~/.cache/flutterware/registry/`)
- Lists active and recent runs
- For any run, connects to its log file (history) and Unix socket (live tail)
- Shows stdout/stderr with reasonable rendering of ANSI escape codes

Crucially, the GUI is a *consumer*. The helper writes the registry +
sockets whether or not the GUI is running. `tail -f` works as a fallback.

### 5.2 Custom UI per process kind

When a registered run has a `kind` field (e.g. `"server_local"`), the GUI
loads a kind-specific UI plugin. The plugin can:
- Render extra widgets (e.g. "current connected sessions" for `server_local`)
- Send commands to the process via the control socket (§7)
- Display structured events emitted by the process

The set of kinds is open-ended; new kinds = new GUI plugins. The wrapper
itself is kind-agnostic; it only relays.

### 5.3 Auto `--dart-define` injection

Project config (e.g. `flutterware.yaml`) declares rules:

```yaml
inject:
  flutter_run:
    - --dart-define=API_BASE=http://localhost:8089
    - --dart-define=FEATURE_X=true
```

Helper applies them when the matching command is detected. Always prints
a one-line notice listing what was added so debuggers aren't surprised.
A `--no-inject` flag opts out per invocation.

**[OPEN]** Whether to support conditional rules (e.g. inject only when
target is `chrome`). Probably yes, eventually; needs a tiny condition
syntax.

### 5.4 Shortcuts

Project config defines aliases:

```yaml
shortcuts:
  admin:
    cmd: flutter
    args: [run, -d, chrome, -t, packages/admin/lib/main_dev.dart]
  server:
    cmd: dart
    args: [run, bin/server_local.dart]
    cwd: packages/server
```

`fw open admin` resolves to the configured command, then dispatches
through the normal supervisor pipeline (registration, tee, control
socket). A shortcut is just a configurable command-rewriter, not a
parallel code path.

---

## 6. Registry & on-disk layout

```
~/.cache/flutterware/
├── registry/
│   └── <run_id>.json         one file per run (active or recent)
├── logs/
│   └── <run_id>.log          PTY-captured output
└── sockets/
    ├── <run_id>.tail.sock    GUI tail connections
    └── <run_id>.ctrl.sock    bidirectional control channel
```

Registry entry shape (additive; new fields fine):

```json
{
  "run_id": "01HX...",
  "wrapper_version": "0.3.0",
  "wrapper_pid": 12345,
  "child_pid": 12346,
  "command": "flutter run -d chrome -t demo/_my.dart",
  "kind": "server_local",
  "cwd": "/Users/.../rimbaud/packages/server",
  "project_root": "/Users/.../rimbaud",
  "started_at": "2026-05-01T12:34:56Z",
  "ended_at": null,
  "exit_code": null,
  "log_path": "...",
  "tail_socket": "...",
  "control_socket": "..."
}
```

GC policy (helper applies it on its own `install` and on each run):
keep last N runs per project, plus all currently-active runs. Bound
disk usage to a sensible default (e.g. 500 MB of logs, configurable).

**[OPEN]** Per-project vs global registry. Currently leaning **global,
filtered by `project_root`**, because some interesting processes don't
belong to any project (one-off scripts, global CLIs). Per-project is
simpler but loses those.

---

## 7. Bidirectional control protocol

A process under the wrapper *may* opt into a richer dialog with the GUI.
This is what makes "server_local has a custom UI" possible.

### 7.1 Setup

The wrapper always:
- Creates a Unix socket at `~/.cache/flutterware/sockets/<run_id>.ctrl.sock`
- Sets `FW_CONTROL_SOCKET=<path>` in the child's environment
- Sets `FW_RUN_ID=<run_id>` so the child can identify itself
- Listens on the socket, waiting for the child to connect

Vanilla Flutter doesn't read these env vars and never connects. No harm.

### 7.2 Handshake

Cooperating processes connect, then send:

```json
{"protocol": "fw-control/1", "kind": "server_local", "capabilities": ["status", "trigger-restart"]}
```

The wrapper records `kind` and `capabilities` in the registry, then
relays the same handshake to any GUI client connected for this run.

### 7.3 Wire format

Line-delimited JSON, bidirectional, no ordering guarantees beyond what
the underlying socket provides. Common message shapes:

| Direction | Shape | Purpose |
|---|---|---|
| child → GUI | `{"event": "<name>", "data": {...}}` | Notification |
| GUI → child | `{"call": "<capability>", "id": "<reqid>", "args": {...}}` | RPC |
| child → GUI | `{"reply": "<reqid>", "ok": true, "data": {...}}` | RPC reply |
| child → GUI | `{"reply": "<reqid>", "ok": false, "error": "..."}` | RPC error |

The wrapper is a dumb broker — it relays bytes without parsing the
content. Schema lives in a shared `flutterware_protocol` package
consumed by both the producer (e.g. `server_local.dart`) and the
consumer (the GUI).

### 7.4 Versioning

`fw-control/1` is the current handshake version. Older protocol
versions are honored as long as the GUI plugin still supports them.
New versions add capabilities; capabilities are negotiated, never
assumed.

---

## 8. IDE interception

IDEs invoke `flutter` and `dart` directly, bypassing `fw`. To capture
those runs too, swap the Flutter SDK's `bin/flutter` and `bin/dart`
binaries with our shims.

### 8.1 How

`<root>/.fvm/flutter_sdk/` becomes a directory we own (not a symlink):

```
<root>/.fvm/flutter_sdk/
├── bin/
│   ├── flutter        ← our shim binary
│   ├── dart           ← our shim binary
│   ├── cache          ← symlink to ~/.cache/flutter/<version>/bin/cache
│   └── ...            ← symlinks to the real cached binaries
├── packages/          ← symlink to real
├── examples/          ← symlink to real
└── ...
```

Built during `fw install` (when `ide_intercept: true` in project
config). Walks the cached SDK and mirrors every direntry as a
symlink, except for `bin/flutter` and `bin/dart` which become our shims.

The shims are essentially the same binary as the helper; they just
detect they were invoked as `flutter` (via `argv[0]`) and behave like
`fw flutter <args>` minus the bash dispatcher hop.

### 8.2 What we're not breaking

- IDE indexing of Flutter sources: works (those are symlinks)
- `flutter --version` output: identical (shim relays real flutter's stdout)
- `flutter` invoked by build tools: works
- Flutter version updates: `fw install` rebuilds the directory tree

### 8.3 Risks we accept

- New top-level binaries added by future Flutter releases that we'd
  *want* to shim. Realistic answer: `flutter` and `dart` have been
  stable forever; adding a third would be loud and we'd notice.
- Recursion in the shim (calling itself instead of the real binary).
  The shim resolves the real binary by absolute path
  (`~/.cache/flutter/<version>/bin/flutter`); no possibility of
  recursion if implemented carefully.

### 8.4 Opt-in

Default off in v1. Project flips `ide_intercept: true` once the
non-IDE path is stable.

---

## 9. Configuration

Project-level config lives at `<project_root>/flutterware.yaml`:

```yaml
shortcuts:
  admin:
    cmd: flutter
    args: [run, -d, chrome, -t, packages/admin/lib/main_dev.dart]

inject:
  flutter_run:
    - --dart-define=API_BASE=http://localhost:8089

ide_intercept: false
log_retention:
  max_runs: 200
  max_disk_mb: 500
```

**[OPEN]** Whether to reuse `tool/tools.yaml` (already exists in
rimbaud) or introduce a new file. Leaning toward a new file because
its consumers and lifecycle are different.

---

## 10. Where the code lives

### 10.1 Decision

The CLI and GUI live in a separate **flutterware** repo. Rimbaud
contains only the bash shim, the bash dispatcher, and project-level
config. This makes the tooling reusable across projects, lets the
flutterware repo evolve at its own pace, and keeps branding consistent
with the GUI.

### 10.2 Layout

```
flutterware/                          (separate repo)
├── packages/
│   ├── flutterware_cli/              the helper binary (Dart)
│   │   ├── bin/main.dart
│   │   └── lib/{passthrough,shortcuts,injectors,registry,broker}.dart
│   ├── flutterware_protocol/         shared schema (control protocol, registry)
│   └── flutterware_gui/              the desktop app (Flutter, later)
└── README.md

rimbaud/                              (this repo)
├── bin/fw                            frozen shim
├── tool/fw                           bash dispatcher
├── flutterware.yaml                  project config (shortcuts, injects, etc.)
└── pubspec.yaml                      dev_dependency: flutterware_cli
```

### 10.3 Build and distribution

Inside `fw install`, after Flutter is ready:

1. `dart pub get` resolves `flutterware_cli` to the version pinned in
   the project's pubspec.
2. AOT-compile `flutterware_cli/bin/main.dart` to
   `.dart_tool/flutterware/bin/fw` via `dart compile exe`.
3. The bash dispatcher execs that binary for non-bootstrap commands.

Per-project version pinning works the same way `fvm` itself does:
projects pick the helper version that suits them, can stay on older
versions, can upgrade independently.

---

## 11. Roadmap (rough phasing)

Each phase produces something independently useful.

1. **Helper skeleton (passthrough)**.
   Dart binary that runs flutter under a PTY, tees output to a log file,
   registers the run. No control socket, no GUI. Already useful via
   `tail -f`. Validates the FFI/PTY layer.

2. **Bash dispatcher integration**.
   `tool/fw` execs the helper for `flutter` / `dart`. Behavior should
   be indistinguishable from today, except a log file appears.

3. **Control socket + handshake**.
   Shared `flutterware_protocol` package. Test with a Dart harness that
   connects to the socket and echoes events.

4. **`flutterware.yaml` + shortcuts + injection**.
   Project-level config kicks in. `fw open admin` works.

5. **GUI MVP**.
   Lists runs, tails logs, no control-socket UI yet. Standalone Flutter
   desktop app reading the registry.

6. **GUI custom UIs per `kind`**.
   Plugin architecture. Server-local UI is the proof of concept.

7. **IDE interception**.
   Shim layer in `.fvm/flutter_sdk/bin/`. Opt-in via config.

8. **Polish**: log retention, registry GC, doctor enhancements,
   Windows ConPTY if it's needed.

---

## 12. Open questions to revisit

- Per-project vs global registry (§6).
- One config file (`flutterware.yaml`) vs reusing `tool/tools.yaml` (§9).
- Conditional injection rules (§5.3).
- Whether to ship the helper as a single binary or `dart run`-on-demand.
  Currently leaning AOT during `fw install`; latency win matters for
  `fw flutter run` invoked frequently.
- IDE shim's `argv[0]` detection — robust on macOS / Linux, may need
  a different mechanism on Windows.
- Whether the wrapper should restart crashed children automatically,
  or stay strictly single-run. Probably single-run; restart belongs in
  the GUI as a user action.
- How to surface injection / shortcut expansion to AI agents reading
  the wrapper's output. Probably a stable line prefix they can grep for.

---

## 13. Non-goals

- Replacing Flutter's tooling: we wrap, we don't fork.
- Multi-language support beyond Dart/Flutter (not in scope; if it
  happens, it's a different tool).
- Production runtime: nothing here is meant to run in CI long-term beyond
  builds and tests; `flutterware` is a development-time tool.
- Centralized telemetry: registry stays local, no upload.
