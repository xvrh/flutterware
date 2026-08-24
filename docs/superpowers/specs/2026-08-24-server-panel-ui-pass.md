# Server panel: a second UI pass

**Status:** decided 2026-08-24. §3 → **A2** (split with a grip). §4 → **B1**
(header popover, Info leaves the tab strip).

Everything below was read off the running panel on 2026-08-24 — Studio (dev) on
macOS, driven against `examples/example/bin/example_server.dart` with a dozen
requests through `/users`, `/slow`, `/echo`, `/error` and `/health`. Line
numbers are `app/lib/src/plugins/native/server_plugin.dart` unless said
otherwise.

The panel's *content* is good: the N+1 finding, the waterfall, copy-as-curl,
explain/requery, the masked DSNs. What has not been paid for is the surface
around it — the list rows, the way a detail opens, whether text can be taken
somewhere else. That is what this pass is.

## 1. What is actually wrong

### 1.1 SQL is drawn as prose, not as SQL

Every place a statement appears — the shape list (l. 545), the query detail
header (l. 636), the occurrence rows (l. 733), the request's SQL tab (l. 1210),
the waterfall labels (l. 1481), the N+1 banner (l. 1140), the Events rows
(l. 1957) — it is a single `Text`/`SelectableText` in `context.type.mono` with
no colour.

The tokeniser is already here and already speaks SQL. `app/lib/src/ui/syntax.dart`
registers `lang_sql` among its eighteen grammars, and `codeSpans(context, source,
language: 'sql')` returns palette-coloured spans. Two call sites already use it
(the diff rows, the scenarios help page). The server panel is the third that
should and does not.

The normaliser's `?` placeholders tokenise fine — they are operators to the
grammar, not errors.

### 1.2 Statements cannot be taken anywhere

Mixed, and the mix is the problem — you cannot learn a rule:

| where | today |
|---|---|
| shape list row | `Text` — not selectable |
| query detail header | `Text` — not selectable |
| occurrence row | `Text` — not selectable |
| request SQL tab, collapsed | `Text` |
| request SQL tab, expanded | `SelectableText` |
| Events row | `Text` |
| explain result | `SelectableText` inside `_Slab` |

There is no `SelectionArea` anywhere in the panel, so even the `SelectableText`
rows cannot be dragged across — a selection that cannot cross a row is not a
selection of a query.

The precedent is already written down. `changes_screen.dart:2470` puts **one**
`SelectionArea` over the whole diff body and says why: *"a selection that cannot
cross a line is not a selection of code"*. `Tappable` already handles the
collision between selection and tap targets (`SelectionContainer.disabled`,
`selectableChild`) — see its doc comment at `ui/tappable.dart:48`.

There is also no copy button on a statement anywhere. `_SmallIconButton` with
`Icons.copy` already exists in this file (l. 1863) — it is used for DSNs and
nothing else.

### 1.3 The panel has two master/details, built two different ways

- **Requests** (l. 166–186): proper split — a 380px `_RequestList`, a
  `VerticalDivider`, an `Expanded` `_RequestDetail`. You keep your place.
- **SQL** (l. 148–154): the pane is *replaced*. `_SqlView` → `_QueryDetail`,
  with an `IconButton(Icons.close)` in the corner as the only way back
  (l. 645). The list you came from is gone; going back re-reads it from the top.

Both are the same panel and the same address grammar
(`<server>/req/<id>` vs `<server>/sql/<key>`). Only one of them behaves like a
master/detail.

Two more things the split itself gets wrong:

- The 380px is a `SizedBox`, not draggable. `InspectSplitGrip`
  (`inspect/inspect_dock.dart:267`) exists precisely for this and is used by
  three other panes.
- The list **drops the timestamp** when it narrows (`showTime: false`,
  l. 158), so the moment you select a request you lose the one column that lets
  you line it up against a log.

### 1.4 Requests: the row does not say what happened

- **The status code is not in the list at all** — only a dot. And `_failed`
  (l. 1996) is `error != null || status >= 500`, so **a 404 draws green**.
- Method and path share one string (`'${p['method']} ${p['path']}'`, l. 861),
  so paths do not align down the column. The file already knows this is wrong —
  `_ChannelChip` is given a fixed width with the comment *"a column whose left
  edge moves per row is one the eye cannot run down"* (l. 1922).
- No filter of any kind. The `/health` poll from the dev stack lands in the list
  every 30s and there is no way to mute it.
- The detail header `GET /users → 200` (l. 963) is not selectable, and the URL
  is only reachable as a whole curl command.
- Header lists (l. 1400) have no copy-all and no find.

`app/lib/src/run/network_tab.dart` is a deliberate sibling of this list — its
doc comment says so — and shares every one of these gaps. It has also drifted
off the design tokens: it reads `theme.textTheme.bodySmall` where the server
panel reads `context.type`.

### 1.5 Logs are inert

Two log surfaces, both thin:

- **Per-request Logs tab** (`_RequestLogsTab`, l. 1428): a `SelectableText` of
  `_summary(log)` per line — `"INFO: listed 3 users"`. No time, no logger name,
  no colour by level, no filter, no copy-all, and the `error` field of the
  payload is never shown at all.
- **Events tab** (`_EventRow`, l. 1857): plain `Text`. Not selectable, not
  tappable — an `http` row does not open its request, a `sql` row does not open
  its shape, though both destinations exist and both are one `AddressScope.write`
  away. No channel filter, no text filter.

And the level is thrown away: `_ChannelChip` colours by *channel*, and `_failed`
only looks at `error`/`status`. Measured live, a `SEVERE: about to fail on
purpose` row renders in exactly the grey an `INFO` row does.

The pattern to follow is in the house already: the run cockpit's Logs tab
(`run_plugin.dart:1042`) has filter pills, a live line count, a reversed list
pinned to the newest line, and per-line colour by severity.

### 1.6 Info spends a tab on fourteen lines

Measured on the example server, the whole Info pane is 3 links, 1 connection,
2 feature flags and 2 config values. It is identity — it does not change while
you work — and it costs a quarter of the tab strip. Worse, it is *context for
every other tab*: to check which database you are pointed at you have to leave
Requests and come back.

### 1.7 The tab strip has no hover — and it is the shared one

`InspectTabStrip` builds

```dart
Material(type: MaterialType.transparency,
  child: Container(color: context.colors.panel,   // opaque
    child: Row(children: [ … _Tab → InkWell(hoverColor: …) … ])))
```

`Material` paints its ink features **below** its child, so every hover wash and
splash those `InkWell`s produce is drawn onto the Material's canvas and then
covered by the opaque `panel` container sitting on top of it.

Confirmed live in one frame: hovering the `Events` tab produced no visual change
at all, while a `Tappable` row in the same pane, hovered by the same verb
moments earlier, tinted normally.

`Tappable` is the house primitive and says so — *"the house alternative to
`InkWell`"* (`ui/tappable.dart:29`) — and paints its own wash inside its own
subtree, where no ancestor container can cover it. The strip predates it.

One fix, three panels: the strip is also the run cockpit's and the lints
panel's.

## 2. What was built

All of it, in one pass. Five steps, all landed.

### Step 1 — the shared bits

1. **`InspectTabStrip` hover.** `_Tab` and `InspectStripButton` are
   [Tappable]s. Fixes the server panel, the run cockpit and the lints panel in
   one edit. `app/tool/catalog/demos/tab_strip.dart` is the new entry that
   makes the hover something `previews screenshot` can photograph rather than
   something we take on trust — a hover state is a colour, not a widget, so
   nothing else in the harness can see it.
2. **`app/lib/src/ui/code_block.dart`** — `FwCodeBlock` (recessed surface,
   `language:` through `codeSpans`, horizontal scroll, `SelectableText`) plus
   `CopyIconButton`, which answers with a tick because a clipboard write is
   otherwise invisible. Replaces `_Slab` and its three hand-drawn siblings.
3. **`app/lib/src/ui/filter_bar.dart`** — `FwFilterBar` / `FwPill` /
   `FwSearchBox`, promoted out of the run cockpit's Logs tab, which drew the
   shape first. Now used by four lists.
4. **`app/lib/src/ui/split_pane.dart`** — `FwSplitPane`: list, grip, detail.
5. **`app/lib/src/ui/http_row.dart`** — `HttpMethodToken` and `HttpStatusCode`,
   shared by the two request lists that are meant to read as siblings. Saying
   so in a doc comment was not keeping them in step.

### Step 2 — SQL reads as SQL

Every statement goes through `codeSpans(…, language: 'sql')` — the shape list,
the detail, the occurrences, the request's SQL tab, the N+1 banner, the Events
stream. One `SelectionArea` per pane with `selectableChild: true` on the rows
that are also tap targets. A copy button on the shape and on every occurrence.

### Step 3 — SQL master/detail: **A2**

`FwSplitPane` under both tabs, keyed apart so each keeps its own width. The SQL
list narrows to `count · shape · total`, highlights the selected shape, and the
✕ is a deselect rather than the only way back.

### Step 4 — Info: **B1**

A `Details` popover on the header, from every pane. `ServerViewKind.info`,
`ServerPlace.info` and `infoSegments` are gone; a pasted `…/info` reads back as
the server, which is where the popover now lives, and the address test says so.
The card is focusable so Escape closes it — nothing in a list of text and icon
buttons takes focus on its own, so opening moved focus nowhere and the key went
to the root scope.

### Step 5 — Requests, Logs, Events

6. Request rows: `HttpMethodToken` in its own column, the **status code shown**,
   `_failed` widened to `>= 400`, and a two-line form for the split's column so
   narrowing no longer *drops* the timestamp.
7. `FwFilterBar` over Requests (All / Errors / N+1 + path), the per-request Logs
   tab (All / Warnings+ / Errors + text), Events (All / HTTP / SQL / Logs +
   text) and the run cockpit's Network tab (All / Errors + URL).
8. One `_LogRow` for both log surfaces: time, level, message, logger, and the
   payload's `error` — which neither surface had ever shown. `_LogBand` folds
   `package:logging`'s names to three, and `_ChannelChip` colours a `log` row by
   its level, so a `SEVERE` is no longer the grey an `INFO` is.
9. Events rows are doors: `http` opens its request, `sql` opens its shape.
10. `network_tab.dart` moved onto the design tokens and the shared row, and
    `requestUrl` was split out of `curlCommand` so the request header can offer
    the URL on its own.

## 3. Decision A — how the SQL detail should open — **A2 chosen**

**A1 · Match Requests.** Split the SQL tab exactly like the Requests tab: the
shape list narrows to a left column, the detail fills the rest, the ✕ becomes a
deselect. One panel, one idiom, address unchanged.
*Against:* at 380px the shape column loses most of the statement, and
count/total/avg/max do not fit beside it.

**A2 · Match Requests, with a grip.** A1 plus `InspectSplitGrip`, and the
narrowed list keeps `count · shape · total` (avg and max are detail-only
numbers). The two master/details in the panel share one private `_Split` so they
cannot drift apart again.
*Against:* one more piece of state to hold (the split position).

**A3 · Expand in place.** No navigation: tapping a shape opens its occurrences
underneath it, the way the request's own SQL tab already expands a query
(l. 1194). Full width for the statement, all four stat columns kept, no back
button to design.
*Against:* loses the deep-linkable `/sql/<key>` address, and a nine-occurrence
list shoves the rest of the table off screen.

**Recommended: A2.** It removes the inconsistency rather than adding a third
idiom, keeps the address, and the grip is the honest answer to "380 is too
narrow for a statement".

## 4. Decision B — where Info should live — **B1 chosen**

**B1 · A popover on the header.** Info leaves the tab strip; a trigger beside
the state pill opens a `Popover` (`ui/popover.dart` — anchored, escape- and
outside-tap-dismissible, already in the house) carrying links, connections and
config, max-height ~420 with its own scroll. Reveal and copy behave exactly as
today. Available from *every* tab, which is what it is for. Strip becomes
Requests | SQL | Events.
*Against:* a real app's config may run long; nested JSON in a bounded popover is
tighter than in a pane.

**B2 · A hover card on the environment chip.** `HoverCard` instead of
`Popover` — cheapest of all, no click needed.
*Against:* reveal-a-secret is a deliberate click and does not belong behind a
hover; and a card that closes when you reach for it is the classic bug this
would walk into.

**B3 · Split it.** Links, connections and environment → header popover (short,
per-tab context). Config groups stay a pane, reached by a "see all config" link
in the popover, keeping the `/info` address but off the tab strip.
*Against:* one route with no tab to reach it is a place people stop finding.

**Recommended: B1**, with B3 held in reserve if a real server's config turns out
to overflow the card in practice. The `_NoInfoHint` teaching snippet is short
enough to live in the card unchanged.

## 5. Filling the panel

Working on this panel means needing one of everything it draws, and curling by
hand gets you a list of eleven `GET /health`s. `examples/example/bin/example_server.dart`
drives itself now:

```sh
cd examples/example && fvm dart run bin/example_server.dart --seed
```

`GET /demo/seed` fires the same run again, and it is published as a
`ServerLink` — so it is one click from the panel's own Details popover.

What `_seed` covers, and why each one is there:

| aspect | what produces it |
|---|---|
| every method colour | GET / HEAD / POST / PUT / PATCH / DELETE on `/users` |
| every status band | `/bad-request` 400 … `/maintenance` 503, `/moved` 302, 201, 204 |
| the N+1 badge and warning | `/users`, four times |
| a slow request | `/slow`, 300ms |
| every log level, coloured | FINEST…SHOUT in one burst, before the request noise |
| a log carrying an exception | `/error`, and `_audit.severe` with a `FileSystemException` |
| more than one logger | `example_server`, `.audit`, `.cache` |
| a redacted header | the seeder sends `authorization` |
| a request body that folds | `POST /users`, with an explicit `contentLength` — without it the client chunks, shelf reports no length, and the capture cut declines |
| a response body that folds | `/report`, five keys deep |
| a captured non-JSON body | `/report.xml` |
| "not captured", both reasons | `/avatar.png` (binary), `/huge` (over the 32k cap) |
| nine query shapes | select / insert / update / delete / a grouped aggregate |
| a query with params | `/slow` and the aggregate |
| an unknown channel | `/cache` emits on `cache`, which the GUI has a fallback for and nothing was reaching |
| structured config | `Limits`, which the Details popover folds into a `JsonView` |
| two connection kinds | `toy` (masked) and `redis` (nothing to mask) |

`--seed` is opt-in: this file is also the copy-paste adapter demo, and a demo
that fires forty requests at itself on boot buries the one you sent by hand.

## 6. What is deliberately not in this pass

- The SQL tab still has no badge. It costs a normalisation pass over every event
  to compute, which l. 335 declines to pay per frame, and that reasoning still
  holds.
- No new data. Everything above is a rearrangement of what `ServerCore` already
  reports; nothing here asks the inspector protocol for a new field.
