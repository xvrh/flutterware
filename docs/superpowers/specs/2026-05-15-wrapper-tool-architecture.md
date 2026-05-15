# Command-Wrapper Tool — Architecture Exploration

**Date:** 2026-05-15
**Status:** Exploration / direction-setting. **Not a committed spec.** No implementation
beyond phase 1 (the `passthrough` command) exists.

This document captures a design discussion about the larger tool that the
`passthrough` PTY command is the first building block of. It records the shape
we agreed on and the open questions, so a future session can pick it up without
re-deriving everything.

## The goal

A wrapper CLI that AI agents (and humans) invoke in many git worktrees of the
same project. Every command run through the wrapper funnels to one central,
per-project place so its progress and results are observable in a GUI — each
open worktree shown as a tab.

`passthrough` (phase 1, done) is the bottom layer: it runs a child process under
a real PTY, tees its output, forwards stdin/signals/resize, and exposes the
captured stream. Everything below builds on top of it.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  flutterware daemon  (one per project)                       │
│                                                               │
│  ┌──────────────────┐    ┌────────────────────────┐          │
│  │ config compiler  │ ←  │ <project>/flutterware/ │ watch    │
│  │ (dart compile,   │    │   config.dart           │          │
│  │  on invalidation)│    └────────────────────────┘          │
│  └────────┬─────────┘                                         │
│           ▼                                                   │
│  ┌──────────────────┐  separate process — crash-isolated;     │
│  │ user-config      │  killed + replaced on recompile         │
│  │ process          │                                         │
│  └────────┬─────────┘                                         │
│           ▲ JSON-RPC over socket                              │
│  ┌────────┴─────────┐    ┌────────────────────────┐          │
│  │ RPC server       │ ←  │ wrapper CLIs query     │          │
│  │ (unix socket)    │    │ "spawning X — policy?" │          │
│  └──────────────────┘    └────────────────────────┘          │
│                                                               │
│  ┌──────────────────┐                                         │
│  │ DB writer        │ → <project>/.flutterware/flutterware.db  │
│  └──────────────────┘                                         │
└────────────────────────────────────────────────────────────┘
        ▲                    ▲                      │
        │ query              │ inner-app channel    │ sqlite_async.watch()
┌───────┴────────┐  ┌────────┴────────┐    ┌────────▼────────────┐
│ wrapper CLI    │  │ inner app       │    │ GUI                 │
│ (per worktree) │  │ (e.g. flutter   │    │ (attaches any time, │
│  └─ passthrough│  │  run) connects  │    │  one tab/worktree)  │
│     + PTY      │  │  via env var    │    │                     │
└────────────────┘  └─────────────────┘    └─────────────────────┘
```

### Components

**Wrapper CLI** — thin, per-invocation. Flow:
1. Find project root (walk up to nearest `flutterware/` marker).
2. Find or auto-spawn the project daemon.
3. RPC `policy.query`: "about to run `<cmd> <args>` in `<cwd>` — apply policy."
4. Apply the returned rewrites (argv, env, GUI metadata, channel routing).
5. Spawn the child under `passthrough` (PTY), stream observations to the DB
   through the daemon.
6. If the daemon is down or policy fails → fall back to plain passthrough.

**Per-project daemon** — long-lived, one per project. Owns:
- Compilation of `<project>/flutterware/config.dart` (recompile on file
  invalidation; not Dart hot reload — judged too heavy / low value).
- The user-config process (run separately for crash isolation; replaced on
  recompile).
- A Unix-socket JSON-RPC server that wrapper CLIs query.
- The DB writer.

Daemon identity is **per-project**, not per-user: different projects may use
different flutterware versions. (A worktree technically can override the
flutterware package version; that complication is deliberately ignored for now.)

**`config.dart`** — user-written policy code. Proposed API:

```dart
import 'package:flutterware/config.dart';

void main() => Flutterware.configure((fw) {
  // declarative match pattern + imperative handler
  fw.command('flutter run', timeout: Duration(seconds: 3), (ctx) async {
    final flags = await fetchRemoteFlags();       // async allowed
    ctx.args.inject(['--dart-define=APP_ENV=dev', ...flags]);
    ctx.gui.tabLabel = 'flutter · ${ctx.worktree.name}';
    ctx.channels.enable(['http.logs', 'ui.buttons']);
  });

  fw.command('dart test', (ctx) {
    ctx.gui.tabLabel = 'tests';
  });

  // async reactions to runtime events (off the spawn critical path)
  fw.on<ChannelMessage>('http.logs', (msg) {
    if (msg.statusCode >= 500) fw.notify('5xx from ${msg.path}');
  });
});
```

- The match pattern is **declarative data** (so the daemon/GUI can list
  recognized commands without running code).
- The handler is **imperative** and `FutureOr<void>` — sync for the fast path,
  `await` allowed when needed.
- Inside the handler: synchronous spawn-time config (`ctx.args`, `ctx.env`,
  `ctx.gui`) is on the wrapper's critical path; `fw.on` event reactions are not.
- A purely-declarative `fw.rules([...])` form could coexist later (e.g. for a
  GUI-editable rules table) — not designed yet.

**Communication channel** — per-invocation Unix socket. The wrapper owns the
socket; its address is injected into the child via an environment variable so
the inner app can connect back. Wire format: JSON frames with an envelope
`{session, channel, payload}`. `channel` is a sub-protocol name
(`pty.stdout`, `http.logs`, `ui.buttons`, …); new features = new channel name,
no protocol version bump. The config process never touches the DB or PTY
directly — it only *requests* actions through the daemon.

**SQLite as the bus** — the daemon writes everything (PTY output, channel
messages, session metadata) to `<project>/.flutterware/flutterware.db`. The GUI
reads via `sqlite_async`'s `watch()` streams and subscribes selectively with
SQL `WHERE` clauses. No separate daemon↔GUI protocol. Cross-process change
detection is ~100–200 ms (polling `pragma data_version`) — acceptable because
the user's own terminal already shows real-time output; the GUI is a secondary
observer.

Active-session discovery and orphan cleanup (wrapper killed `-9`) are handled
with a heartbeat column the wrapper bumps periodically, plus a staleness sweep.

## Config-process ↔ daemon protocol

JSON frames over a socket, same envelope style as the rest:

| Direction | Message | Purpose |
|---|---|---|
| daemon → config | `policy.query {invocation}` | "about to spawn X — policy?" |
| config → daemon | `policy.result {args, env, gui, channels}` | the decision |
| config → daemon | `event.subscribe {channel}` | config wants runtime events |
| daemon → config | `event.deliver {channel, payload}` | forwards a runtime event |
| config → daemon | `action.notify` / `action.dbWrite` / … | side effects requested |
| config → daemon | `ready` / `error {message, stack}` | startup + failures |

The config process receives concurrent `policy.query` requests (multiple
worktrees spawning at once); each gets its own `ctx`.

## Decisions locked

- **Unix socket** for the channel (per invocation).
- **GUI is lazy** — the CLI does everything; the GUI catches up later when opened.
- **JSON** wire format for now, with named sub-protocol channels.
- **Multiple simultaneous invocations** across worktrees — funnel to one
  per-project DB.
- **Per-project daemon** (not per-user, not per-worktree).
- **Compile-on-invalidation** for `config.dart` (not Dart hot reload).
- **`config.dart` handler is `FutureOr<void>`** — async allowed.
- **Per-command tunable timeout** with a conservative global default.

## Guiding principle — always degrades to plain passthrough

Every layer can fail and the user's command still runs:

- **Policy-query timeout** — wrapper waits ≤ the command's budget for
  `policy.result`; on timeout, spawn unmodified and log it.
- **Atomic policy application** — if the handler times out mid-`await`, discard
  the *entire* decision. Never apply a partial `ctx` (partial policy is silent
  corruption).
- **Compile failure** — daemon keeps the last-good compiled config; surfaces the
  error in the GUI; if there is no good version, all commands fall through.
- **Config crash** — daemon restarts the process; repeated crashes trip a
  circuit-breaker → config disabled, plain passthrough, error shown.
- **Daemon unreachable** — wrapper auto-spawns it; if that fails too → plain
  passthrough.

## Open questions

- How the GUI process starts in the per-project model (manual `flutterware gui`
  from inside the project, auto-spawn on first wrapper invocation, or a
  standalone always-running app with a project picker). Leaning toward manual.
- Whether a purely-declarative `fw.rules([...])` subset is worth adding for
  GUI-editable rules.
- DB schema for sessions, PTY chunks, and channel messages.
- Daemon auto-start mechanics (double-fork / `setsid`) and the well-known socket
  path convention.

## Suggested next step (separate session)

Build the **smallest end-to-end loop** to de-risk the daemon lifecycle and the
DB-as-bus before the `config.dart` machinery goes in:

> A trivial daemon + wrapper that recognizes one hard-coded command and writes
> its PTY output to a per-project SQLite DB — no config compilation, no channels,
> no policy. Prove: daemon auto-start, project-root discovery, the wrapper →
> daemon → DB write path, and a minimal GUI/CLI reader using `sqlite_async`
> `watch()`.

Once that loop is solid, layer in (in order): `config.dart` compilation +
`policy.query`, then the per-invocation channel and sub-protocols, then richer
GUI.
