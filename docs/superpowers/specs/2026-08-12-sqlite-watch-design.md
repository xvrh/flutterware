# SQLite watch — the app's database, on every surface

**Date:** 2026-08-12
**Status:** Designed with the owner in conversation, 2026-08-12. **Built and
S-DB1 spiked the same day** — the loop ran end to end over MCP against
Brewline and the design held; results in
`2026-08-12-sqlite-watch-spike-findings.md`. S-DB2 (powersync) remains open
and still gates Decision 4. The time machine — scrub back to seq 1, capture
sidecar — is deliberately *not* in this design; it stays deferred under the
name WIRE·LINE (§ Deferred).

**Lineage:** `2026-08-11-devbar-run-bridge-design.md` § Deferred: WIRE·LINE —
the three prototype-review findings recorded there (PowerSync's own schema
carries the changes; successful sync destroys the evidence; capture is in-app
because a physical device's database is sandboxed) all hold and shaped this.
`2026-07-30-server-inspection-design.md` — the precedent this follows on
dependencies: flutterware defines the seam, the adapter is a pasted recipe,
and SQLite-as-anything was already rejected once for dragging native loading
into processes that did not ask for it. `2026-07-31-app-launcher-cockpit-
brainstorm.md` §S-L4 — "one toy SQLite plugin over a devbar channel" was the
spike that motivated the panels bridge; this design is that toy grown up.

## The goal

The app is running — on the desktop, on a phone — and its database is visible
from outside it. Browse the schema, run a query, pin a query and watch it
change, follow the writes as they happen. From the cockpit, from `fw`, from
MCP, without a rebuild. First consumer after the built-ins of the panels
bridge, and the first one an agent will reach for: "run this SELECT against
the live app" is the debugging move the MCP surface has been missing.

## What already exists, measured 2026-08-12

| what this feature needs | what is in the tree today | gap |
|---|---|---|
| a wire out of the app | the panels bridge (#101): `DevbarPanelSource` → cockpit, `fw run run panelInvoke`, MCP, overlay — all from one descriptor | nothing |
| an append-only change feed | `Panel.feed`/`emit`, ring buffer with replay-on-attach and lazy `details` fetch | nothing |
| a command with typed params | `PluginAction` with `danger:`, already a form in the GUI, flags in `fw`, a schema for agents | nothing |
| per-row commands | `itemAction` — whose design example is literally `sql/explain` | nothing |
| row-level history for replicated tables | PowerSync's `ps_crud` / `ps_oplog`, plain tables readable by SQL | a tail (§ Decision 4) |
| a sqlite dependency | none, and three docs that decided against one | keep it that way |

**The finding that sets the scope: v1 ships without touching `app/` at all.**
Every surface renders panels generically already. The whole feature is one
file in flutterware core, a recipe in the docs, and a dogfood in the example.

## Decision 1 — a generic adapter, no sqlite dependency (owner, 2026-08-12)

flutterware never imports sqlite_async, powersync, or sqlite3. The seam is
four function types and a name:

```dart
class DatabaseAdapter {
  DatabaseAdapter({
    required this.name,   // 'main' — the panel becomes db:main
    required this.query,  // Future<List<Map<String, Object?>>> Function(String sql, List<Object?> args)
    this.updates,         // Stream<Set<String>>? — table names, per write transaction
    this.watch,           // Stream<List<Map<String, Object?>>> Function(String sql)?
    this.execute,         // same shape as query; its presence is the write opt-in
  });
}
```

The recipe the app author pastes — and `PowerSyncDatabase` implements
sqlite_async's interface, so the powersync recipe is the same lines:

```dart
DatabasePlugin.init(
  database: DatabaseAdapter(
    query: (sql, args) => db.getAll(sql, args),
    updates: db.updates.map((u) => u.tables),
    watch: (sql) => db.watch(sql),
  ),
)
```

Why not depend directly: a hard dep means an app pinning a different
sqlite_async major cannot resolve *flutterware itself* — the blast radius is
the whole tool, not the feature. Why not a `flutterware_sqlite_async` shim
package: the adapter is five lines; a package holding five lines is a version
to keep in sync forever. Why powersync needs nothing at all: everything
powersync-specific in this design is *table names in SQL strings*
(§ Decision 4), not API.

`watch` is optional and deliberate: sqlite_async's own `watch()` already does
source-table inference and throttling, and delegating beats re-implementing
inference. When absent, a watch falls back to re-query on any `updates` tick,
throttled — correct, just wasteful.

## Decision 2 — one panel per database: `db:<name>` (owner, 2026-08-12)

Multiple databases are multiple `DatabasePlugin` instances, panel ids
`db:main`, `db:cache`. The alternative — one panel with a `database` parameter
on every action — makes feeds unrenderable per-database and was rejected. The
bridge's `#2` disambiguation is not relied on; names are the identity.

## Decision 3 — what v1 serves (owner, 2026-08-12)

- **`state('schema')`** — tables, columns, row counts. Empty `fields`: "show
  whatever comes back" is the honest declaration for a shape the renderer has
  no business curating.
- **`action('query')`** — `sql`, `args`, `limit` (default 100). The reply is
  `{columns, rows, rowCount, truncated}` — truncation visible, never silent,
  because an action reply travels inline in the frame; there is no lazy
  details fetch for action results (that mechanism is per ring event). The
  hard cap is measured in S-DB1, not guessed here.
- **`feed('changes')`** — table-level ticks from `adapter.updates`, coalesced
  plugin-side in a ~250ms window into `{tables, transactions, at}` so a sync
  burst costs a handful of events, not thousands. sqlite_async already
  coalesces per transaction; this coalesces across them.
- **`action('watch')` / `action('unwatch')` + one static `feed('watch')`** —
  all watches share the one feed. `watch {sql}` answers with a watch id; each
  result snapshot is an event `{watchId, sql, rowCount, at}` with the rows in
  `details`, fetched only when someone looks. Chosen over a dynamic feed per
  watch because **the vocabulary has no `removeFeed`** (only knobs are
  removable), and over building `removeFeed` because a shared feed needs no
  vocabulary surgery and renders as a history of snapshots — which is more
  useful than a mutating table, because the diff between ticks is visible.
- **`itemAction('explain')`** on the watch feed — `EXPLAIN QUERY PLAN` for
  the snapshot's SQL, the design example made real.
- **Writes**: the `execute` function's *presence* is the entire gate. No
  function → the action does not exist → no surface can see it, agents
  included. Provided → `action('execute', danger: true)`. No runtime knob on
  top; the app author opting in is the decision, made once, in code. A happy
  accident worth recording: with the reference wiring, `query` runs on
  sqlite_async's read pool, so even a hostile `query('DELETE …')` dies at the
  sqlite layer.

**Not in v1, on purpose:** a bespoke table-browser renderer in the cockpit.
`PanelView` renders all of the above today; the query action *is* the browser.
A dedicated surface would be the first panel-specific renderer, breaking the
one-renderer symmetry the bridge design bought — additive later, and it
changes nothing on the wire.

> **Reversed the same day (owner, 2026-08-12).** The human review was blunt:
> empty feed panes and a "Controls" form are not how a person meets a
> database. The cockpit now special-cases `db:*` panels with
> `DatabasePanelView` (`app/lib/src/run/database_panel_view.dart`) — tables
> sidebar with live row counts, a data grid that follows writes, a SQL
> editor, the activity stream — over the unchanged wire. `PanelView` stays
> the renderer for every other panel and for this one on `fw`/MCP. The
> deferral was right about the wire and wrong about the person; see the
> spike findings' addendum for the two transport bugs the bespoke view
> flushed out.

## Decision 4 — the PowerSync bonus feed, gated on S-DB2 (owner, 2026-08-12)

If `sqlite_master` shows `ps_crud`, the plugin declares **`feed('uploads')`**
and tails it: on a tick naming `ps_crud`, SELECT rows above the last seen id,
emit each `{id, op}` with the row JSON in `details`. Detection and tailing are
SQL by table-name convention — no powersync dependency, per Decision 1.

WIRE·LINE finding 2 said successful sync destroys the evidence: `ps_crud`
drains on ack. The tail is what survives it — **the ring is a bounded time
machine for free.** Events outlive the rows they describe, replay to a host
that attaches late, and cost nothing when nobody is watching. It is the
capture sidecar's miniature edition, and deliberately not the full one
(§ Deferred).

Two unknowns gate this whole decision, and they are exactly S-DB2: whether
`PowerSyncDatabase.updates` fires for internal tables at all (it may filter,
or remap `ps_data__todos` → `todos`), and whether tick → SELECT wins the race
against the uploader's DELETE often enough to matter.

## Relation to scenario query events (owner raised, 2026-08-12)

Scenarios already have a `db` channel: a fake or an in-memory sqlite layer
calls `recordScenarioEvent(ScenarioEvent.query(sql: …, args: …, rows: …))`
and the statement lands on the transition
(`2026-08-11-scenario-transition-events.md`, lane 3). Should this design
uniformize with that? In three parts:

- **v1 does not overlap.** The scenario channel records *queries the app
  executed* — push, from instrumentation the author wired. This design's v1
  records *state and changes* — pull, through the adapter. Complementary
  directions; neither can replace the other, and nothing in v1 collides.
- **The trace, when it lands, is one capture with two sinks.** "Watching the
  queries" live (§ Deferred) and the scenario `db` channel want the *same
  record* from the *same interception point*. Whatever the capture turns out
  to be — the upstream sqlite_async hook or a delegating wrapper — it must
  report through one entry point that routes to whoever is listening:
  scenario buffer in a scenario, the panel's future `queries` feed in a live
  run, a null check nowhere. The app instruments once and both surfaces
  light up. `recordScenarioEvent`'s own contract ("safe to leave in shared
  fakes forever") is the model, and this is the strongest argument yet for
  the upstream hook over per-surface wrappers.
- **The vocabulary is shared now, so the shapes cannot drift later.** The
  future `queries` feed uses the keys `ScenarioEvent.query` already fixed —
  `sql`, `args`, a row *count* — and v1's watch feed carries its SQL under
  `sql` for the same reason. An agent that learned to read one surface has
  learned the other.

Not uniformized: the transports. `scenarioEventBuffer` and the panel ring are
the same concept on two hosts — bounded, capped loudly, drained by a reader —
but one lives in a FakeAsync test process writing artifacts and the other
behind a VM-service nudge. Merging them buys nothing v1 needs and couples the
two lifecycles. Worth recording as a door: a live app's fakes calling
`recordScenarioEvent` could someday feed a panel feed, which would make every
scenario-instrumented app observable live for free.

## Experiments

**S-DB1 — the loop, end to end.** sqlite_async in `examples/example`, the
recipe as pasted above, driven over MCP. Must answer: query round-trip time;
what a 10k-row write burst does to the `changes` feed with and without the
coalescing window; where inline action replies actually start to hurt (sets
the row cap); whether `details`-carried watch snapshots render acceptably in
the cockpit and read acceptably over `panelInvoke`.

**S-DB2 — powersync tick semantics.** Against a real powersync app. Must
answer: does `updates` tick for `ps_crud`; are table names raw or remapped;
does the tail read rows before drain under a real sync. A no on the first
question demotes the uploads feed to polling or kills it.

## The build

1. `lib/src/devbar/plugins/database.dart` — `DatabaseAdapter` +
   `DatabasePlugin implements DevbarPlugin, DevbarPanelSource`, exported from
   `lib/devbar.dart`. Order of 250 lines; the notifications panel is the
   reference shape. `dispose` cancels the updates subscription and every
   watch; hot reload is already safe (`Panels.add` replaces by id).
2. Tests against a fake adapter — pure Dart, zero dependencies: scripted
   query results and a hand-fired updates stream. Coalescing, watch
   lifecycle, truncation, the write gate's absence-means-absent.
3. sqlite_async into `examples/example` only, as the dogfood (S-DB1 rides
   this).
4. The recipe into the published docs, next to the server-inspection SQL
   adapters it imitates.

## Open, deliberately

- **Which real powersync app runs S-DB2.** Without one, Decision 4 stays
  paper. There is a candidate consumer with a live powersync stack.
- **The watch fallback throttle** when the adapter has `updates` but no
  `watch` — 250ms to match the coalescing window, until measured.
- **Watch snapshot coalescing.** S-DB1 measured the mismatch: sqlite_async's
  native watch throttles at 30ms, so one burst produced 13 snapshots against
  the changes feed's 2 events. The recipe passes `throttle:` for now; whether
  the plugin should coalesce snapshots itself is open until someone is
  actually hurt by it.
- ~~**Whether a table-browser renderer earns its place** after v1 has been
  driven by a human for a week.~~ It took one day, not a week — built, see
  the reversal note under Decision 3.

## Deferred

- **WIRE·LINE proper.** Scrub to seq 1, persistent capture, reconstruction.
  The ring's bounded tail (§ Decision 4) is the down payment; whether "history
  starts when you attached" is acceptable or reconstruction is required stays
  the open question the bridge design recorded.
- **SQL trace — watching the queries.** Neither `package:sqlite3` (Dart) nor
  sqlite_async exposes `sqlite3_trace_v2`. A trace therefore means either a
  delegating wrapper the app builds its database through — invasive, and
  blind to every query that bypasses it, including powersync's internal sync
  queries, which are the interesting ones — or an upstream hook in
  sqlite_async that powersync would inherit. The upstream route is the one
  worth pursuing, and whatever the capture is, it reports through the shared
  entry point (§ Relation to scenario query events) so scenarios and live
  runs light up from one instrumentation. Nothing in v1 blocks on it.
- **Zero-config auto-discovery.** The guest could depend on `package:sqlite3`
  alone, find `*.db` files under the documents directory, and open a second
  read-only connection in-process — browse plus `PRAGMA data_version` polling
  with no app code at all. Rejected for now on the server-inspection
  precedent (native loading into processes that did not ask) and because the
  five-line recipe is cheap; worth revisiting if the recipe turns out to be
  the adoption blocker.
