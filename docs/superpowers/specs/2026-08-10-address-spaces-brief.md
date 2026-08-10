# An address names a space first — session brief

**Date:** 2026-08-10
**Status:** Brief. Decided, unbuilt. Written to be picked up in its own session
on its own worktree, and landed **before** the worktree explorer.
**Parent:** `2026-07-29-address-router-merge.md` §3 (which this amends),
`2026-05-18-worktree-explorer-plugins-design.md`.
**Blocks:** the worktree-explorer view (design doc to follow, 2026-08-10).

## The change

```
now     fw://<project>/<worktree>/<plugin>/<segments…>?<axes>
after   fw://<project>/<space>/<space's own path…>?<axes>
```

with exactly one space defined:

```
fw:///worktrees                              the collection — the explorer
fw:///worktrees/<name>                       one worktree's home
fw:///worktrees/<name>/<plugin>/<segments…>  a plugin panel
fw:///worktrees/<name>/config                the shell's config screen
fw:///                                       names nothing (unchanged)
```

That is the whole change. Nothing else about addressing moves: the project stays
the URI authority, axes stay query parameters, everything after the plugin
segment stays opaque to the framework, and `config` stays a reserved id in the
plugin slot.

## Why, and why now

**Why a space segment.** Today the first path segment is a worktree name, so any
new top-level noun collides with a real worktree. `Worktree.mainName` already
records the conclusion for this exact problem: *no ordinary token is safe,
because git will happily give a linked worktree the admin name you reserved.*
`~` was chosen for the main checkout precisely because git cannot produce it.
The same reasoning applies one level up — the fix is structural, not a reserved
word. `fw:///ports`, `fw:///settings` and anything else cross-worktree now have
somewhere to live that no checkout can occupy.

**Why now rather than with the feature that wants it.** The address is designed
to be pasted — into logs, filenames, artifacts, agent output, docs. The window
to change its grammar closes the moment real artifacts start carrying it. Doing
it today costs a mechanical sweep. Doing it after the explorer ships costs a
parser that permanently carries the ambiguity we are removing.

**Why one plural noun, not `/worktree/<x>` + `/worktrees`.** Those are two nouns
one character apart meaning different things — a typo you would keep making, and
two things to remember. `/worktrees` is the collection, `/worktrees/<name>` is an
item in it; the relationship is structural rather than lexical. It also makes the
explorer *exactly* "the worktrees space with nothing selected", which is what it
is.

## Decisions already taken — do not relitigate

1. **No legacy-address compatibility branch.** Old-shape addresses do not parse
   after this lands. A compat branch would have to distinguish a space from a
   worktree name by consulting a registry of known spaces, which reintroduces the
   ambiguity this change exists to remove — for a project with no external
   consumers and no persisted addresses. Old addresses in old docs are stale
   anyway; §"Sweep" fixes the ones worth fixing.
2. **The parser does not validate space names.** It parses the segment as data.
   An unknown space is a *resolution* failure, reported where an unknown worktree
   already is (`ShellController.go` → `GoResult`), not a parse failure. This is
   what keeps `address.dart` free of a registry.
3. **`space` is a `String?` with a named constant**, mirroring
   `Address.shellConfig`. Not an enum: the point of the change is room for spaces
   that do not exist yet.
4. **The constructor defaults `space`.** `Address(worktree: 'x', plugin: 'y')`
   keeps working unchanged. See below — this is what keeps the blast radius
   small.

## The model change is smaller than it looks

`Address` keeps `project`, `worktree`, `plugin`, `segments`, `axes`. It gains:

```dart
/// The top-level namespace. `worktrees` is the only one today; the slot exists
/// so a cross-worktree screen can be addressed without competing with a
/// checkout for the first path segment.
final String? space;

static const worktreesSpace = 'worktrees';
```

with the constructor defaulting it:

```dart
space = space ?? (worktree != null ? worktreesSpace : null)
```

and one new invariant alongside the four already there:

- `worktree != null` → `space == worktreesSpace` (throw if a caller passes a
  different space *and* a worktree)
- `space != null` → `space` is not empty

**Because of the default, the ~26 real `Address(...)` construction sites do not
change.** Only `parse`, `toString`, `bare`, `copyWith`, `==` and `hashCode` do.
The blast radius is in **string literals**, not in code that builds addresses.

Parser: `parts.first` is still the authority; then `path[0]` is the space,
`path[1]` the worktree, `path[2]` the plugin, `path.skip(3)` the segments.
`_encode` applies to the space segment like any other.

## Blast radius — measured, not estimated

`fw://` string literals:

| where | files | occurrences |
|---|---|---|
| `lib/` + `app/lib/` | 12 | 22 |
| `test/` + `app/test/` | 11 | 69 |
| `docs/` | 8 | 17 |

The concentrations, which is where the work actually is:

- `lib/src/plugins/address.dart` (5) — the parser and its doc comment. **The
  change itself.**
- `test/plugins/address_test.dart` (33, 241 lines) — the grammar's test,
  including the assertion that this parser and `Uri.parse` agree. That agreement
  must still hold: the space is a path segment, not an authority.
- `app/test/shell/address_bar_test.dart` (14) and
  `app/test/shell/shell_controller_test.dart` (11) — navigation and the bar.
- `docs/superpowers/specs/2026-07-29-address-router-merge.md` (7) — **§3 is the
  decision this amends.** Amend it in place with a dated note pointing here;
  do not leave it silently contradicting the code.

Two files are **generated — do not hand-edit**:

- `app/lib/src/session/action_shapes.generated.dart` (4)
- `docs/capabilities.md` (1)

Both come from `app/tool/generate_capabilities.dart`. Regenerate them; a
hand-edit is caught by `test/session/action_shapes_test.dart` anyway.

## Order of work

1. `lib/src/plugins/address.dart` — the field, the constant, the invariant,
   `parse`, `toString`, `bare`, `copyWith`, equality. Update the class doc
   comment's grammar line, which is the first thing anyone reads.
2. `test/plugins/address_test.dart` — grammar cases first, including the
   `Uri.parse` agreement and a round-trip of `Address(space: worktreesSpace)`
   with no worktree (`fw:///worktrees`). Get this green before touching anything
   else; everything below is mechanical once the grammar is settled.
3. Sweep the remaining literals in `lib/` and `app/lib/`, then the tests.
4. Regenerate the two generated files.
5. Docs: amend the 2026-07-29 §3 in place; fix the literals in the other seven.

## Not in scope

- **The explorer.** No new screen, no `fw:///worktrees` destination, no chrome
  change. This session makes the address *representable*; the next one gives it
  somewhere to land.
- **`ShellController.go` behaviour.** `go(Address(space: worktreesSpace))` with
  no worktree will keep returning `GoResult.worktreeUnknown`. Slightly wrong
  wording, harmless, and it is the exact seam the explorer session picks up —
  leave it alone rather than half-building the destination.
- **The `project` authority slot.** Still reserved, still unused. Do not start
  populating it.
- **Any second space.** `worktrees` is the only one. Adding `ports` or
  `settings` speculatively is how the slot ends up shaped wrong.

## Done when

- `fw:///worktrees/<name>/<plugin>/<seg>` parses, round-trips, and equals an
  `Address` built from named parameters.
- `fw:///worktrees` parses to a space with no worktree and round-trips.
- The old shape `fw:///<name>/<plugin>` no longer parses as a worktree — assert
  this, so the removal is a fact rather than an accident.
- `fvm flutter analyze` clean; `cd app && fvm flutter test` and `fvm dart test`
  green (note: 5 pre-existing failures in `app/test/passthrough/` and
  `app/test/wrap/` predate this work and are not yours).
- `fvm dart tool/prepare_submit.dart` produces no diff. **Never bare
  `dart format`** — see CLAUDE.md.

## Traps

- **A fresh worktree has no `.fvm/`.** `fvm use --skip-pub-get` then
  `fvm flutter pub get` before anything runs.
- **`Uri` agreement.** `address_test.dart` asserts this parser and `Uri.parse`
  decide the same things. An authority is lowercased and a space name is not, so
  the space must stay a path segment. If that test starts failing, the fix is the
  code, not the test.
- **`_encode`, not `Uri.encodeComponent`.** The sparse encoding is deliberate —
  it keeps `team.dart%23TeamList` legible. Apply the same function to the new
  segment.
- **The `bare` getter** is what trees and maps key on. Forgetting `space` there
  gives two addresses that are `==` in one place and not in another.
