# Branch delta — what this branch changed, painted on the trees

The previews tree and the scenarios tree now say which of their rows this
branch touched, against the branch it will merge into. Three states, in the
order the tree ranks them: **added** (green), **edited** (amber), **reached**
(a grey dot — the row reads a file that changed). A folded branch carries a
dot for the strongest state under it. The filter row gains a toggle that
narrows the tree to what changed, and its tooltip names the base the colours
are measured against. `previews entries` and `scenarios list` carry the same
states, so an agent can run only what the branch touched.

## What it is built from

Nothing here is new machinery; it is two existing answers joined.

- **The delta is the changes screen's probe** (`changes/changes_probe.dart`):
  the inferred or configured base, the merge-base, the patch with renames
  detected, the untracked files. "No base" is a state — nothing is diffed
  against a guess, so on a checkout with no base nothing is tinted.
- **The reach is the comparison's import graph**
  (`comparison/import_graph.dart`): each entry file's closure, read from
  source rather than compiled, intersected with the delta's paths. No second
  checkout, no build, no guest.
- **The lines come off the hunk bodies**, not the hunk ranges. A hunk carries
  three lines of context at each end, and a declaration tinted for being
  *near* an edit is the false positive that would make the colour worthless.
  `BranchDeltaProbe` walks each hunk for the runs of `+` lines and the
  positions of `-` lines.

Both scanners now record where a declaration **ends** as well as where it
starts — `CatalogEntry.line`/`endLine`, `ScenarioRef.endLine` — because the
design-system demo file holds twenty entries and a file-level answer would
tint all twenty for one edit. A preview's span starts at its first
annotation, not at the doc comment above it: a rewritten sentence is not an
edit to the entry. A scenario is keyed by file, name *and* line, because a
name declared twice in one file is two rows.

## The classifier (`delta/branch_delta.dart`)

Pure, and tested without git. In priority order:

1. **added** — the file is untracked (or under a directory git reports as
   wholly untracked), or was added on the branch, or every line of the
   declaration is in an inserted run.
2. **edited** — an added run overlaps the declaration, or a removal sits
   strictly inside it. A rewritten line is a removal at `x − 1` plus an
   addition at `x`; a removal at a span's *edge* is charged to nobody, because
   by line numbers alone it is the neighbour's as often as the span's, and the
   neighbour is the common case. The same rule keeps a rewritten declaration
   from reading as wholly new.
3. **reached** — nothing in the declaration moved, but its closure holds a
   changed file. Generated files (`.g.dart`, `.freezed.dart`) are edits to
   their own entries and never reach.

**Reach is withheld past a quarter of the tree.** Measured on this studio's
151 entry files: 122 of the 1,097 files any entry reaches are in the closure
of at least half the entries, and the top hub reaches 107 of 151. Touch one
and the whole list goes grey, which is a colour on none. Under the threshold
the dots are precise (457 files are read by exactly one entry); over it the
rows keep their added and edited marks and the toggle's tooltip says *N of M
read a shared file that changed — not marked*.

## The organ (`delta/branch_delta_controller.dart`)

One `BranchDeltaController` per worktree, owned by the `Session` and installed
on the previews and scenarios cores the way the compare runner is: the cores
cannot see each other, and neither should own what both read.

- **Never blocks a list.** The tree draws untinted and the tint arrives when
  the load lands — `Isolate.run`, since the graph is ~800 ms of parsing cold.
  The last answer survives a failed reload.
- **Each core registers the files its scan found** (`track`), and one load
  answers for the union. Every landed scan looks again, whether or not the
  set moved: a scan lands because a file was saved, and an edit inside an
  existing entry moves no set at all. An arriving panel with nothing
  registered yet does not read: the load the scan starts on landing is the
  first one worth paying for.
- **An unchanged git half skips the graph.** The probe is handed the previous
  answer; when base, files, lines and untracked all match and the same files
  are asked about, the previous reach is carried over and no file is parsed.
  The controller then keeps the previous *object* too, so everything memoised
  on its identity stays warm and nothing is notified. That is what makes the
  20-second tick affordable on an idle checkout: a few git processes, no
  parsing.
- **Refresh, cheapest first:** the shell forwards `gitMoved` (a commit or a
  branch switch moves the merge-base) to every session with a tree on screen;
  a panel arriving or the window regaining focus asks again if the answer is
  older than ten seconds; and while a panel is on screen the tick is the
  backstop. No recursive working-tree watch — that is the changes screen's
  scoped exception.
- **A mid-load refresh is remembered, not joined**, copied from the changes
  controller: the save that fired it landed after the running load read the
  disk. The agent path waits for the chain to *settle* (`whenSettled`): a
  load already running when a scan landed was asked before that scan's files,
  so the answer it wants is the queued one's.

## Cost

Measured on this repository, cold, for the studio's 151 entry files:

| step | cost |
|---|---|
| git: merge-base, diff, status | 73 ms |
| import graph, first closure | 132 ms |
| import graph, all closures | 832 ms |

Warm, a closure is ~1 ms since files are parsed once per graph. The graph is
rebuilt per load; mtime invalidation is the optimisation to reach for if a
real suite makes the tick noticeable.

## Not done, on purpose

- **The uncommitted delta as a separate colour.** The branch since merge-base
  is the question asked; "what I changed since lunch" is a different one and
  one more state, not a redesign.
- **Removed entries.** Gone from the tree, so they cannot be tinted. The
  comparison reports them.
- **A pixel answer.** The tint is the guess; the comparison is the check.
