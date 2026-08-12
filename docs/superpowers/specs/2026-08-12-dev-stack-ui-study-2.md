# The dev stack on screen, second pass — the strip, and a panel with something in it

The first study (`2026-08-11-dev-stack-ui-study.md`) turned a run-on line into a
railed card and gave the plugin six rules. This pass is about what was still
wrong once the card was right: it is too big for the screen it sits on, it
carries a control whose result happens somewhere else, and the panel it links to
is mostly empty.

Read off the running app on 2026-08-12 — stack up, light theme, maximised
window. The mockups the directions were chosen from were rendered in the app's
own palette and type ramp; what survives here is the reasoning.

## 1. Four findings (continuing the first study's numbering)

11. **The glance surface is a card, and the answer is one word.** 142px — a caps
    section line, a bordered card, a 3px rail, an internal rule, a 20px coloured
    word — sitting alone on a page that is otherwise a title and two chips.
    Nothing else on the worktree overview is that loud, and nothing else on it is
    that short an answer.

12. **A control on the overview wrote to a screen you were not on.** The block
    promoted the project's first argument-less command — in practice `Logs` — to
    a link beside `Tear down`. Pressing it ran `dart tool/stack.dart logs` and
    put forty lines into the *panel's* output pane. From the overview the button
    appeared to do nothing at all. Reported as "there are some buttons we don't
    know what they do", which is the polite version.

13. **Colour was used at hairline width and nowhere else.** State was carried by
    a 3px rail and an 8px dot against neutral chrome. Legible, but it cost a
    whole card to be legible *at all*: the frame existed mostly to give the rail
    an edge to be.

14. **The panel repeated the block and then had nothing to say.** The 720px card
    was mounted verbatim at the top of a panel twice that wide, above two
    mismatched command controls and three hundred pixels of empty state — while
    facts the core already held (per-service state, the exit code, how long the
    command took) were never drawn.

## 2. Precedent

The first study read container managers for the card. The question this time is
narrower: how do tools render a service's state when it is *not* the subject of
the screen, and how do they use the screen when it is.

- **GitHub Actions** — state is a tinted full-width band, not a bordered card.
  One line of type; the colour is the frame.
- **Vercel deployment rows** — dot, name, target, age, trailing chevron on one
  44px line. The row is the link; there is no separate "open" control.
- **OrbStack container list** — a row carries only the control that changes that
  row's state. Everything else lives on the detail page, next to its own output.
- **Tilt** — services are a table with a state column, and the roll-up is
  derived from the rows.
- **Xcode's console** — output with the invocation echoed above it and a result
  badge. You always know which command produced the text you are reading.
- **flutterware's own Run panel** — the house shape for a working page: bold
  title, muted subtitle, controls flush right, content edge to edge. The stack
  panel shared none of it.

## 3. Three directions, and why A

**A, the status strip** — one 40px tinted line: dot, state word, name, address,
services, the one state-changing control, chevron. The row is the link into the
panel. **Chosen.**

**B, the tile** — 72px, two lines, tinted; services always on their own line and
a failure sentence has somewhere to go without reflowing. Costs a second line
every good day, and earns it only if a project ever declares two stacks.

**C, the header chip** — the stack becomes one more chip beside the branch. Zero
added height and honest about the question being yes/no, but bringing a stack up
then always costs a navigation and a failure has nowhere to live.

A was picked with B's services folded into the line and C's discipline about
controls. Two rules came out of it, and they generalise past this plugin:

- **The tint is the frame.** A ~12% wash of the state's own tone with a matching
  edge (`FwPalette.statusFill` / `statusBorder`, which already existed for the
  dependencies panel) reads from across the desk and needs no card. `down` still
  gets no tone — a checkout you are not working in *should* have its stack down,
  and a permanently tinted overview is a tinted overview.
- **A glance surface may only carry controls whose result is visible on it.**
  Finding 12 is not a labelling problem. `Bring up` and `Tear down` change the
  word right beside them; `Logs` changes a pane on another page. Commands live in
  the panel now, next to the console they write to.

## 4. What shipped (2026-08-12)

| | |
|---|---|
| `app/lib/src/dev_stack/stack_block.dart` | `DevStackForm.strip` / `.band` replacing the `compact` flag — two chromes over one state machine |
| `app/lib/src/plugins/native/dev_stack_plugin.dart` | panel rebuilt: header band → services table → command rows → console → one-line provenance |
| `app/lib/src/plugins/native/dev_stack_core.dart` | `lastExitCode`, `lastRunFor` |
| `app/lib/src/shell/worktree_home.dart`, `app/tool/catalog/demos/dev_stack.dart` | the new form |
| `tool/flutterware.dart` | a description for our own `logs` command |

**The strip.** 142px → 40. The section line goes (the strip names itself), the
freshness goes to the panel and comes back into the line only when the reading is
stale, and `Open panel →` is retired in favour of the row itself plus a chevron.
The name, the address and the services are one run of rich text rather than three
laid-out slots, so it truncates in priority order: services first, then the
address, then the name. One state is allowed a second line — `unavailable`,
whose reason is the whole point and cannot be read ellipsised at 200px.

**The band.** The panel's header, in the Run cockpit's anatomy: name in ink, the
state word beside it, address and working directory and freshness muted beneath,
`Check now` and the state control flush right, tinted the same as the strip. The
panel offers `Check now` always; the strip only when the *reading* is the problem.

**Services became the page's first section.** A table with the probe's own state
word per row. A service the project reported no state for reads `not reported`
rather than being rendered as one it did — the same rule `serviceCount` follows
when it refuses to count a partial declaration. No `Open ↗` was built: nothing in
`StackService` declares a protocol, and opening `http://localhost:5432` in a
browser because a port looked web-ish is a guess this plugin has no business
making.

**Every command looks like a command.** One row shape — name, the project's
description as a subtitle, an argument field only where one is declared, `Run`
flush right. Where no description was declared the row falls back to the
invocation in monospace, which is the same fallback the action list already gives
`fw` and an agent. **That fallback found the actual cause of finding 12**: our
own `tool/flutterware.dart` declared `StackCommand('logs', 'Logs', [...])` with
no description at all, so there was nothing to render and never had been. The
declaration now carries one.

**The output pane became a console.** The invocation is echoed as a `$` prompt
line above its own output, and the exit code and the duration are shown — both
were already on `DevStackRunResult` and reaching the CLI and agents, and the
panel had been throwing them away, so a command that printed a warning and
exited 1 looked exactly like one that worked. The executable is shortened to its
basename for display (`dart tool/stack.dart up`, not seventy characters of
pinned-SDK path); the footer still carries the whole of it, with a copy control.

### Decided while building

- **The console takes the space the sections leave**, via
  `SliverFillRemaining(hasScrollBody: false)` — pinning it to the bottom left a
  void in the middle of a page whose sections are short, which is the same
  emptiness this pass exists to remove. A stack with six services and four
  commands pushes it down and the page scrolls.
- **Section content caps at 880px** through an `Align` — a bare `ConstrainedBox`
  under `CrossAxisAlignment.stretch` has its width enforced right back over it,
  which is why the first attempt did nothing.
- **A `Spacer` beside a `Flexible` leaves the slack at the far end.** The service
  rows' state column landed in the middle of the page until the name was bounded
  instead of flexible.
- **The band drops the freshness while the reading is unconfirmed.** The detail
  already says `last seen 1m ago · checking now`; adding `checked 1m ago` reads
  as two different facts about one probe.

### Not built

- **`Open ↗` per service** — see above; needs a declared protocol, not a guess.
- **A transcript** — the console is the last command's tail, deliberately. The
  stack's own `logs` streams the real thing in a terminal that can scroll and
  search.

---

## The alignment pass (2026-08-12, later)

Everything above was right about *what* was on the page and wrong about where
the pixels landed. Read off the running app again:

- **The header's controls hung off the title line.** `Check now` and the button
  were laid out against the top of a two-line block, so they sat high and — being
  different heights — did not agree with each other either. Both are centred
  against the block now, which is what the Run cockpit's header already did.
- **`Run` stepped down the page with the descriptions.** Same cause in the
  command rows: top-aligned controls beside text that is one line or two
  depending on what the project wrote, and a text field that is taller than the
  button beside it. Centred, every row's controls sit in the middle of what they
  act on and on the same line as each other.
- **Three right edges.** The sections capped their width at 880 while the header,
  the console and the footer ran full-bleed, so trailing content — the state
  control, a service's state, `Run`, `Copy` — landed on three different edges.
  `DevStackColumn` is now the one column every band of the panel is laid out in,
  and there is one edge.
- **The name and the state word are set on a baseline**, not centred on each
  other's boxes: 16px beside 13px centred is 16px beside 13px sitting slightly
  low. The dot stays out of that row — a circle has no baseline.
- **`Copy` was the one control you found by hovering**, and the link underline
  was a hairline that vanished into the header's tint. Both links wear the same
  `mut3` underline now.

Measured after: the strip's dot, word, summary, button and chevron all centre on
one line, and the block is 44px tall against the old card's 142.
