# S-DB1 findings — the sqlite watch loop, end to end

**Date:** 2026-08-12. The spike gating
`2026-08-12-sqlite-watch-design.md`, run against the build it gated: the
`DatabasePlugin` recipe wired into Brewline (`examples/example/lib/
shop_devbar.dart`), sqlite_async over a real file, driven entirely over MCP
(`panels` / `panelInvoke` / `panelState` / `panelKnob`) against the app
running on macOS. Method for every timing below: the ring's own event
timestamps and the app's `Stopwatch` prints — not wall-clocking MCP calls,
which measure the transport rather than the feature.

**Verdict: the design holds.** Every v1 surface worked over the wire on the
first run — schema, query with loud truncation, the coalesced changes feed,
watch with details, explain on a ring event, the execute gate in both its
absent and present forms. Four findings adjust the margins, none the shape.

## Measured

- **Write → tick → watch snapshot ≈ 8ms in-app.** A push insert landed on
  the `changes` feed 5ms after the inbox event and the watch's re-query
  snapshot 3ms after that (ring timestamps `.628 → .633 → .636`). The panel
  is effectively synchronous with the database at human timescales.
- **Coalescing does its job under a real burst.** 201 write transactions
  (200 single-row inserts in 194ms + one 10k-row batch, which is a single
  transaction) became **two** `changes` events: the leading edge and one
  merged `{tables: burst, transactions: 201}`. A slower 445ms burst spanned
  two windows and became three. Uncoalesced this would have been ~200 events
  per second.
- **A 1000-row inline reply is ~30KB and survives fine.** The pain is not
  the reply, it is the fetch: `rowCount: 10200` proves `adapter.query`
  pulled the whole table before the reply-side cap. The action description
  already says "put a LIMIT in the SQL to page a big table," and that stays
  the real protection. Default limit 100 confirmed sensible; no hard cap
  added — nothing measured argues for one yet.

## Findings that adjust the design

1. **The native watch throttle is 30ms, our coalesce window is 250ms, and
   the mismatch shows.** During the burst, one watched `count(*)` emitted
   **13 snapshots ~35ms apart** — sqlite_async's default `throttle`. Correct,
   but noisy in the ring, and for a fat SELECT it would be 13 × 500-row
   details per burst. The recipe should pass a throttle
   (`db.watch(sql, throttle: const Duration(milliseconds: 250))`) and the
   docs should say why; whether the plugin should coalesce snapshots itself
   is a v2 question, noted in the spec.
2. **Feeds are readable over MCP/CLI after all** — the `panels` action tails
   recent events per channel in its `events` map. Session-note correction:
   an early read of `run_core`'s action list concluded feeds were
   cockpit-only; wrong. What is *not* reachable from `fw`/MCP is a feed
   event's lazy **details** — an agent that wants a watch snapshot's rows
   re-runs `query`, which costs one call and is equivalent. No change needed
   for v1; a `panelDetail` action is the additive fix if it ever hurts.
3. **The watch error path is a feature, seen live.** A watch armed before
   its table existed reported
   `no such table: burst … Causing statement: EXPLAIN SELECT …` on the feed
   and cancelled itself — and the `EXPLAIN` in that message is sqlite_async's
   own source-table inference, confirming the native watch is genuinely
   delegated to, not re-implemented.
4. **The read-pool refusal is real, not a comment.** `DELETE FROM
   notifications` smuggled through `query` died in sqlite:
   `attempt to write a readonly database (code 8)`. The reference wiring's
   `getAll`-on-the-read-pool is an enforced gate, not a convention. The
   `execute` door — added to Brewline as the opt-in showcase — then dropped
   the spike's scratch table over the wire, danger-flagged.

## Also observed

- Hot restart (~1s) rebuilds the panel cleanly from the plugin's
  constructor; watches and knob values are gone with the rest of the app's
  state, as they should be. Registration survived a restart that *changed
  the adapter* (execute added) — the new action simply appeared.
- The burst under an active watch ran 200 txns in 445ms vs 194ms without —
  the fallback cost of a watch re-querying against a busy write connection
  is visible but not pathological.

## Scaffolding

The burst hook (a push titled `db-burst` triggering 200 inserts + a 10k
batch) lived in `AppDatabase` for the duration of the spike and was removed
after. The `burst` table was dropped through the panel's own `execute`.

## Addendum, same day: the human review, and the two bugs it flushed out

The owner's verdict on the generic `PanelView` rendering of the panel was a
flat rejection — empty feed panes on open, the query form hiding under
"Controls", no tables anywhere. The measured wire was fine; the surface was
not. `DatabasePanelView` (cockpit-side, `db:*` panels only) replaced it the
same day: schema loads on open into a tables sidebar, the first table's grid
is on screen immediately, the grid re-queries when a `changes` tick names
the visible table, and the SQL editor and activity stream ride the same
actions and feeds. Wire unchanged; `fw`/MCP unchanged.

Being the **first surface that needed an asynchronous panel reply pushed to
an already-attached host**, it found two transport bugs that had been
invisible under sync-only traffic:

1. **The nudge's in-call suppression was transport-global.** An event
   broadcast while *another* peer's exchange was in flight (a `panelInvoke`
   over MCP) queued on the cockpit's peer but was never nudged — the frame
   sat unread until an unrelated re-attach, which is why a cockpit watching
   a feed while an agent drove the app saw nothing. Fixed: the suppression
   is now per-serving-peer (`vm_transport.dart`), with a regression test
   (`test/server/vm_transport_test.dart`).
2. **Cockpit peer ids were not unique per attachment.** A re-created panels
   pane racing its predecessor's async detach shared the id; the detach tore
   down the new peer and every in-flight reply died on the orphaned queue —
   the schema spinner that never resolved. Fixed: the peer id carries a
   per-pane nonce (`panels_tab.dart`).

Every earlier consumer had survived on synchronous round trips and
attach-time replay, so the nudge path had effectively never been exercised
end to end. The lesson for the bridge: a transport claim ("the app nudges,
the host pulls") is not verified until a surface *needs* it — the sync
window was hiding a dead half of the protocol.
