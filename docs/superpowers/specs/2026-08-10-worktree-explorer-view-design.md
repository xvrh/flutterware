# The worktree explorer — design

**Date:** 2026-08-10
**Status:** Designed, unbuilt. Decisions below are settled unless listed under
"Open questions". Measurements are from this machine on 2026-08-10 (14
worktrees) and are reproducible.
**Parent:** `2026-05-18-worktree-explorer-plugins-design.md` (the plugin model
this consumes), `2026-07-25-overhaul-master-plan.md` (answers open question 4).
**Requires:** `2026-08-10-address-spaces-brief.md` — `fw:///worktrees` must
exist before this can land.

## What this is

One screen listing every worktree git reports, with enough per-worktree fact to
answer two questions without opening anything: **which one was I in**, and
**which one needs me**. It is a cockpit, not a launcher — the expectation is that
it stays open on a second monitor while several agents run.

Four first-party facts: freshness, files changed, PR state, agent state. User
plugins contribute more later; the seam for that is §"Evolution".

## 1. The central decision: facts are not sessions

Today **every fact about a worktree comes from its `WorktreeSession`**, and a
session only exists when the worktree is *open* — it costs a config subprocess.
`shell_view.dart` is the tell: the switcher renders `status.message` for open
worktrees and the literal string `'Open'` for the rest.

A screen that lists *all* worktrees inverts that. Every row needs data, most rows
are closed, and opening 14 config subprocesses to draw a list is not something we
can do.

**So the explorer reads a new, shell-owned "facts" layer that never runs project
code.** Git, agent and forge probes are flutterware's own; they behave identically
for open and closed worktrees. Plugin-contributed cells layer on top, and in v1
only for open worktrees.

This answers master-plan **open question 4** ("are unopened badges computed
eagerly, lazily, or not at all?") with a third option it did not consider:
*shell-owned facts, always; plugin-owned status, only when open.* It also means
the explorer ships without waiting on the declarative plugin tier, which is
deferred to v2 by the master plan.

Corollary worth stating because it is load-bearing: **a worktree whose config
fails to load still has complete facts.** The two layers do not share a failure
mode.

## 2. Where it lives

### Address

```
fw:///worktrees                              the explorer
fw:///worktrees/<name>                       a worktree's home
fw:///worktrees/<name>/<plugin>/<segments…>  a plugin panel
```

The explorer is "the worktrees space with nothing selected". See the address
brief for why the space segment exists and why the noun is plural for both.

### Chrome — a pinned pseudo-tab

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  ◐ ◑ ◒   ‹│ ⛬³ │ ● explorer brainstorm ✕ │ ci green merge ✕ │ ⌄ │   ⌕  ⚙  🔥 │
└──────────────────────────────────────────────────────────────────────────────┘
            ↑ pinned, no close, badge = "needs you"
```

**The deciding argument is the badge.** The explorer's job is ambient — *N
worktrees need you*. That number wants a permanent pixel. A pinned tab carries it
natively; a right-cluster icon carries it awkwardly; a switcher menu item cannot
carry it at all. Everything else about the choice is taste.

The reframe that makes it honest: the band stops meaning "a tab per open
worktree" and starts meaning **"a strip of open places, one of which is always
open"** — which is what a pinned tab means in every browser. The oddities then
follow from the model rather than needing excuses:

- no close button — that is what pinned *means*
- always leftmost, before the first worktree — spatially, the origin
- selected state identical to a worktree tab, so the tab model stays uniform

**Not a house icon.** `Icons.home_outlined` is already the sidebar's "Overview"
row — *this worktree's home*. A house on the pinned tab would make one glyph mean
two scopes in one window. Use `Icons.account_tree_outlined`: a branch/tree glyph,
unused elsewhere, and it says "the worktrees" rather than "the start page".

**Badge = "needs you"** — count of worktrees where the agent is *waiting on you*,
or PR checks are failing, or a review is requested from you. Not a count of
worktrees, not a count of agents: a count of things that will not progress until
you act.

**Sidebar while the explorer is selected:** hidden, and its toggle disabled — not
an empty rail. Derive as `sidebarVisible && !isExplorer` so the window preference
is not clobbered and returns intact on the next worktree.

**Reachable from:** the pinned tab, a row at the bottom of the existing switcher
popover (*All worktrees…*), and `⌘⇧E`. It does **not** replace the switcher; the
switcher remains the fast path for "I know which one I want".

## 3. Data model

Three layers, separate because they have different lifetimes and costs:

```
Worktree            identity — path, gitName, branch, head, isMain   (exists)
  └ WorktreeFacts   observations — one Fact<T> per provider          (new)
      └ chips       plugin contributions                             (v2)
```

`Fact<T>` is the unit and carries its own provenance:

```dart
class Fact<T> {
  final T? value;
  final DateTime? computedAt;
  final String? validityKey;   // §5
  final FactState state;
  final String? failure;
}

enum FactState { unknown, stale, fresh, failed, unavailable }
```

**`unavailable` is deliberately distinct from `failed`.** No `gh` installed, or a
worktree with no remote, is a permanent "there is nothing to show here" — it
renders as a quiet dash and is never retried on a schedule. `failed` is a
transient error that retries on the next refresh. Collapsing the two produces a
red cell that never goes away and that the user cannot act on.

`WorktreeFacts` holds the first-party facts as **typed** fields (`git`,
`activity`, `agent`, `forge`) plus `Map<String, WorktreeChip>` for extensions.
Typed rather than all-in-the-map because the explorer's columns are a fixed
layout, and typing them is what keeps the row widget simple.

**Everything in it is plain data in the existing `lib/src/plugins/` vocabulary**
(`Status`, `StatusBadge`, `Tone`), so `fw worktrees --json` and MCP need no
second model. This is decision 2 of the master plan applied to a shell surface
rather than a plugin.

One new data type is required — the change fingerprint has no vocabulary today:

```dart
class ChangeShape {
  final List<({String bucket, int added, int removed})> buckets;
  final int files;
}
```

Data, not a widget: the GUI draws a bar, the CLI prints percentages.

## 4. The four facts

### Activity ("freshness")

Freshness is at least three clocks and they disagree: last commit, last
working-tree write, last agent message, last time *you* opened it. We do not pick
one. `activity = max(...)`, displayed as one relative time and **attributed** —
`4m · agent`, `2h · commit`. `lastOpenedAt` is shell-local state we write
ourselves (§6).

### Changes — two questions, two cells

- **Dirty vs HEAD** — "is there uncommitted work at risk here". From
  `git status --porcelain=v2 --branch`.
- **Branch vs base** — "how big is this change". From
  `git diff --numstat <base>...<head>`, plus `↑n ↓m` divergence.

### PR

`gh` and `glab`, CLI only, reusing the user's existing auth — we never hold a
token. Fields: number, title, draft/open/merged, review decision, checks rollup.
The PR title also feeds the label-priority stack (§7).

### Agent

Read from Claude Code's session files. **Verified on 2026-08-10**, not assumed:

- `~/.claude/projects/<cwd with / → ->/<sessionId>.jsonl`, one directory per
  worktree, several sessions each; newest mtime is the current one.
- The title is in `{"type":"custom-title","customTitle":"…"}` records, **appended
  repeatedly** — the last one wins.
- `{"type":"last-prompt","lastPrompt":"…"}` gives the last user prompt.
- Records carry `cwd`, `gitBranch`, `version`, `entrypoint`, so the lossy
  directory-name encoding (`-` collides with `-` in real paths) is *verifiable*
  rather than trusted.
- Files here are 500–660 KB. **Never full-parse — tail-read.** The last ~64 KB
  backwards yields the title, the last prompt and the last record type.

State machine, given file-only detection (no process inspection — decided):

| state | signal |
|---|---|
| `none` | no session directory for this cwd |
| `working` | mtime < ~60 s and last record is a user message or tool result |
| `waiting` | last record is an assistant message, mtime recent — **waiting on you** |
| `idle` | mtime older than ~30 min |

**The honest limit, recorded so nobody later reads a `working` dot as a liveness
guarantee:** file-only cannot distinguish "Claude is running" from "Claude was
killed mid-turn". A stale `working` decays to `idle` by age.

This is Claude Code's private format and it will change. It lives behind one
class with a version-tolerant parser that degrades to `unknown` and never
throws — the 2026-05-18 spec already named `ClaudeSession` as the encapsulation
of exactly this. The *interface* is `AgentProbe`; Claude is the first
implementation. That is free now and expensive to retrofit.

## 5. Refresh — no timers

Two findings make "live where it's free, manual where it isn't" cheap enough to
prefer over pure-manual:

**One watcher covers every worktree's git state.** A linked worktree's HEAD and
index are not in the checkout — they are in `<main>/.git/worktrees/<name>/`
(verified). So one recursive watch on `<main>/.git/worktrees/` sees branch
switches and commits across all linked worktrees, plus `.git/refs/heads/` and
file-watches on `.git/HEAD` and `.git/index` for the main checkout. **Four
watchers, not fourteen.** Never watch `.git/` recursively — `objects/` churns on
every fetch.

**One `gh pr list` covers every branch.** `--json number,title,headRefName,
isDraft,reviewDecision,statusCheckRollup --limit 100` returns everything joinable
on `headRefName`. The PR tier is one subprocess for the whole repo.

| trigger | refreshes | cost |
|---|---|---|
| filesystem events | branch, ahead/behind, HEAD moves, agent state | 4 git watchers + 1 on `~/.claude/projects/` |
| becoming visible | dirty counts; PR if past TTL (~5 min) | ~100 ms pooled; +0.9 s if PR stale |
| manual button | everything, unconditionally | ~1 s worst case |

**No polling timer anywhere.** The agent cell being live is the part worth
insisting on: a cockpit you sit on while six agents run is useless as a snapshot,
and watching one directory buys the "Claude is waiting on you" signal for nearly
nothing.

**One honest gap: dirty state cannot be event-driven.** Editing a file does not
touch the index, and watching 14 working trees recursively is precisely the cost
we are avoiding. Dirty refreshes on visibility and on demand. It is also the
least urgent cell — it changes when *you* type, and you know you typed.

**A clock tick that redraws "4m ago" is not a refresh.** A 30 s ticker on
relative-time labels is render-only; do not let it grow into a probe schedule.

## 6. Performance

Measured, 14 worktrees, warm:

| call | cost | scope |
|---|---|---|
| `git worktree list --porcelain` | 10 ms | once |
| `git for-each-ref refs/heads/` | 15 ms | once, **all branches** |
| `git status --porcelain=v2 --branch` | 20–30 ms | per worktree |
| `git diff --numstat base...head` | 8 ms | per worktree |
| `gh pr list --json …` | 890 ms | once, **all branches** |

Four rules:

1. **Batch what git can batch.** `for-each-ref` gives last-commit time and
   `%(upstream:track)` ahead/behind for *every* branch in one process. Only dirty
   state genuinely needs a per-worktree cwd — 14 spawns instead of 42.
2. **`--no-optional-locks` on every status.** It exists for polling tools;
   without it we write each worktree's index from a background refresh and fight
   the user's own git.
3. **Content-addressed cache, persisted.** Each fact declares a validity key from
   inputs that are already free. Refresh computes the key first and recomputes
   only when it moved. Where it actually pays — stated precisely so it is not
   oversold:

   | fact | key | effect |
   |---|---|---|
   | branch numstat | `(base_sha, head_sha)` | computed once per commit, **ever** |
   | agent | jsonl mtime + size | a `stat()` decides |
   | dirty | none cheaper than the work | just runs |
   | PR | TTL, not a key | one call for all rows |

4. **Bounded pool (~4) with per-(worktree, fact) dedup**, so a rescan storm
   cannot stampede.

**Cache location:** `~/.flutterware/<sha1(main checkout path)>/worktrees.json`,
alongside the launcher's existing per-project directory. Not inside the repo:
this is machine state, not project state, and writing it into the checkout means
gitignore churn and a dirty-count that reports our own cache. `lastOpenedAt`
lives in the same file.

**The UI rule that makes all of this invisible: stale-then-fresh, never
empty-then-full.** Rows render immediately from cache with identity and
last-known values; refreshing cells show the old value, not a spinner. A grid of
per-cell spinners is the failure mode this rule exists to prevent.

## 7. The view

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  Worktrees · 14        [ Filter…            ]      Sort: activity ⌄     ↻  12s ago    │
├──────────────────────────────────────────────────────────────────────────────────────┤
│▎●  Worktree explorer brainstorm         ▊▍▏  app·lib      ⬤ waiting for you   #76 ✕   2m│
│    claude/worktree-explorer-e5efdc      14f  +340 −87 ●3  "now design the row" 1 approve agent│
├──────────────────────────────────────────────────────────────────────────────────────┤
│▎   The UI catalog becomes Previews      ▊▊▊▍ app          ◐ working           #73 ✕   4m│
│    claude/ui-catalog-design-38b6c0      62f  +2.1k −890   "fix the analyze fail" 1 failing│
├──────────────────────────────────────────────────────────────────────────────────────┤
│ ●  ci green merge master                ▏    docs         ○ idle 3h           —      2h│
│    claude/ci-green-merge-master-df3e7d  2f   +11 −4                           no PR   commit│
├──────────────────────────────────────────────────────────────────────────────────────┤
│    master                          ~    —    in sync      —                   —      6h│
│    the main checkout                                                          commit   │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

**Two lines per row: line 1 is the answer, line 2 is the evidence.** That rule is
what keeps the density honest — every line-2 item explains the line-1 item
directly above it.

Column budget at ~1200 px: gutter 14 · name flex (min 220) · changes 220 · agent
190 · PR 150 · when 64 · actions 32.

### Cells

**Gutter — two marks, two meanings.** A 2 px `accent` left edge means *open* (a
spatial rhyme with the tab strip). The dot is the aggregate tone, worst-wins.
Conflating them would make "open" and "needs attention" the same pixel.

**Name.** Label-priority winner in `bodyStrong`, branch in `caption` below. The
tooltip shows the whole stack (`agent title → PR title → branch → directory`) so
precedence is inspectable rather than mysterious. Filter matches lit via the
existing `matchedName` from `worktree_filter.dart` — the switcher's filter is
reused wholesale, same `↵ picks the first` contract.

**Changes.** The fingerprint went through one revision worth recording. The first
proposal was colour-coded buckets; that fails because with different buckets per
row the bars are not comparable and you cannot tell `lib` from `test` without
hovering, which makes it decoration. Two fixes make it a real signal:

- **The bar carries proportion, the text carries meaning.** One segment per
  bucket with alternating *luminance* (no hue), and the two dominant buckets
  named in text beside it. No colour-assignment problem, and it degrades exactly
  to CLI: `app 78% · lib 15% · docs 7%`.
- **Shared scale across rows.** Total bar width ∝ lines touched, normalised to
  the largest row and capped. This is what makes "that branch is big, this one is
  a typo fix" readable down the column — the entire reason the bar exists.

Line 2 is `14f +340 −87` plus the dirty badge `●3` in `amber`.

**Agent.** Line 1 is the state; line 2 is the **last prompt**, truncated —
deliberately *not* the title, because the title has already been promoted into
the name cell and repeating it wastes the row's most interesting 190 px. "What is
it doing right now" is the thing available nowhere else in the app.

**PR.** `#76` + state on line 1; `1 failing check · 1 approval` on line 2.
`unavailable` renders as `—` in `mut3` with a tooltip, never as an error.

**When.** `2m` over `agent` in `micro` — the attributing source. The "max of
several clocks, attributed" decision made visible in 64 pixels.

### Sorting

**Activity descending, flat, no grouping.** Deliberately *not* OPEN / NOT OPEN
like the switcher: the worktree that needs you is most often the one that is not
open — an agent finished while you were elsewhere — and grouping open-first
buries exactly the row the screen exists to surface. Open-ness is a marker, not a
section. Modes: `activity` (default) · `needs you` · `name` · `branch`.

### Row states

| state | treatment |
|---|---|
| hover | `hoverOverlay`; primary **Open** fades into the right margin |
| open | 2 px `accent` left edge |
| current | left edge + `current` in `micro` after the branch |
| expanded | grows to ~200 px in place |
| stale cell | value at 60 % opacity, **no spinner**; one "Refreshing…" in the header is the only progress |
| failed probe | small `!` with the error in a tooltip — never a red row; a probe failing is our problem, not the worktree's |

**Expansion is in place, not navigation.** Click the row background (or `→`) and
it grows: changed files with per-file +/−, the PR's check list, the agent's last
exchange, the full path, the label stack. This follows the screen's governing
principle — **nothing on a row costs an open**, so you can decide before you
spend.

### Actions

Hover shows `Open`; `⋯` has Open in background · Reveal · Open in editor · Copy
path · Open PR · Remove worktree.

Removal of a *closed* worktree is the awkward case: plugin guards need the
worktree open. It either opens first, or runs with shell-owned guards only and
says so in the dialog. See open questions.

### Keyboard

`↑↓` move · `↵` open and go · `⌘↵` open in background (stay on the list, the row
flips to open in place — the "open three to compare" case) · `/` filter · `Esc`
back to where you were · `⌘⇧E` reach the explorer from anywhere.

### Degenerate states

This ships to repos that do not use worktrees at all.

- **One checkout** — the screen still renders and says "This repo has one
  checkout", with a `git worktree add` hint rather than an empty list.
- **Not a git repo** — say so plainly. `WorktreeDiscovery` already falls back to
  a single synthetic entry; the explorer explains it rather than showing a lonely
  row.
- **50 worktrees** — virtualised list; the filter is already load-bearing.

## 8. Renderers

Same model, three surfaces — the master plan's "no renderer is privileged"
applied here:

```
fw worktrees
● explorer brainstorm   claude/worktree-explorer-e5682  14f +340 −87 ●3  agent:waiting  #76 ✕  2m
```

plus `fw worktrees --json`, and the switcher popover rendering a condensed
one-line form of the same rows (replacing today's literal `'Open'`).

## 9. Code layout and testing

The split mirrors `PluginCore` vs `NativePlugin`, and for the same reason:
`fw` must not link `package:flutter` (`app/test/utils/entry_point_purity_test.dart`
enforces it).

```
app/lib/src/worktrees/
  facts.dart              Fact, FactState, WorktreeFacts, ChangeShape   pure Dart
  facts_controller.dart   scheduler, cache, watchers                    pure Dart
  providers/git.dart      batched for-each-ref, status, numstat         pure Dart
  providers/agent.dart    AgentProbe + ClaudeSession (tail reader)      pure Dart
  providers/forge.dart    gh / glab                                     pure Dart
  explorer_screen.dart    the view                                      Flutter
  explorer_row.dart       the row                                       Flutter
```

Change notification is a `ValueStream`, matching `PluginCore.changes`, so the
CLI can subscribe without a `ChangeNotifier`.

Testing:

- **Parsers get unit tests with recorded fixtures** — `porcelain=v2`, `numstat`,
  `for-each-ref`, `gh --json` output, and a truncated JSONL. These are the parts
  that break when a tool version changes, and they must be testable without git,
  network or `~/.claude`.
- **Providers take injectable process runners**, as `WorktreeDiscovery` and
  `pub_deps` already do.
- **The scheduler gets a fake clock and a fake filesystem**, so "does not
  stampede" and "does not recompute when the validity key is unchanged" are
  assertions rather than hopes.
- **Row widget tests over fabricated `WorktreeFacts`**, covering every state in
  the table above — especially `unavailable`, `failed` and `stale`, which are the
  ones a happy-path demo never produces.

## 10. Build order

Each slice is independently useful and independently reviewable.

1. **Facts model + git provider + `fw worktrees`.** No GUI. Proves the model,
   the batching and the cache against a real repo, and lands a CLI command that
   is useful on its own.
2. **The explorer screen**, git facts only — pinned tab, rows, filter, sort,
   open/open-in-background. This is the shape; everything after is a cell.
3. **Agent provider** + the `~/.claude/projects/` watcher + the "needs you"
   badge. The feature people will actually keep the window open for.
4. **Forge provider**, `gh`/`glab`, TTL and manual refresh.
5. **Expansion, row actions, keyboard**, degenerate states.

Slice 1 depends on the address rework only for slice 2 onwards; it can start in
parallel.

## Decisions reached

- Facts are a shell-owned layer, independent of `WorktreeSession`, that never
  runs project code — which is what makes closed worktrees reportable and answers
  master-plan open question 4.
- The explorer is `fw:///worktrees`; the address gains a space segment first.
- Chrome is a **pinned pseudo-tab**, decided on the badge argument, with
  `Icons.account_tree_outlined` rather than a house (the house is taken).
- It does **not** replace the switcher.
- Freshness is `max` of several clocks, **attributed** in the UI.
- Changes is two cells, not one: dirty vs HEAD, and branch vs base.
- The fingerprint is **luminance + named buckets + shared scale**, not hue-coded
  buckets.
- Agent detection is **file-only**; `AgentProbe` is the interface, Claude the
  first implementation.
- Forge is **CLI-only** (`gh`, `glab`), one batched call per refresh.
- **No polling timers.** Filesystem events, visibility, and a manual button.
- `FactState.unavailable` is distinct from `failed`.
- Sort is activity-descending and flat; open-ness is a marker, not a section.
- Stale-then-fresh rendering; no per-cell spinners.
- Cache is content-addressed and persisted outside the repo.

## Rejected

- **Right-cluster toggle for the explorer** — that cluster is meta (search,
  config, hot reload); a primary destination there is discoverable once and
  carries a badge badly.
- **Overlay sheet over the current worktree** — a cockpit you sit on cannot be a
  thing you dismiss to work, and an addressable overlay is a contradiction.
- **Explorer inside the 232 px sidebar** — dead on the same evidence that killed
  the horizontal plugin strip in M1.
- **`/worktree/<x>` + `/worktrees`** — two nouns one character apart meaning
  different things.
- **Hue-coded change buckets** — not comparable row to row without a hover; kept
  as a v2 idea gated on a palette that survives both themes.
- **Process inspection for agent liveness** (`ps`/`lsof`) — expensive and flaky
  for a signal a file mtime approximates well enough.
- **Cards instead of rows** — comparison across worktrees requires aligned
  columns.
- **Grouping open-first** — buries the row the screen exists to surface.
- **A polling timer** — every fact either has an event source or a cheap
  visibility check.

## Open questions

1. **Label precedence when the agent title and the PR title both claim high** —
   inherited unresolved from the 2026-05-18 spec, and this screen is the first
   surface where both are routinely present. Leaning: agent title wins while the
   agent is `working` or `waiting`, PR title otherwise.
2. **Teardown of a closed worktree.** Plugin guards need an open worktree. Open
   first, or proceed with shell-owned guards and a stated reduction? The former
   is safer and slower; the latter needs the dialog to be honest about what it
   did *not* check.
3. **The v2 hue palette** for change buckets — needs stable hue-per-directory
   assignment that survives both themes and does not collide with the tone
   colours.
4. **Second agent implementations** (Codex, Cursor, aider) — the interface exists
   from day one; whether any ships in v1 is unowned.
5. **What the explorer does when the repo has *many* worktrees with no agent and
   no PR** — i.e. a repo that uses worktrees for release branches. The row is
   then mostly empty and the screen may want a denser single-line mode.
