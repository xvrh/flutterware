# Sub-project 0 — The SDK Wrap Point (Implementation Spec)

**Date:** 2026-05-15
**Status:** Implementation spec. Ready for an implementation plan.
**Parent:** `2026-05-15-wrapper-tool-architecture.md` — read it for vocabulary
(Mechanisms A/B, three-layer distribution, sub-project decomposition).
**Brief:** `2026-05-15-subproject-0-sdk-wrap-point.md` — the scoping brief.
**Phase A finding:** `2026-05-15-subproject-0-ide-launch-finding.md` — the
empirical result that shaped this spec.

## Purpose

Wrap the `flutter`/`dart` scripts an IDE invokes so that every run — CLI, AI, or
IDE — is intercepted, classified, observed, and can have a `--dart-define`
injected, degrading to plain passthrough on any failure. This is the riskiest
piece of the architecture; building it for real and pointing an IDE at it is how
the architecture is de-risked.

The Phase A spike already de-risked the central unknown (see the finding doc):
IntelliJ launches runs as a direct `flutter run --machine` with `--dart-define`
values in plain argv. No daemon JSON-RPC proxy is needed; injection is an argv
rewrite. This spec is written on that result.

## Two open decisions — resolved

1. **Wrapped-script placement: per-project mirror facade.** The project's SDK
   path is a real directory whose `bin/flutter` and `bin/dart` are wrapper
   scripts and whose every other entry symlinks into the pristine shared SDK.
   The shared SDK stays byte-identical to a clean checkout. The wrapper `exec`s
   the *real* binary, which computes `FLUTTER_ROOT` from its own physical path —
   so builds run entirely against the pristine SDK; the mirror is a pure
   interception facade.

2. **Noise classification: a hard-coded probe default.** A pure-bash `case` on
   the first non-flag argument. `flutter run` / `flutter test` → *interesting*;
   everything else, and all `dart`, → *noise*. This is deliberately disposable —
   sub-project 3's `config.dart` replaces it. Every invocation is recorded as
   one line in an audit log, which doubles as the discovery instrument for
   refining classification later.

## What it delivers

A wrapped `flutter`/`dart` such that, on every invocation:

1. **Marker resolution** — walk up from `$PWD` for the `flutter_version` marker.
   Not found → `exec` the real binary immediately, fully transparent.
2. **Classification** — pure-bash `case` on the first non-flag arg.
3. **Noise** → append one audit-log line, `exec` the real binary.
4. **Interesting** → hand off to the compiled `flutterware wrap` executable,
   which resolves worktree identity, injects `--dart-define=FW_MARKER=<token>`
   by argv rewrite, runs the real binary under a transport passthrough, captures
   output to a local session sink, and exits with the child's code.
5. **Always degrades** — any failure (missing marker, missing/failing wrap
   executable, error inside the wrap) ends in a plain `exec` of the real binary.

Plus: an installer that builds the mirror around an existing SDK, a probe app
that proves the injected define reaches the running app, and the audit log /
session sink for inspecting what was intercepted.

## Components

### 1. The mirror facade

Location: `<project>/flutterware/sdk/` — **non-hidden** (IntelliJ rejects SDK
paths with a hidden path component; the finding confirms this). The audit log
and session sink live separately under `<project>/.flutterware/` (hidden, not
referenced by any IDE config).

Layout: a real directory mirroring the SDK. Every top-level SDK entry and every
`bin/` entry is a symlink into the pristine shared SDK, except `bin/flutter` and
`bin/dart`, which are the generated wrapper scripts. (Sub-project 0 builds the
*full* mirror — symlink everything — rather than hunting the minimal symlink
set; minimization is a later optimisation.)

The IDE is pointed at `<project>/flutterware/sdk` as its **Flutter SDK**;
IntelliJ then derives the Dart SDK as `<mirror>/bin/cache/dart-sdk` itself,
through the `bin/cache` symlink. The IDE must not be pointed at the cache
directly, or the wrap is bypassed.

### 2. The installer

A `flutterware wrap-install` command (or equivalent), given an existing shared
SDK path and a project root: creates `<project>/flutterware/sdk/`, symlinks all
SDK entries, and writes the two wrapper scripts with absolute paths baked in
(real binary path, compiled `flutterware wrap` executable path). Idempotent —
re-running rebuilds cleanly.

Sub-project 0 assumes the shared SDK already exists at a known path; the
walker/bootstrapper/SDK-download is tracked separately.

### 3. The bash wrapper scripts (the cheap fast path)

Generated per project by the installer. Both `flutter` and `dart` shims share
the same logic, parameterised by the wrapped binary's name:

1. Walk up from `$PWD` for `flutter_version`. Not found → `exec` the real
   binary. (This is the bulk-transparency case and the cheapest path.)
2. Find the first non-flag argument (skip leading `--*` global flags such as
   `--no-color`, `--verbose`).
3. Classify: `flutter` + (`run` | `test`) → interesting; all else → noise.
4. Append one tab-separated audit-log line — timestamp, cwd, kind,
   classification, full argv — to `<project>/.flutterware/wrap-audit.log`.
   Cheap `printf >>`; concurrent short appends are atomic on POSIX.
5. Noise → `exec` the real binary.
6. Interesting → `exec` the compiled `flutterware wrap` executable, passing the
   real binary path, kind, project root, and the original argv. If that
   executable is missing or not executable → `exec` the real binary.

Classification and the noise path are pure bash, so the high-frequency `dart`
invocations an IDE makes pay only a marker walk-up and one log append.

### 4. The `flutterware wrap` command (the heavy path)

A new standalone CLI entry `app/bin/wrap.dart` (mirroring `app/bin/passthrough.dart`)
with logic under `app/lib/src/wrap/`, compiled to an executable via
`dart compile exe`. Invoked by the bash shim only for *interesting* runs.

Internal units, each independently testable:

- **Project / worktree resolution** — project root is the `flutter_version`
  directory; worktree identity is resolved from the worktree's `.git` *file*
  (`gitdir:` pointer) when present, else the project root itself.
- **dart-define injection** — rewrite the argv to insert
  `--dart-define=FW_MARKER=<token>` immediately after the `run`/`test`
  subcommand token. The `<token>` is a value the wrap chooses and records, so
  the probe app can confirm the round-trip.
- **Transport passthrough** — run the real binary and stream its I/O:
  - `stdin` is *not* a terminal (an IDE / `--machine` run) → plain bidirectional
    **pipe** passthrough (tee both directions to the sink).
  - `stdin` *is* a terminal (an interactive CLI run) → **PTY** passthrough,
    reusing `runUnderPty` from phase 1.
  Neither mode parses the stream; both are dumb tees. The child's exit code is
  propagated.
- **Session sink** — writes a `<project>/.flutterware/sessions/<id>/` directory
  with captured output and a `meta.json` (timestamp, worktree, argv before and
  after rewrite, injected token, exit code).
- **Graceful degradation** — any error before/while spawning the child falls
  back to a plain spawn of the real binary with the original argv; the wrap
  never prevents the real command from running.

### 5. The probe app

`examples/example` gains a trivial widget that reads
`String.fromEnvironment('FW_MARKER')` and displays it. Success is that token
appearing **in the running app** — for CLI, AI, VS Code, and IntelliJ launches —
not merely present in a host process.

## Observation sink format

Under `<project>/.flutterware/` (hidden; sub-project 1 replaces all of this with
the daemon + SQLite DB):

- `wrap-audit.log` — one tab-separated line per invocation (every kind, every
  classification). The discovery instrument: `grep` it after living with an IDE
  to refine classification.
- `sessions/<id>/` — per interesting run: captured output stream(s) and
  `meta.json`.

## Graceful degradation — every layer

- No `flutter_version` marker → plain `exec` (not a flutterware project).
- Classification or audit-log write fails → still `exec` the real binary.
- `flutterware wrap` executable missing / not executable → bash `exec`s the real
  binary.
- Any error inside `flutterware wrap` → plain spawn of the real binary with the
  original, un-rewritten argv.
- The real command always runs and the wrap exits with the child's code.

## File layout

```
app/bin/wrap.dart                         # new standalone CLI entry
app/lib/src/wrap/
  wrap_command.dart                       # arg parsing + orchestration
  project_resolution.dart                 # project root + worktree identity
  dart_define.dart                        # argv rewrite
  transport.dart                          # PTY vs pipe passthrough
  session_sink.dart                       # local observation sink
app/lib/src/passthrough/                  # reused as-is (PTY transport)
docs/superpowers/specs/                    # this spec + the finding doc
```

The installer command is added to the existing CLI command set.

## Testing & success criteria

**Automated** (`app/test/`):
- Classification: representative `flutter`/`dart` argvs → correct
  interesting/noise verdict, including leading global flags.
- dart-define injection: argv rewrite inserts the define in the right position
  and is idempotent against the input shapes seen in the finding.
- Project/worktree resolution: marker walk-up; `.git`-file worktree case.
- Degradation: errored wrap still spawns the real binary with original argv.

**Manual** (recorded in a smoke-test doc, like the phase-1 passthrough smoke):
- `flutter run` from IntelliJ and from VS Code appears in `wrap-audit.log` as an
  intercepted interesting session, output captured, and `FW_MARKER` confirmed
  *inside the running app*.
- The IDE's own workflows still work end-to-end through the wrap — hot reload,
  stop, debugger, analysis server.
- Noise `dart`/`flutter` invocations are classified as noise and add negligible
  latency.
- Killing the wrapper, or any wrap-step failure, still runs the real command.

A clear negative result — the wrap breaks an IDE workflow, or noise cannot be
classified cheaply — is also a successful outcome: it forces a change to the
parent architecture before more is built on it.

## Out of scope (later sub-projects)

- The daemon, the SQLite DB, `policy.query` — sub-project 1. Here there is no
  daemon; the wrap always takes the standalone path and writes the local sink.
- `config.dart` / per-worktree config processes / user-configurable
  classification — sub-project 3.
- The Mechanism-B back-channel — sub-project 2.
- The walker + bootstrapper + SDK download — tracked separately; sub-project 0
  assumes a shared SDK exists at a known path.
- Auto-writing the IDE's `.idea/` SDK configuration — sub-project 0 validates
  the facade with the IDE configured by hand.
