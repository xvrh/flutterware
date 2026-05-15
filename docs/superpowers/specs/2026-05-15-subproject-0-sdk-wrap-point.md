# Sub-project 0 — The SDK Wrap Point

**Date:** 2026-05-15
**Status:** Scoping brief. Hand-off for a fresh implementation session — *not*
a finished spec. The implementation session should brainstorm the "Open
decisions" below before writing code, then produce a plan.
**Parent:** `2026-05-15-wrapper-tool-architecture.md` (read it first — this brief
assumes its vocabulary: Mechanisms A/B, the three-layer distribution model, the
sub-project decomposition).

## Purpose

Sub-project 0 is the **first** sub-project for two reasons: everything else
depends on it, and it is the **riskiest assumption** in the whole architecture.

The architecture promises to observe `flutter run` / Dart processes started
*any way* — by an AI, a human terminal, or an IDE. That promise rests entirely
on one hack: **wrapping the `flutter` and `dart` scripts the IDE itself
invokes.** The daemon, DB, and channel layers are conventional engineering and
will work. The SDK-script wrap is a hack against Flutter's SDK layout and IDE
behavior — if it is fragile, the architecture must change. Sub-project 0 exists
to find out, by building the real wrap point and pointing a real IDE at it.

It is built **for real** (the wrapped scripts are permanent infrastructure, not
throwaway), but kept deliberately minimal — its only genuinely exploratory part
is the noise-classification rule.

## What it delivers

A wrapped `flutter` / `dart` such that, on every invocation:

1. **Project + worktree resolution** — walk up to the `flutter_version` marker
   for the project root; resolve worktree identity (a worktree's `.git` is a
   *file* pointing at the common dir). Not a flutterware project → exec the real
   binary immediately, fully transparent.
2. **Classification** — decide *interesting* (a run worth observing, e.g.
   `flutter run`, `flutter test`) vs *noise* (`dart pub get`, the IDE analysis
   server, `flutter --version`, …).
3. **Noise** → exec the real binary directly, negligible overhead.
4. **Interesting** → run the real binary under the existing `passthrough` PTY
   (reuse `runUnderPty` from phase 1), capture its output, **inject a marker env
   var** into the child (proving the injection path), and append a record to a
   **local log/capture sink**.
5. **Always** — the real command runs and exits with the child's code; any
   failure in the wrap degrades to plain exec (the guiding principle).

Plus: a minimal installer step that places the wrapped scripts around an SDK,
and a way to inspect what was intercepted (the local log).

## In scope / out of scope

**In scope**
- The wrapped `flutter`/`dart` and the wrap logic.
- Project-root + worktree-identity resolution.
- A minimal, hard-coded noise-classification rule.
- Env-var injection into interesting children.
- A **local** observation sink (a log file + captured output) — enough to prove
  interception.
- Reuse of the phase-1 `passthrough` PTY for interesting runs.

**Out of scope** (later sub-projects)
- The daemon, the SQLite DB, `policy.query` — sub-project 1. In sub-project 0
  there is no daemon, so the wrap *always* takes the degraded/standalone path
  and writes to the local sink. Sub-project 1 swaps that sink for the daemon.
- `config.dart` / per-worktree config processes / real policy — sub-project 3.
  Classification here is hard-coded, not user-configurable.
- The Mechanism-B back-channel — sub-project 2.
- The full walker + bootstrapper + SDK download. Sub-project 0 may **assume an
  SDK already exists** at a known path and focus on wrapping it; building the
  distribution layers is tracked separately.

## Intended shape (subject to the open decisions)

The wrapped script keeps a **cheap fast path**: classification and the noise
case should be pure bash (a `case` on the first argument), so the common,
high-frequency `dart` invocations pay almost nothing. Only *interesting* runs
hand off to the heavier machinery (the compiled `passthrough` executable with
the real binary as its child). This matters because wrapping `dart` taxes every
`dart` call an IDE makes — build scripts, the analysis server, etc.

## Open decisions — brainstorm these first

The implementation session must resolve these before coding. They are genuine
design choices, not placeholders.

1. **Wrapped-script placement.** Two candidates, from the parent doc:
   - *Shared SDK cache* — wrap `<cache>/bin/flutter`/`dart` in place. Simple
     (one install per version) but modifies a git-tracked SDK file and affects
     every project on that version.
   - *Per-project mirror dir* — the project's SDK path is a real directory whose
     `bin/flutter`/`dart` are wrappers and whose other entries symlink into the
     pristine shared cache. Keeps the cache git-clean, scopes the wrap to
     opted-in projects, and is naturally per-worktree.

   The parent doc leans **per-project mirror**. Validate: how many symlinks does
   a believable SDK mirror need, and does IntelliJ's Dart/Flutter plugin accept
   it (it resolves `<sdk>/bin/cache/dart-sdk`).

2. **Noise classification — the central research question.** A static
   subcommand allow/deny list is the obvious starting point (`flutter run`,
   `flutter test` interesting; everything else noise). Living with a real IDE
   for an hour is how you find out whether that is enough or whether it
   misfires. *This is the finding sub-project 0 exists to produce.*

3. **Locating the real binary.** Depends on (1): a renamed `flutter.real` in the
   shared-cache approach, or the cache path directly in the mirror approach.

4. **The local observation sink format** — where the log/captured output lives
   (e.g. under `.flutterware/`) and its shape. Keep it trivial; sub-project 1
   replaces it with the DB.

## Success criteria

The de-risking is successful when:

- A `flutter run` launched **from IntelliJ** (and ideally VS Code) appears in
  the local log as an intercepted *interesting* session, with its output
  captured and a marker env var confirmed injected into the child.
- The IDE's own workflows still work end-to-end through the wrap — hot reload,
  stop, the debugger, the analysis server.
- The IDE's many *noise* `dart`/`flutter` invocations are classified as noise
  and add negligible latency.
- Killing the wrapper (or any wrap-step failure) still lets the real command run
  (degrades to plain exec).

A clear *negative* result — "the hijack breaks the IDE" or "noise is
unclassifiable cheaply" — is also a successful outcome of sub-project 0: it
would force a change to the parent architecture before more is built on it.

## Relationship to later sub-projects

Sub-project 0's local sink and standalone (no-daemon) path are intentionally
provisional. Sub-project 1 introduces the per-project daemon + DB and the wrap
point starts reporting to it via `policy.query` / DB writes; the local sink
becomes the fallback used only when the daemon is unreachable.
