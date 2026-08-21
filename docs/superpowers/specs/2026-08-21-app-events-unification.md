# One report, whichever surfaces are listening

*2026-08-21. Built. Raised by a consumer running a 125-scenario suite that
already wires the devbar in six entry points.*

## The report

There were two app-side places to say what the app did, and a project had to
wire each separately:

| | the call | landed in |
|---|---|---|
| devbar | `devbar.maybeNetwork?.request(…)`, via `DevbarHttpClient` | the devbar's Network tab |
| scenarios | `recordScenarioEvent(ScenarioEvent.request(…))` | the step's Events pane |

Neither knew the other existed — zero cross-references in either direction,
confirmed by grep before anything was changed. So a project that wired the
devbar, which is what the devbar's own docs tell it to wire, got an empty
Events pane, and vice versa. Both calls report the same fact about the same
app.

The `log` channel was already the shape that works, and it is worth saying why:
`LoggerPlugin` and the harness both listen on `Logger.root.onRecord`
themselves, so the project writes nothing and both surfaces are full. `network`
and `analytics` were the same concept solved the other way round — each surface
asking the project to call *it*. `db` had no devbar equivalent at all:
`DatabasePlugin` is a *browser* over a `DatabaseAdapter`, and never sees a
statement the app itself issued.

## The correction that shaped the fix

The report proposed fanning out to "{a mounted devbar, a capturing scenario}".
But **a devbar plugin method can never fire inside a scenario** — no `Devbar`
is mounted, so `Devbar.instances` is empty and `devbar.analytics.log(…)` is
unreachable rather than merely unheard. Forwarding *from* the devbar's plugin
methods buys nothing.

The one exception is `DevbarHttpClient`, which is a `Client` wrapper that
exists whether or not a devbar is mounted. That is the only devbar-side thing
with a live path into a scenario, and it is where most of the value is.

That collapses the design to one direction of call:

- **`recordAppEvent` is the app's door.** It writes `appEventBuffer` and
  notifies every listener registered through `addAppEventListener`.
- **A reporter that has already served one surface tags itself, and that
  surface alone skips it.** `DevbarHttpClient` has handed each mounted devbar
  the exchange in two halves already, so it reports the completed one with
  `source: devbarHttpClientSource`, and the devbar's listener registers with a
  matching `ignoreSource`. Everybody else — the buffer, and any listener a
  project registered — sees it normally.

  *This was a bypass first: the client wrote `appEventBuffer` directly, which
  did stop the double row but hid every `package:http` request from
  third-party listeners as well, because `addAppEventListener` is published.
  Caught in review; the tag is the version that only suppresses the one
  surface that asked to be suppressed.*
- **The devbar routes only the channels it has no source of its own for** —
  `network`, `analytics`, `db`. `log` is excluded because `LoggerPlugin`
  listens at the source; routing it would double every record. `print`,
  `platform` and `system` have no live-app collector at all.

## Where the registry lives, and why not the other way round

`lib/src/app_events/events.dart` is import-free, which is the whole reason
`package:flutterware/app_events.dart` can be imported from a project's `lib/`
without dragging in `flutter_test`. So the fan-out is a listener registry
there, and the devbar registers *into* it. The dependency runs devbar →
events, never events → devbar.

### Dispatch may not disturb the app, and that took three goes

`recordAppEvent` is documented as safe to leave in a shared fake forever. The
first version of the dispatch broke that promise in three ways, all found in
review and all now pinned by tests:

1. **It walked the live list by index.** That avoids the concurrent
   modification a for-in would throw, but a listener that unregisters itself
   shifts its neighbour into the slot just read — so the neighbour is
   *skipped*. Two mounted devbars, one disposing mid-report, and the survivor
   silently missed the event. Dispatch walks `List.of(_listeners)`, which is
   correct for removal and for addition.
2. **It let a listener's exception through.** A surface that breaks would
   abort the app's own call — a line in somebody's fake. Each listener now
   runs in a `try`, and a throw goes to `Zone.current.handleUncaughtError`:
   loud, but not in the caller's face. (`dart:async` is the only import this
   library has, and it is a core one; the Flutter-free property stands.)
3. **The devbar registered its listener without checking it was still
   mounted.** A plugin factory may await — the example's `VariablesPlugin.init`
   waits on a directory — and `dispose` can run first, doing its half of the
   teardown before there is anything to tear down. The registration then
   outlived the devbar: one leaked listener per mount, each routing into
   plugins that had been disposed, so `recordAppEvent` threw
   `StateError: Cannot add new events after calling close` out of the app's own
   call. `_loadPlugins` guards both that and `DevbarBridge.mount` on `mounted`
   now — the bridge had the same latent shape.

## Renamed, because the old name was half the confusion

Owner decision: the function and the type both move, breaking change and all.
`ScenarioEvent` named the surface that read it rather than the thing it was,
which is exactly the miscue that made a project conclude the feature did not
work. The file moved out of `lib/src/scenarios/` for the same reason.

| was | is |
|---|---|
| `ScenarioEvent` | `AppEvent` |
| `ScenarioChannel` | `AppChannel` |
| `recordScenarioEvent` | `recordAppEvent` |
| `ScenarioEventBuffer` / `scenarioEventBuffer` | `AppEventBuffer` / `appEventBuffer` |
| `maxScenarioEventsPer{Step,Run}` | `maxAppEventsPer{Step,Run}` |
| `package:flutterware/scenarios.dart` | `package:flutterware/app_events.dart` |
| `lib/src/scenarios/events.dart` | `lib/src/app_events/events.dart` |

`AppChannel` and not `EventChannel`: the latter collides with
`package:flutter/services.dart`. `recordAppEvent` and not `report`: `report`
already names the scenario *run* report in this repo
(`lib/scenarios_report.dart`, `ScenarioRunResult`), and it is a very broad
symbol to export into an app's namespace.

The wire format did not change. `.events.json` still carries `channel`,
`title`, `detail`, `data`, `body`, `error`, `level`, so `scenarioRunReportVersion`
did not move and an old run still reads.

## The `db` tab

`LogQueriesPlugin` — a `Queries` tab under `Logs`, beside `Network`,
`Analytics` and `Logger`, fed only by the `db` channel. It is the log next to
`DatabasePlugin`'s browser, which is the split
`2026-08-12-sqlite-watch-design.md` § *Relation to scenario query events*
called for. It is opt-in like every other devbar plugin, and deliberately has
**no project-facing ingest method**: the documented door is `recordAppEvent`,
so a project's `CommonDatabase` wrapper is written once and both surfaces fill.

## The one place the shapes genuinely differ

The devbar's Network tab is a correlated *pair* keyed by id — `request(id, …)`
then `response(id)`/`responseError(id)` — so it can show a request while it is
still in flight. An `AppEvent` is one completed event. `LogNetworkPlugin.reported`
takes the completed form and builds a row with `timed: false`, so
`NetworkRequest.watch` is null and the tile shows no duration rather than a
false `0ms`. `AppEvent` carries no duration to give it — the 2026-08-11 owner
decision ruled durations out because `FakeAsync` makes them meaningless, and
that still holds.

An `AppEvent` carries its body as *text*, and the Response tab renders through
`JsonViewer`, which JSON-encodes whatever it is handed — so a reported body
went in as text and came back as one escaped line with quotes round it, where
the same tab shows a tree for an exchange this process watched. `reported`
decodes a body that parses as JSON; the tab renders anything still a `String`
as text, which also improves the `<unknown>` placeholder the watched path has
always put there.

`reported` splits the title at the first space to recover method and path,
which is the exact inverse of what `AppEvent.request` composed; a network event
made by `AppEvent.custom` keeps its whole title as the path, which is the only
honest reading of it. Reported rows take negative ids so a late `response(id)`
meant for an in-flight `DevbarHttpClient` request can never land on one.

## The agent surface: light was right, digging did not exist

Audited after the unification landed, on the question of whether an agent
running scenarios over MCP is handed the events lightly *and* can get at the
rest. The first half was already right — `run` summarises each step as
`eventCount`, `eventChannels`, `eventTitles` and the `events` path, and
`steps: failing|all|none` bounds the volume. The second half was missing
entirely, in four measured ways:

- **`read` was blind to events.** The one action built for "ask this step
  more" — `find`, `at`, `styles`, `tree` — could answer nothing about what the
  app *did*.
- **Pointing `read` at the `.events.json` leg silently answered about the
  widget tree.** `_captureLegs` accepts that extension and `_baseOf` strips
  it, so the reply came back about a different question than the one asked,
  with `step` rewritten to `.tree.json`. A reply may refuse; it may not
  substitute.
- **`read` did not even carry the path**, so an agent starting from the
  failing-step read — the read that happens most — had no pointer at all.
- **The raw file was the only door, and it is mostly chatter.** Measured over
  the example suite: 46 `.events.json` files, 30,459 bytes, of which 701 (2%)
  is non-`system` — 183 framework events against 6 reported ones. No filter by
  channel, none by `error`. `system` is the channel the GUI hides by default
  and `eventTitles` already excludes; every consumer agreed it was noise
  except the only door an agent had.

Built as one flag lane on the existing grammar, so there is nothing new to
learn: `events: true` for the payload, `channel: network,db` to narrow,
`errors: true` for the ones that are themselves a problem. `system` is
excluded unless `channel` names it, which is one parameter instead of two.
`channel` and `errors` imply `events`, and so does pointing `step` at the
events leg. A filter that matches nothing answers with an empty list and a
note saying what the step *did* record, because going quiet is
indistinguishable from a quiet step.

`eventCount` and `eventChannels` ride on **every** read whether or not events
were asked for, and the `next` line names the flag when the step has any —
a schema read once at connection time is not where an agent looks on step
forty.

The same reasoning applies to the inline cap: `eventTitles` now ends with
`… N more — scenarios read events: true` rather than truncating at twelve in
silence. The count it reports is of the *titles*, after the `system`
exclusion, because that is the number a reader would otherwise think they
were seeing all of.
## A title is the statement, not its first keyword

Reported by the same consumer wiring the `db` channel, measured at `5e96ddd`.

`AppEvent.query` took its title from the first line of the SQL. A generator
emits one line, so a generated statement titled whole; a person formats theirs
across several with the keyword alone on the first, so it titled `select …`.
On their suite that was **110 of 194 db events** — half the channel saying
nothing, and which half depended only on who wrote the SQL, which is not a
distinction the pane means to draw.

**The comparison channel is why this mattered more than legibility.**
`EventChannel.mask` keys an event on its channel and its title, so every
hand-formatted `select` was one key. They flagged it as latent and said
plainly they had not observed it. Built as a test, it is worse than a merged
row: base runs the task query, head runs a users query instead, and
`EventChannel.of` returns `added: [], removed: []` — no difference at all, on
the channel whose whole job is to notice. Now pinned in
`app/test/comparison/channels_test.dart`.

**Folded, not normalized.** Their suggestion was to title with `normalizeSql`,
which already folds whitespace and exists two subsystems over for exactly the
"reduce a statement to its shape" job. Declined for the display half: it
blanks literals, so `version >= 3` reads `version >= ?` and the value goes
back into `body` one expand away — which is the complaint the report opened
with, relocated rather than fixed. Folding whitespace and keeping the literals
gets legibility *and* the values for the same row width.

Grouping is unharmed by keeping them: `mask` already folds digits to `#`, so
an N+1's siblings — which differ precisely in an id — still meet. That is
pinned too, because it is the property the fold could plausibly have broken.

One argument of theirs that does not transfer, recorded so it is not
re-litigated: `normalizeSql`'s docstring keeps the rules attacher-side so they
"can improve with flutterware releases without touching anyone's server". A
scenario's events are regenerated every run, so nothing freezes app-side and
that reasoning does not argue against normalizing in `AppEvent.query`. The
literals argument is the one that does.

**`normalizeSql` had a bug beside it.** `?1` — sqlite's numbered placeholder,
what `sqlite3`/`sqlite_async` emit — fell past the explicit `$1` rule into the
bare-number one, which ate the digit and left `??`. Stable enough to group by,
and reading as a typo wherever the result is shown. The placeholder rule takes
`[$?]\d+` now.

**And a trap in the docstring.** Opening a database costs a dozen statements
before the app has done anything — `BEGIN IMMEDIATE`, the migration
bookkeeping, the `create table`s, `COMMIT`. Across 125 scenarios that was 1680
of 1874 events, 89% of the channel. It takes measuring to notice, because a
busy pane looks like a working one. `AppEvent.query` says so now, since
everyone following the `LogQueriesPlugin` recipe meets it.

Beyond what was asked: the database browser's own panel feed cut at the first
line the same way, and there the SQL is *typed by the person reading it back*.
Folded too — leaving one of two identical defects would have been the
inconsistency this removes.

**A second cap, on width, once a db title became a whole statement.** A
summary is bounded by rows times width and only the rows were. Twelve titles
at the stored 300-character limit is 3,600 characters on one step; measured
with folded SQL, twenty hand-formatted queries on one step put 1,980 bytes in
the run's answer, and 1,639 at 120 characters each. The saving on that case is
17% — the point is the ceiling, which is now known whatever an app reports:
the same twenty queries with 5,000-character titles still fit in 1,600 bytes.
The detail is appended after the cut, never inside it, because `→ 500` is a
handful of characters and most of what the line is read for.

## Silence, which was the part that bit

An Events pane fed by nothing showed `Nothing happened on the way to this
step`, and could not distinguish that from "this project reports somewhere
else". It now names the door — `recordAppEvent`, or wrapping the client in
`DevbarHttpClient` — and says a mounted devbar shows the same reports.

## Answered, not built

**Mounting a `Devbar` under `flutter_tester`** was raised as a possible
alternative. It is not one, whether or not it works: `isHeadless` defaults to
`GuestChannels.installed`, false under the tester, so the overlay's `Stack`,
`FittedBox` and `Navigator` would sit in the very tree a scenario's targets and
captures walk — the hazard `Devbar.headless` documents. And the plugins collect
into `ValueStream`s that nothing in a run reads. Reasoned from the code, not
measured; the conclusion does not depend on which way the measurement goes.

## Open

- **Web and wasm.** Everything here was built and run on macOS and
  `flutter_tester`. The registry is plain Dart with no platform surface, so
  there is no reason for it to differ, but nothing has run it there.
- **The `print`, `platform` and `system` channels have no live-app collector.**
  A devbar tab for them is possible and was not built — nothing has asked.
- **The transports are still not merged.** `appEventBuffer` and the panel ring
  remain two hosts of one concept, for the reasons in
  `2026-08-12-sqlite-watch-design.md`.
