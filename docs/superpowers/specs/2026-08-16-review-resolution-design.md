# Review notes: a note is resolved, and the handoff stops being a transition

**Date:** 2026-08-16
**Status:** Decided with the owner in conversation, then **built** — every
decision below is in the code, and § What the build corrected records the five
places the build disagreed with this document. Threads (D6) remain unbuilt and
deliberately so; the storage that makes them additive is in.

**Lineage:** the review feature itself — `app/lib/src/changes/review_*.dart`,
whose three decisions this doc keeps two of and retires the third; and the
report that opened it, *"a review note is written for an agent and is the one
thing an agent cannot read"*, which is where the problem statement comes from.

## The report

A human left a note on a line of `tool/flutterware.dart` and asked whether the
agent could read it. It could — by knowing from a commit message that notes live
in an append-only JSONL log, guessing that *outside the repository* meant
`~/.flutterware/`, and searching for a file whose name contained `review`. The
note had by then been sitting unread for a day, and the only reason it surfaced
at all is that the human eventually asked *can you see it?*

Two distinct failures, worth separating because they have different fixes:

- **Discovery.** The log's directory is `sha1(canonicalize(worktreePath))`
  ([review_store.dart:40](../../../app/lib/src/changes/review_store.dart)). A
  caller can derive that; no caller should have to. Notes are a shell feature
  rather than a plugin, so they appear in neither `flutterware_status` nor
  `flutterware_actions` — a project that declares three plugins gets three
  plugins and no hint that a fourth kind of thing exists.
- **State.** Even found and read, there is nothing to read *back*. The agent
  cannot say *done*, cannot say *I disagree, and here is why*, and cannot tell a
  note it has already acted on from one it has not.

## What changed since the feature was designed

The original rule was:

> Handing off is what closes a batch, and it is the only thing that does.

That was right, and the reason it was right is worth stating precisely, because
it is the reason it is now wrong. **Two different facts were being collapsed:**

- **Delivery** — has the recipient got this? Naturally batch-shaped; you hand
  over a set.
- **Disposition** — has the thing this note asks for been done? Naturally
  per-comment; each note asks for one thing.

With a human colleague as recipient, disposition is *unobservable*. The tool
cannot know whether they fixed it. So the only honest fact available was *it
left*, batching that was correct, and per-comment resolution would have been a
row of checkboxes nobody could fill in truthfully.

The recipient has changed. An agent running in the repository knows when it is
done with note 3 and can say so. Disposition became observable, so it becomes
the state worth keeping — and delivery, the thing the batch modelled, turns out
not to be a question anybody was asking.

## The model

**D1. One bit per note: resolved.** Either party sets it. The GUI filters
resolved notes out by default; turning the filter off is what History used to
be.

**D2. The handoff is a read, not a transition.** The dialog becomes *here are
the unresolved notes* — copy them, save them, point somebody at them. It changes
no state. Nothing is "closed" by exporting, because exporting never knew
anything about whether the work got done.

**D3. A resolution carries an actor and an optional message.** *Resolved by the
agent* and *resolved by you* are different facts, and when you scan a list you
want to know which ones you are taking on faith. The message is where *I did it*
and *I disagree, the test at `foo_test.dart:88` covers this* differ.

**D4. A resolution you have not seen does not filter.** This is the hole in the
naïve version and the one decision that has to be in the first build. If the
agent may resolve, and resolved is hidden, then an agent that disagrees with a
note closes it silently — and the filtered list looks identical to the case
where it did the work. The pushback disappears exactly where it mattered.

The mechanism is a per-worktree `seen` marker rather than per-note state: an
agent resolution newer than the marker is drawn regardless of the filter, and
the Review tab carries a count of them. Opening the tab advances the marker.
Per-note acknowledgement was considered and rejected — it is one click per note
forever, which is the manual ticking this whole design is trying not to
introduce.

**D5. No status enum.** Not `done` / `declined` / `wontfix`. The message carries
the nuance, and a taxonomy is a field nobody fills in honestly. If a shape
emerges from a year of real messages, it can be added over data instead of over
a guess.

**D6. Threads come later, and the storage is decided now.** The agent answering
in the tool and you replying to that answer is wanted (*a nice little tool*, not
a competitor to chat). It is not in this build. What is in this build is the
event shape that makes it additive: a reply is the resolution event **without
the resolved bit**. Deciding this now costs nothing and means the logs written
in between are readable by both versions.

The earlier refusal of threads — *the reply is the agent's next commit* —
assumed the agent's reply lands somewhere the human will see it. The report
above is the proof it does not: a reply in chat scrollback is a reply that gets
lost, which is the same failure as the note nobody could read, pointing the
other way.

**D7. The drift badge goes quiet on a resolved note.** *This file has changed
since the comment was written* is a warning today. On a note the agent resolved,
the file changing **is the point** — every resolved note would wear the badge,
and a badge that is always on is not a badge.

## Storage

Three new events, all tolerated by the existing decoder, which returns null for
a line it does not understand and keeps the rest of the log
([review_comment.dart:348](../../../app/lib/src/changes/review_comment.dart)).

```jsonc
{"event":"resolve",  "id":"<comment>","by":"agent|human","at":"…","message":"…"}
{"event":"unresolve","id":"<comment>","by":"agent|human","at":"…"}
{"event":"seen",     "by":"human","at":"…"}          // advances the marker
// later, and deliberately the same shape minus the bit:
{"event":"reply",    "id":"<comment>","by":"agent|human","at":"…","message":"…"}
```

`unresolve` is not symmetry for its own sake: it is how you recover a note an
agent closed wrongly, and how the agent itself backs out of a resolution it
wrote before its session was interrupted.

The `seen` event lives in the log rather than in a preference file because the
log is already the per-worktree store and a second store is a second truth. It
is written **at most once per visit to the Review tab**, never per frame — a
write on draw is a smell, and an unbounded one would be a bug.

`ReviewState` loses `history` and gains the resolution on the comment itself;
`ReviewComment` gains `withResolution` beside `withBody`. Resolved notes read
newest-resolved-first when the filter is off.

## What gets cleaned up

The handoff was load-bearing, and half of what it holds up is prose. **Prose
that asserts a retired rule is worse than dead code**, because the next reader
believes it.

### Deleted outright

| Thing | Where |
| --- | --- |
| `ReviewBatch` and its class doc (the *no Clear button* argument) | `review_comment.dart:218` |
| `BatchHandedOff` **write** path, and `route` / `savedTo` with it | `review_comment.dart:414` |
| `ReviewState.history`, and the `BatchHandedOff` arm of `fold` | `review_comment.dart:441` |
| `ReviewController.handOff` and its explicit-ids rationale | `review_store.dart:131` |
| `ReviewBatchRow` | `review_view.dart:714` |
| The *Handed off* section of the Review tab, `onCopyBatch`, `_copyBatch` | `changes_screen.dart:1216` |
| `_handOff` and the state mutation after the sheet returns | `changes_screen.dart:620` |

The route distinction (`copy` vs `file`) was recorded because *I copied it* and
*I wrote it to disk* have different next steps when the agent says it saw
nothing. That consumer is gone: the agent now reads the log directly, and
whether a markdown blob also went to a file is no longer part of any story about
why a note was not acted on.

Copying a past batch again survives in better form — resolved notes are still in
the log, the filter shows them, and export runs over whatever is selected.

### Demoted, not deleted

`showHandoffSheet` stays, as **Export**. It keeps the two routes, the preview,
and the in-place failure message — *what leaves, shown before it leaves* is
still true, and the paste-into-some-other-agent path is still real. It loses:

- the title *Hand off N comments* → *Export N unresolved*;
- the footer promise *Moves these to history. You can copy a past batch again.*
  — it now moves nothing;
- the `HandoffResult` plumbing that mutated the store, reduced to *did it
  succeed*, which is all the optional follow-up below needs.

The footer button (`changes_screen.dart:1494`) loses its status as the screen's
closing gesture and becomes a quiet *Export*. The tab count changes meaning:
*what is waiting to be handed off* becomes *unresolved*.

**One optional affordance, and only this one:** after a successful export, the
dialog may offer *resolve these too*. It is the honest answer to the one real
regression in this design — the copy-paste path never self-empties, because
nobody reports back — and it is not the *Clear* button the original refused,
because it is tied to the export gesture rather than standing on the screen as a
way to empty a list.

### Doc comments that must be rewritten, not left

`review_handoff.dart:8` (*handing off is what closes a batch*),
`review_comment.dart:218` (*there is no Clear button, and this is why*),
`review_comment.dart:253` (*the handoff, as markdown* — it is the export now),
`review_store.dart:125` (*closes the open batch*). Each states a rule this
design retires; each is the kind of comment this repository is read for.

### Tests

Deleted or rewritten, by name:

- `review_log_test.dart` — *handing off closes the batch and opens the next
  one*, *newest batch first, because that is the one you just sent*, *a batch
  whose comments were all deleted is not a row*.
- `review_screen_test.dart` — *handing off closes the batch and history
  remembers it*, *cancelling the sheet leaves the batch open*, *a deleted
  comment does not travel with the batch*; *the tab count is what is waiting to
  be handed off* survives with a new name and the same assertion.

New, and these are the ones that carry the design:

- A resolve hides the note; the filter shows it again.
- An agent resolution the human has not seen is **not** hidden, and the tab
  counts it; opening the tab advances the marker and it filters thereafter.
- `unresolve` returns a note to the list.
- **The legacy fold** (below), against a log fixture written by the shipped
  version.
- Two writers: a resolve appended by another process is folded in on the next
  read, unchanged from the existing two-writer test's shape.

## Migration

**A log written by the shipped version already contains `handoff` events.** If
the new fold ignores them, every note ever handed off comes back as unresolved
on first launch — for the author of this design, that is every note ever
written.

So `BatchHandedOff` stays **decodable and unwritten**: the fold treats a legacy
handoff as resolving its ids, actor `human`, at the batch's timestamp, with no
message. `route` and `savedTo` are dropped on the floor. This has to ship in the
same build as the new fold, not after it.

## The agent surface

**`flutterware_status` carries the count and the resolved path** —
`review: {unresolved: N, log: "<path>"}`, beside `root` and `worktree`
([mcp_server.dart:142](../../../app/lib/src/session/mcp_server.dart), and the
same shape in `fw status --json` at
[cli.dart:955](../../../app/lib/src/session/cli.dart)). This is the half that
fixes discovery, and it fixes it on the call the server's own instructions tell
a client to start with. It is worth shipping on its own, before anything else
here.

**A fifth MCP tool, `flutterware_review`** — `list` (unresolved by default),
`resolve(id, message)`, `unresolve(id)`, and `reply(id, message)` when threads
land. A tool rather than a plugin action, because `Session` resolves cores from
the declared manifest and there is no always-on shell core concept to hang this
on; inventing one for a single feature is a larger change than the feature
justifies. The cost is named honestly: the server's small-fixed-tool-set policy
gets a fifth member, `docs/capabilities.md` is generated from
`FlutterwareMcpServer.tools` and regenerates, and **`fw review` has to be
written and tested by hand** — the parity test walks declared plugin actions, so
it will not catch a shell tool that only one surface has.

`list` returns the same markdown `reviewMarkdown` already produces, so there
stays one format to keep readable and one to test.

**The GUI must watch `review.jsonl`.** `ReviewController.reload()` exists and
has no caller anywhere. That was survivable when state changed once per handoff,
by the window doing the changing. It is not survivable when an agent writes
resolutions and replies while your window is open: without the watch, the screen
is simply wrong for most of the session, and the receipt this whole design is
built to give you is the thing you cannot see. A single-file watch, not a
recursive one.

## What is out, and why

- **A status taxonomy** — D5.
- **A standing *resolve all*** — the original argument holds: it makes *I dealt
  with these* and *I gave up on these* one gesture. The export follow-up is
  bounded to the moment you exported.
- **Agent-proposes / human-approves** — a second workflow to model, when the
  unseen marker gets the same protection for one bit.
- **Threads, now** — D6 buys the option without paying for it.
- **Per-note assignment, severity, due dates.** A review tool for one human and
  one agent in one worktree does not have a routing problem.

## Costs, risks, open questions

- **The copy-paste path never self-empties.** Named above; mitigated by the
  export follow-up; accepted.
- **An agent can resolve everything.** The deterrent is the message and the
  actor, not a permission — the same trust already extended to a process that
  edits the source. The unseen marker bounds the damage to *you have to look*.
- **A write on view.** The `seen` event has to be genuinely once-per-visit. Worth
  a test that pumps the tab and counts appended lines.
- **`ReviewThread` is already taken** — it is the widget that draws a comment in
  the diff (`review_view.dart:54`). Whatever threads get called, it is not that,
  or that gets renamed first.
- **No commit sha on a resolution.** It was considered — a sha beside *done*
  makes the receipt checkable rather than merely readable — and refused: the
  message is what a human reads, and a field that only a machine can check is a
  field that goes stale the first time work lands across two commits.

## What the build corrected

**The controller had to leave the store.** `ReviewStore` is now read by `fw` and
by the MCP server, both compiled without Flutter and guarded by a purity test on
the CLI entry point — so one `package:flutter/foundation.dart` import for a
`ChangeNotifier` would have made the log unreachable from the two surfaces this
whole design exists to serve. `ReviewController` moved to its own file.

**Arriving at the tab re-reads before it marks.** The watch was supposed to be
how an agent's answer reaches an open window, and the test that proved the
design — the agent resolving a note while the screen is up — failed on it: a
filesystem event is not something a widget test can wait for, and a watch can be
refused in production for the same reason it is absent there. Arriving is the
moment the answer matters, so it is the moment not to depend on the watch.

**The watch may not create the directory it watches.** The first version called
`createSync` so there was something to watch — which would leave a permanent
empty directory under `~/.flutterware` for every checkout anybody ever opened
the screen on, for a review nobody wrote. It watches only what exists, and the
first note arms it.

**The unseen set is held by the screen, not read from the log.** Marking on
arrival and reading `unseenResolutions` in the same build clears the accent in
the frame that draws it — the rows arrive already dimmed, which is precisely the
silence D4 exists to prevent. The screen captures the ids on arrival, and the
live list is that set plus whatever has landed since.

**The usage column of the capability document never escaped pipes.** Found
because `review`'s usage has alternatives in it — and `capture` turns out to
have been rendering as three columns since it grew a `--theme=light|dark`. The
rule already existed for parameter descriptions; it was one column short.

## Order

Planned as five steps and **built as one**, because the seams turned out to be
false: the fold cannot ship without its migration (a data-loss bug), the filter
cannot ship without the unseen marker (D4's hole), and the export demotion
cannot lag behind the resolution model without two ways to close a note existing
at once — which is the ambiguity this design is removing.

Steps 1 through 5 are in. **Threads (D6) are not**, and are not wanted yet; what
is in is the event shape that makes them additive — a reply is the resolution
event without the resolved bit.

## Verification

- **2,680 tests green**, workspace analysis clean. 30 of them are this feature's:
  the fold, the unseen marker, the legacy migration, resolving and reopening
  through the real screen, and the agent surface against a log resolved from a
  real worktree path — which is the thing that actually failed in the report, so
  a test that hand-built the store would have proved the wrong half.
- **The loop, end to end through `fw`**, against this checkout's own log: two
  notes written into it, `fw review` reading them back with their ids and their
  quoted code, `fw review resolve <id> --message=…` answering one, and
  `fw status` then reporting *1 review note outstanding*.
- **The GUI's own tests cover the screen**, including the case the whole design
  turns on: an agent resolution written into the log while the window is open is
  drawn anyway, with the agent's message, and reading it is what quiets it.
