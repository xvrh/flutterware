# The scene grammar round-trip — the tier-2 bet, measured

**Date:** 2026-08-31
**Status:** findings from a working spike with a passing test suite. The
grammar is provisional; the *engine shape* and the invariants are the result.
**Context:** motion v2's spike #1 — *"grammar on a page, parse and emit,
fuzz `emit(parse(x)) == x`, hand-edit hostilely"* — run against the canvas
toy's touched scene model rather than a predicted one, wearing every scar the
drawing-plugin exhumation recorded.
**Artifacts:** `app/lib/canvas_toy/scene_file.dart` (grammar comment, parser,
emitter — ~650 lines) and `app/test/canvas_toy/scene_file_test.dart`
(round-trip, 300-document fuzz, idempotence, fifteen hostile edits).

## What was built

A one-page grammar (in the file's header comment): marker line, file-level
comments and imports, one class with one `final root = Frame(…)` field, nodes
as constructor invocations (`Frame`/`Text`/`Shape`/`Ext`) with fixed named
vocabularies, values limited to literals, `Color(0x…)`, allowlisted enums,
child lists and literal-only `args` maps. A **collecting** parser — never
fail-fast, all-or-nothing on the document — and a **canonical** emitter
through the pinned `dart_style`.

All 20 tests passed on the first full run, fuzz included.

## Finding 1 — the invariant had to be restated, and the restatement is better

Motion v2's single invariant — *`emit(parse(f)) == f` for every file the
editor accepts* — cannot survive the first friendly tolerance: accept
`1024.0` where the canonical spelling is `1024`, or `0xff…` for `0xFF…`, and
identity on files is already broken. Refusing those spellings instead would
make hand-editing hostile for no reason. What the tests actually hold is a
triple:

1. **`parse(emit(m))` reproduces `m`** — identity on *models* (checked via
   emit equality, 300 fuzzed documents).
2. **`emit(parse(f)) == f` for canonical files** — identity on emit's image.
3. **Accepted non-canonical files converge in one emit** and are stable
   thereafter.

The grammar defines *accepted*; the emitter's image defines *canonical*; the
editor never widens the gap because it only ever writes canonical. This is
the honest version of the round-trip promise and the one the real
implementation should state.

## Finding 2 — refusal is a policy, and collecting is the policy

The drawing plugin shipped three failure behaviors in one small parser (drop,
skip, throw) and the drop was a disk-eating shredder. Here there is exactly
one: **every out-of-grammar construct adds a refusal naming what was found,
where, and what was expected; a file with any refusal yields no document; and
all refusals are reported at once.** The probe output, verbatim:

```
line 3: comment — comments inside the scene are not preserved by the editor,
        so they are refused rather than silently lost on the next save
line 6: arithmetic — expected a number literal
line 7: identifier — expected a color, spelled Color(0xAARRGGBB)
line 8: for element — a scene lists its children one by one — the editor
        cannot read a computed list
```

Fifteen hostile constructs are covered — `for`, interpolation, method calls,
conditionals, arithmetic, off-allowlist identifiers (including
`Colors.white`), unknown properties, unknown node types, duplicate names,
adjacent strings, in-scene comments, extra class members, a missing marker,
multi-fault files, raw syntax errors — and none of them throws. The refusals
name constructs a *Dart programmer* wrote in good faith, which is the v2
prediction ("an agent reaches for a `for` loop because that is good Dart")
holding at the door.

## Finding 3 — comments are refused at the door, as designed

A comment inside the scene body is refused with the reason ("not preserved by
the editor… refused rather than silently lost on the next save"), while the
file-header region — above the class body — stays free for the ownership
banner. This makes the emit-regenerates-everything strategy safe by
construction: nothing that can enter can be lost. The modelled note field
(motion v2 open question 3) remains the way to give comments back.

## Finding 4 — canonical spelling is three small rules, not a system

Numbers: an integral double is an int literal; anything else is Dart's own
`toString`, which is round-trip lossless for doubles. Colors:
`Color(0xAARRGGBB)`, uppercase. Strings: single-quoted with six escapes
(`\\ \' \$ \n \r \t`), everything else — emoji included — verbatim. The
formatter is part of the identity, so its version is part of the format;
`dart_style` is pinned by the lockfile and should be named in the real
format's version marker.

## Finding 5 — identity is enforced where it is cheap: at parse

A node's name is its identity (keys, rects, the wire). The parser refuses a
duplicate name with both locations implicated, so the invariant every other
layer assumes is established at the one door everything enters through.

## Finding 6 — the owner's risk assessment, now measured twice

*"The parse-and-emit is engineering with known failure modes — the risk is
the surface, not the parser."* The whole engine is ~650 lines, written in one
sitting, and the 300-document fuzz passed on its first run. The two places it
bit were both **analyzer-13 AST migrations** (`ClassBody` behind
`BlockClassBody`, `ArgumentList` yielding `Argument` rather than
`Expression`) — the same class of change the repo has already absorbed in the
scan and shape extractor, and a reminder that the parser's real maintenance
cost is tracking the analyzer's API, not the grammar.

## Honest limits

- **The emitted file is parsed, never compiled.** Its node spellings
  (`Text`, `Frame`) collide with Flutter's own when compiled against
  material — fine for a parse-only spike, and a real decision for the
  runtime: non-colliding class names (`SceneText`?) or no material import,
  which then costs the `Color` spelling its class. The naming is provisional
  either way.
- **This is the scene vocabulary, not motion's.** Tracks, keys and machines
  are a bigger surface; what transfers is the engine shape — collecting
  parser, canonical emitter, the invariant triple — and the grammar-comment
  discipline.
- **Structural-edit preservation is untested because it is moot**: the
  emitter regenerates whole files, which finding 3 makes safe.
- The spike is not wired into the editor yet; save/load in the composited
  canvas is the natural next increment, and `fw scene check` is this parser
  behind a CLI door.
