# Server inspection — a Dart server reports into the GUI

**Date:** 2026-07-30
**Status:** design. "What is already true" is verified against the code and two
VM probes run on this machine; everything under "Decisions" is agreed direction
from the 2026-07-30 brainstorm; the protocol and API sketches are proposals for
review.
**Extends:** `2026-07-27-gui-cli-mcp-architecture.md` (decisions 1–6 hold),
`2026-07-25-overhaul-master-plan.md` (this is the first slice of M5's "process
catch-all", goal 8 consumer side).
**Revises:** one premise of `2026-05-15-wrapper-tool-architecture.md` — see
"The reframe" below. The rest of that doc's Mechanism-B intent carries over.

## The question

A Dart server (shelf, or anything else) should report its live state — HTTP
request/response, SQL queries, logs and errors — to the flutterware GUI for
inspection: timelines, per-request timing, explainable/re-runnable queries.
Three questions decide the shape:

1. How does the server find the GUI (and vice versa)?
2. What transport and protocol?
3. What makes it *useful* rather than a log viewer?

With the hard constraint that it must work however the server was launched:
`fw run server …`, the IDE's run button, or an agent typing
`dart run bin/server.dart` — the tool cannot assume everything launches through
a wrapper.

## The short answer

The server **announces itself** with a handle file in `~/.flutterware/run` and
binds a unix socket; the GUI, `fw`, and the MCP server **attach** the same way
`attachToLiveSession` already does — liveness decided by connecting, stale
handles deleted on the way past. No wrapper, no env var, no daemon, no mDNS.
The library keeps a bounded in-memory ring and replays it on attach; nothing
persists. Explain/requery work because the command channel runs handlers
*inside* the server process against its own live DB connection.

## The reframe

`2026-05-15-wrapper-tool-architecture.md` says Mechanism A (the SDK wrap
injecting an env var) is *how* Mechanism B learns where to connect: "A is not a
secondary convenience — it is how B learns where to connect." That was written
before `LiveSession` existed. The UI catalog has since solved the identical
rendezvous problem in the opposite direction —
[live_session.dart](../../../app/lib/src/catalog/live_session.dart) publishes a
JSON handle keyed on the project root, and consumers attach — and that
direction is strictly better here, because it is launcher-independent. An
IDE-launched or agent-launched server needs nothing injected into it.

Mechanism A (`fw run server`) survives as optional sugar: restart-on-save, env
injection for containers, a pinned status line. It is no longer load-bearing
for discovery. Bonjour/mDNS, the other candidate, buys network reach the core
case does not need (everything is on one laptop) at the cost of announcing repo
paths on the LAN; it is parked as a possible future transport for
cross-machine setups, not part of this design.

## What is already true (verified)

### 1. `dart run` does NOT enable asserts

Probed on this machine (Dart from the pinned SDK):

```
dart run asserts_probe.dart   → asserts: false
dart asserts_probe.dart       → asserts: false
./asserts_probe (compiled)    → asserts: false
```

So an asserts-based "am I in dev mode" gate — the analog of how the widget
inspector rides `assert(() {…}())` — **does not work for servers**. The
brainstorm's first proposal for the release gate is dead on arrival.

### 2. `dart.vm.product` is the real release signal

Probed the same way:

```
dart run product_probe.dart               → product: false
dart compile exe → ./product_probe        → product: true
```

`const bool.fromEnvironment('dart.vm.product')` is false under JIT (`dart run`,
IDE debug and run, agent launches) and true in compiled executables — the same
constant Flutter's `kReleaseMode` reads. This is the gate. (`dart compile
aot-snapshot` + `dartaotruntime` was not probed — no runtime on PATH; expected
to also be product mode, worth confirming if anyone deploys that way.)

### 3. The rendezvous pattern exists and its rules are documented

[live_session.dart](../../../app/lib/src/catalog/live_session.dart):
- Keyed on **project root alone, not a config hash** (`:19-24`) — precisely
  because GUI and `fw` build different configs for the same package.
- `attachToLiveSession` (`:108-125`): liveness = it connects within 2s; a
  handle that will not connect is deleted on the way past. No pid checks.

[run_dir.dart](../../../app/lib/src/utils/run_dir.dart):
- `flutterwareRunDir()` = `~/.flutterware/run` (HOME/USERPROFILE), deliberately
  short — 104-byte `sun_path` cap, `checkSocketPath` fails legibly (`:152-165`).
  **Note: it creates the directory on call** — the server library must not use
  that behavior for its gate (see decision 3).
- `sweepRunDir` (`:64-108`): nothing younger than `keepFor` is touched; daemon
  sockets (`^[0-9a-f]{16}$` keys) are connect-probed before deletion; guest
  sockets (`g-*`, `shot-*`) age out without a probe; `live-*.json` is left
  alone because it is bounded at one per project.

### 4. The plugin contract forbids sockets in `computeAll`

[plugin_core.dart](../../../app/lib/src/plugins/plugin_core.dart): `report` is
a pure read called per sidebar row per frame (`:31-37`); `computeAll`'s budget
is parsing — "no compiling, no process spawn, no socket, no network"
(`:68-90`). Attaching to a server therefore happens on subscription (panel
visible) or behind a `PluginAction`, never in `computeAll`.

### 5. MCP already has the right surface

[mcp_server.dart](../../../app/lib/src/session/mcp_server.dart) exposes exactly
three tools (`:59`) — status/actions/invoke — and reaches live processes only
through attach (`_withSession` opens cold, `UiCatalogCore` attaches to the live
handle). A server plugin adds *actions*, not tools, and inherits the whole
agent surface plus the auto-generated `docs/capabilities.md` entry for free.

### 6. What exists of a wire envelope

[lib/src/utils/connection/](../../../lib/src/utils/connection/message.dart) is
the legacy test-runner transport: built_value `Message{type, id, channel,
method, serializedParameter1..3}` with codegen and string-encoded params. It
works, but its shape (fixed method + three stringly params) fits RPC, not event
streaming, and drags `built_value` codegen into what should be a small readable
runtime. `app/lib/src/ui_catalog/service/udp_discovery.dart` is a 7-line stub —
UDP discovery was never built. Neither is reused here (decision 2).

### 7. This does not trigger the daemon identity split

[daemon_address.dart](../../../app/lib/src/catalog/daemon_address.dart)`:22-45`
defers splitting process identity from service identity until "the first second
service added to the daemon *process*". No part of this design lives in the
daemon process: attach is direct GUI↔server, consistent with constitution
decision 3 ("the daemon executes and holds live resources; it does not
remember"). The deferral stands untouched.

## Decisions

### 1. Discovery: the server announces, attachers connect

On first reported event (see decision 4 — there is no init call), the library:

1. Binds a unix socket `srv-<hash>-<name>-<pid>.sock` in the run dir.
2. Writes `srv-<hash>-<name>-<pid>.json`:

```json
{
  "projectRoot": "/Users/x/dev/myapp",
  "name": "my_server",
  "socketPath": "…/run/srv-1a2b3c4d-my_server-4242.sock",
  "pid": 4242,
  "startedAt": "2026-07-30T14:01:12Z",
  "protocol": 1
}
```

- `projectRoot` is `Directory.current.path`, canonicalized. No walking up, no
  `Platform.script` heuristics — cwd is where IDEs and agents run servers from,
  and it is overridable (`FlutterwareServer.configure(root: …)`) for the rare
  exception.
- **Matching is by path containment, not hash equality.** The GUI scans
  `srv-*.json` and shows a server under any open worktree whose root contains
  the handle's `projectRoot` — so a server run from `repo/server_pkg/` appears
  under the `repo` worktree. The `<hash>` in the filename (8 hex of
  sha1(projectRoot)) is only a filename uniquifier; nothing parses it.
- `name` defaults to the entrypoint basename (`bin/my_server.dart` →
  `my_server`), overridable. The `<pid>` suffix makes restarts and multiple
  instances collision-free; attachers group by `name` and delete handles that
  will not connect, exactly like `attachToLiveSession`.
- The GUI watches the run dir for `srv-*` appearing/disappearing; `fw` and MCP
  scan on demand.

**Sweep integration** (resolved 2026-07-30, discussed rather than
rule-copied): `srv-*.sock` gets the **daemon rule — probe before delete — not
the guest rule**. The guest rationale ("a guest up for `keepFor` is a leak")
inverts for servers: a dev server running since Monday is normal. Age-out
would cascade into a lie: unlink a live server's socket → new attachers cannot
connect → the attacher scan deletes the handle as dead → **the server vanishes
from the list while still running**. The other guest objection — "the socket
expects a protocol, not a knock" — is dissolved by decision 2's attach
handshake: connection ≠ attachment, so a probe that connects and closes is
free by construction. `srv-*.json` is swept only when its socket is gone or
dead (it is not bounded at one per project, so it does not inherit
`live-*.json`'s leave-it-alone rule); attachers delete dead handles on scan,
and the library deletes its own predecessors (same projectRoot + name, dead
socket) on activation, so the dir stays bounded without waiting a day for the
sweep.

### 2. Transport: newline JSON over the unix socket, channel envelope

One frame shape both directions:

```json
{"ch": "sql", "t": "event", "p": {…}}
{"ch": "sql", "t": "req",  "id": 7, "m": "explain", "p": {"queryId": "…"}}
{"ch": "sql", "t": "res",  "id": 7, "p": {…}}
{"ch": "sql", "t": "err",  "id": 7, "p": {"message": "…"}}
```

- `ch` is a sub-protocol name (`http`, `sql`, `log`, `meta`, …). **New feature
  = new channel name, no protocol version bump** — the one rule kept verbatim
  from the 2026-05-15 doc. The `protocol` field in the handle exists for the
  day the *envelope itself* has to change, and is expected to stay at 1.
- Hand-rolled `jsonEncode`/`jsonDecode`, newline-delimited — same framing as
  the compiler daemon. Not the built_value `Connection` (fact 6): the runtime
  half must be small, readable, and codegen-free, because users read the
  library their server imports and adapters are copy-paste (decision 5).
- **Connection ≠ attachment.** An accepted connection gets nothing until it
  sends `{"ch": "meta", "t": "req", "m": "attach"}`; the server answers with
  `meta` hello (`name`, `pid`, `startedAt`, known channels), replays the ring
  in event-id order, marks the boundary with a `meta.replay-done` event, then
  streams the live tail. This is what makes liveness probes (the sweep, the
  attacher scan) free: a connect-and-close knock triggers no replay and is
  indistinguishable from noise the read loop already ignores. Multiple
  attachers are supported; requests are answered per-connection.
- **Events are summaries; bodies are fetched lazily.** An `http` event carries
  method/path/status/duration and truncated previews; full request/response
  bodies and SQL result sets stay in the server's side buffer, fetched by id
  via `http.body`/`sql.rows` requests. The hot path is "serialize a small map
  onto a local socket".

### 3. Inert in release, and on machines without flutterware

The library is active iff **all** of:

1. `!const bool.fromEnvironment('dart.vm.product')` — compiled release
   binaries are inert (fact 2). The runtime env override `FW_SERVER_INSPECT=1`
   can re-enable a product build (the code is a few KB; it is not const-gated
   out, deliberately, so containers can opt in).
2. `~/.flutterware/run` **already exists** — the library never creates it
   (unlike `flutterwareRunDir()`, fact 3). A prod box or CI runner that never
   ran flutterware stays inert even under `dart run`.
3. `FW_SERVER_INSPECT != '0'` — the explicit off switch.

When inert, every primitive is a cheap no-op: no socket, no file, no ring.

### 4. No init call: the first event activates

There is no `FlutterwareServer.enable()`. The primitives lazily initialize on
first use — adding the shelf middleware *is* the setup. An optional
`FlutterwareServer.configure(name: …, root: …)` exists for overrides and must
be called before the first event. Rationale: the pitch is "add one import and
one middleware line", and every mandatory init call is a README paragraph and
a forgotten-in-one-of-three-services bug.

### 5. Package boundary: primitives in `flutterware`, adapters as copy-paste

Master-plan decision 9 (heavy deps never in `package:flutterware`) applies to
the letter. The published package gains one small pure-Dart library,
`package:flutterware/server.dart`, with **zero new dependencies**:

```dart
FlutterwareServer.event('log', {…});                    // fire-and-forget
FlutterwareServer.span('sql', {…}, () async => …);      // timed, auto-correlated
FlutterwareServer.handle('sql', 'explain', (p) async => …);  // command handler
FlutterwareServer.value(#fwRequestId);                  // read correlation ids
```

Adapters — shelf middleware, `HttpOverrides` for outgoing calls, a
`package:logging` listener + zone print capture (the `GuestLogs` pattern), a
drift `QueryInterceptor`, thin `sqlite3`/`postgres` wrappers — ship as
**copy-paste snippets in docs**, not code in the package. Each is 10–40 lines
against the primitives; users own and adapt their copy. No `flutterware_shelf`
satellite package unless real demand appears.

### 6. Correlation via zones — the feature that makes it useful

The shelf middleware runs each handler in a zone carrying a request id
(`runZoned(zoneValues: {#fwRequestId: id}, …)`). `span` and `event` read
`Zone.current[#fwRequestId]` and stamp it on everything they emit. Every SQL
query, outgoing HTTP call, and log line automatically belongs to the request
that caused it — with zero user wiring beyond the middleware.

That is what upgrades the GUI from log viewer to inspector:

- **Per-request waterfall**: handler span with each query and outgoing call as
  a timed bar inside it.
- **N+1 detection**: same normalized SQL repeated ≥ threshold within one
  request → badge on the request row. Mechanical, no heuristics.
- **Error → cause**: an uncaught error carries the request that produced it.

### 7. Explain/requery run inside the server

The SQL adapter snippet registers `sql.explain` and `sql.requery` handlers
that execute against **the app's own live connection** — same database, same
credentials, same dialect. The GUI needs no DB driver and no connection
config; it sends a request frame and renders the answer. This is why the
command channel is non-negotiable and why SQLite-as-bus was rejected (below).

### 8. Memory: a bounded ring, replay on attach, nothing survives

- Per-channel event ring (default ~500 events) plus a byte-capped LRU side
  buffer (default ~16 MB) for bodies/result sets. Overflow drops oldest;
  events whose body was evicted still render, with "body evicted".
- On attach, the ring is replayed — start the server, exercise it, open the
  GUI *afterwards*, and the last N events are there.
- **Nothing survives a server restart.** A restart is a new handle (new pid
  suffix), a new session; the GUI keeps the previous session on screen,
  greyed out, until dismissed.

**SQLite / `sqlite_async` as the bus: considered and rejected** (2026-07-30):

| | |
|---|---|
| `watch()` is not push | it polls `pragma data_version` cross-process, ~100–200 ms, and says *that* something changed, not what. The 2026-05 doc accepted that for a *secondary* observer; this GUI is the primary surface. The socket is instant |
| It cannot replace the socket | explain/requery/lazy-body-fetch need an RPC into the live process. SQLite would be a **second** transport beside the socket, not instead of it |
| The dep lands in the user's server | `sqlite_async` → `package:sqlite3` → native library loading, in a process that may pin its own sqlite or run in a slim container. Exactly what decision 9 exists to prevent |
| Its one real benefit has a cheaper home | post-crash forensics. But any attacher present at crash time already holds the events; the uncovered case (crashed with nobody attached) is served by a future **attacher-side recorder** (GUI or `fw --record` persisting what it receives) — the process that wants memory pays for it |

### 9. GUI plugin and MCP shape

Standard five-file native plugin, id `server` (`lib/src/plugins/first_party.dart`
declaration, `server_core.dart`, `server_plugin.dart`, `server_address.dart`,
registered in both registries). Multiple servers are address segments:

```
fw://<project>/<worktree>/server/<name>/req/<requestId>
fw://<project>/<worktree>/server/<name>/sql
```

- `report`: "2 servers live" — from the run-dir scan cache, no connecting
  (fact 4).
- Attach on subscription (panel opens) or behind actions; never `computeAll`.
- Panel: unified filterable timeline; request detail (waterfall, headers,
  lazy-loaded body, replay); SQL view (normalized-query grouping, slow-query
  ranking, explain/requery); errors view with correlated request.
- MCP: plugin actions only — `server.status`, `server.requests` (filters:
  status class, path, last N), `server.request` (one, with correlated spans),
  `server.sql` (slow/grouped), `server.explain`, `server.errors`. All through
  `flutterware_invoke`; **the agent loop needs no GUI**: launch server → curl
  it → `flutterware_invoke server.requests` → see the request with its queries
  and timings.

## Non-goals for v1

- Persistence, history across restarts, session export (future: attacher-side
  recorder, decision 8).
- Bonjour/mDNS, cross-machine, Docker ergonomics beyond "set
  `FW_SERVER_INSPECT=1` and mount the run dir".
- Windows. The whole run-dir infrastructure is unix sockets already; a
  loopback-TCP fallback is a later, separate decision.
- Metrics/dashboards (rates, percentiles over time). The ring is a timeline,
  not a TSDB.
- `fw run server` restart-on-save sugar — worth doing, separately specced.

## Second round of decisions (2026-07-30, post-spike review)

The spike's four open questions, resolved:

### 10. Replay duplication: the core dedupes by event id; the wire stays dumb

Thinking this through surfaced a live bug in the spike core: on a transient
disconnect (drop with the server still alive), `TrackedServer` kept its dead
client for history and `_attach` skipped anything holding a client — a
"stopped" server that never reattaches while its handle still announces it.
The fix and the answer are one mechanism: **the core owns a merged event list
per server, deduped by event id** (already monotonic per server process), and
reattaches whenever the handle is present but the connection is not. A
re-replay dedupes to a no-op. The protocol stays replay-then-tail unchanged;
a `since:` parameter on `meta/attach` is the known extension *if* rings ever
grow, and is not built at 500 events.

### 11. Bodies: headers always (redacted in the snippet), capped textual
### bodies only, streams never

Buffer a body only when the content-type is textual (json / text / xml /
form-encoded) **and** content-length is known and under a cap (~32 KB
default). Chunked / SSE / unknown-length responses are never buffered —
record `{size, type, streamed: true}` — because interposing on the stream is
exactly the overhead this design refuses. Headers always, with
`Authorization` / `Cookie` redacted **in the middleware snippet** rather than
the library: redaction the user can see and edit beats redaction hidden
behind an import. Bodies live in the server-side LRU (decision 8), fetched
lazily via `http.body`.

### 12. SQL normalization is required, small, and attacher-side

Exact-string grouping cannot detect the headline N+1 — those queries differ
*precisely* in their literals (`user_id = 1/2/3`). So the normalizer is the
feature, not polish. The ruleset is the well-trodden one (numeric literals →
`?`, quoted strings → `?`, `IN (…)` → `(?)`, whitespace folded), a pure
function of ~20 lines. It runs on the **attacher side** — the wire carries
raw SQL, so normalization improves with flutterware releases without
touching anyone's server.

### 13. Uncaught errors: snippet only

The middleware already catches the dominant case — a handler throwing
becomes a correlated 500 event. What remains is errors outside any request,
and `runZonedGuarded` plus one `event('error', …)` is four lines in the
example. A `FlutterwareServer.run(…)` wrapper would be the first
required-looking call in a library whose pitch is "no init call".

## Third round of decisions (2026-07-31): the server describes itself

A server wants to publish more than traffic: where it listens, which
environment it is, its connection strings, arbitrary config, and the pages
worth a click (health, API docs, an admin UI). Decided in the 2026-07-31
brainstorm and built the same day.

### 14. Metadata is state carried as `info` events; the attacher reduces

Everything on the wire so far is a timeline; metadata is last-write-wins
state. Rather than a second mechanism, it rides the existing ring as an
`info` channel (new feature = new channel, decision 2): each event carries
whole *sections* — `baseUrl`, `environment`, `links`, `connections`,
`config` — and `ServerInfo.fromEvents` keeps the latest value per section.
Publishing again with only `config:` set updates config and leaves the links
alone. Replay-on-attach means a late-opened GUI still has it, dedupe
(decision 10) makes reattach a no-op, and the ring keeps the raw events, so
a feature flag flipping mid-session is visible in the Events tab for free.

### 15. A typed vocabulary, defined once for both halves

Not a freeform map: `ServerInfo` / `ServerLink` / `ServerConnection` in
`lib/src/server/info.dart`, published with `FlutterwareServer.info(…)` —
thin sugar over `event('info', …)`, so there is still no init call and an
`info` call in production code is a no-op like every primitive. The classes
serialize on the server side and parse (tolerantly, the `tryDecodeFrame`
stance) on the attacher side, so the vocabulary cannot fork. Typed is what
makes the display *useful*: links resolve relative URLs against `baseUrl`
and open in a browser, connections render with kind chips, config groups
render as tables. Publish after `serve` returns, so the port is real.

### 16. Secrets mask at display time, not on the wire

Connection strings are exactly what people paste from
`Platform.environment` without thinking. The wire — a local unix socket on
the developer's own machine — carries what the server chose to publish;
masking is an attacher concern, the same side as SQL normalization
(decision 12) and improving with releases the same way. `maskDsn` masks
URL-userinfo and `password=` segments; `isSecretLikeKey` masks config
values under secret-shaped keys. The GUI reveals per value on click and
copy copies the real string; action output (`fw`, MCP) masks without a
reveal, because terminals and agent transcripts have no click. True
redaction — what must not leave the process — still belongs to the
middleware snippet the user owns (decision 11's reasoning, unchanged).

### 17. The handle mirrors `baseUrl` and `environment` — deferred, then wanted

Mirroring `baseUrl` into `srv-*.json` lets `fw status` and the sidebar row
say where a server listens without a socket (`report` may not connect,
fact 4). First deferred — file churn, a second source of truth — with the
retrofit recorded; the wait for someone to actually miss the port in
`fw status` lasted one day. Landed 2026-07-31, same-day as the review that
asked for it, exactly as recorded: the inspector holds the two values from
`info` publishes and rewrites its handle when they change (including the
activation-order case, where the `info` call *is* the first event and the
values must land in the initial write). The mirror is those two fields
only and stays a convenience copy — the `info` channel remains the source
of truth, `tryRead` reads the fields tolerantly so a wrong-typed mirror
cannot unread a live handle, and pre-mirror handles read as before.
Attachers refresh `TrackedServer.handle` on rescan (identity is
`name-pid`; the file content is not part of identity), and the report row
becomes `pid 4242 · http://localhost:8080 · dev`.

### The surfaces

The panel gains an Info tab (`<name>/info` in the address vocabulary) with
links, connections and config groups, plus a promotion: the environment
chip and clickable base URL sit at the right edge of the tab row, visible
from every pane — quiet colors for dev-shaped names, red for
production-shaped ones, because an inspector forced on with
`FW_SERVER_INSPECT=1` should say where it is pointed. `fw` and MCP gain a
fourth action, `info`, masked as above.

## Where to pick up

**All five slices landed 2026-07-31**, plus a UI-review pass the plan did not
foresee: request detail became tabbed (waterfall / sql / request / response /
logs, the tab as an axis), the raw stream moved to an Events tab, and JSON
bodies render in a `JsonView` ported from the cms project's admin_ui. **The
self-description round (decisions 14–17) landed 2026-07-31 too.** What
remains beyond this spec is usage-driven: more adapters as real servers adopt
it, request replay, and whatever the next review round surfaces.

The original plan — five slices, correctness before surface area:

1. **Attach-loop robustness** (decision 10): core-owned merged store,
   reattach-on-drop, dedupe tests. The SQL normalizer (decision 12) lands
   here too — pure logic, needed by slice 2's badge.
2. **Request-centric UI**: request list + detail waterfall, N+1 badge,
   address segments `/server/<name>/req/<id>`.
3. **SQL view + commands**: normalized grouping table, slow ranking,
   explain/requery end-to-end, real adapter snippets (drift
   `QueryInterceptor`, `postgres`, `sqlite3`).
4. **Bodies** (decision 11): server-side LRU, `http.body`, middleware
   capture with caps + redaction, body viewer, request replay.
5. **Surface polish**: `server.errors` / `server.sql` actions, capabilities
   regen, a `Shot` in `tool/screenshots.dart`, README.

## The spike (S-slice)

**Ran 2026-07-30, same day — all four items and every exit criterion.** What
exists: `package:flutterware/server.dart` (primitives, gates, handle, ring,
handshake) with 19 socket-level tests in `test/server/`;
`examples/example/bin/example_server.dart` (shelf middleware + logging +
toy-SQL adapters inline); the `flutterware.server` plugin (core with 4 tests
in `app/test/plugins/server_core_test.dart`, timeline panel, `requests`
action); the `srv-*` probe rule in `sweepRunDir` with tests. Verified live: a
bare `dart run` server appeared in the GUI (captured via `fw capture`), the
`requests` action returned the correlated waterfall with no GUI running, and
a `dart build cli` binary served traffic and published nothing. One design
correction came out of it: `ServerAttachClient` **retains** events in a list
(`received`) with the stream as change signal only — the replay arrives in
the same socket flush as the hello, so a bare broadcast stream drops it
before any caller can subscribe. And one adapter lesson: a `package:logging`
listener must emit through `record.zone`, not its own zone, or log events
lose their correlation id.

The original plan:

1. `package:flutterware/server.dart`: gates (decision 3), lazy activation,
   handle file + socket, ring + replay, `event` + `span` + `handle`
   primitives. Pure Dart, no new deps.
2. The shelf middleware snippet (http channel + zone correlation) applied to
   a toy server in `examples/`.
3. GUI: `server` plugin with a raw timeline panel — connected state, replayed
   + live events in a list, request rows expandable to their correlated
   spans. No SQL view, no waterfall rendering, no replay-request.
4. `server.status` + `server.requests` actions, exercised through
   `flutterware_invoke` with no GUI running.

Exit criteria: IDE-launched and bare-`dart run`-launched toy server both
appear in the GUI without any flutterware-specific launch step; kill the GUI,
keep curling, reopen the GUI → recent history is there; MCP sees the same
requests with the GUI closed; a `dart compile exe` build of the toy server
provably binds no socket and writes no file.
