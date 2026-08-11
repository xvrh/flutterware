# The dev stack on screen — what was wrong, and the rules that replaced it

The plugin worked end to end and looked like a first draft. This is the read of
what was wrong with it, the rules that came out of redrawing it, and what
shipped. The mockups it was decided from were rendered in the app's own dark
palette and type ramp; what survives here is the reasoning, which is the part
that has to outlive the pictures.

Companion to `2026-08-10-dev-stack-design.md`, which is about what the plugin
*is*. This one is only about how it reads.

## 1. What was wrong

The worktree overview drew this, under two chips on an otherwise empty page:

```
Example server  delegated to examples/example
● up · localhost:8080 · pid 493 · just now
[ Tear down ]
Logs   Check now
```

1. **The loudest control on the page was the destructive one.** Nothing else on
   the overview was a button. A screen whose job is orientation led with the
   verb that breaks things.
2. **Four unlike facts, one separator, one weight.** A state, an address, a
   process and a freshness reading, given identical dots and identical colour.
   Nothing told the eye which one was the answer.
3. **A pid was on the glance surface.** It matters about once a month.
4. **The secondary actions had no affordance.** `Logs` and `Check now` were
   plain ink at body size — the same treatment as the sentence above them. You
   found out they were buttons by hovering.
5. **Nothing framed it.** The block floated under the chips with no container.
6. **The compact form dropped the services.** The one screen you glance at was
   the one that could not say *what* was up; the panel you navigate to could.
7. **The sidebar slot is 100px and we sent it a sentence.**
   `up · localhost:8080 · pid 493` rendered as `up · local…` — the ellipsis ate
   the informative half and left the one word that was never in doubt.
8. **The cross-checkout question was unanswerable.** A port block belongs to a
   checkout, so the real question is *which of my eight worktrees is holding one
   up*, and the explorer said nothing.
9. **A normal day and a broken one differed only by hue.** `down` is expected
   and `unavailable` is a fault; both were a coloured dot and a lowercase word
   in the same slot at the same size.
10. **A transition was twenty seconds of nothing** — a disabled button, while
    the output pane below said *Nothing has been run from here yet*.

## 2. Precedents worth obeying

- **Container managers** (Docker Desktop, OrbStack): state left, control right,
  on one optical line, at opposite edges so they never compete.
- **Dev-cluster dashboards** (Tilt): the roll-up is *derived* from the
  per-resource rows, so a green header cannot disagree with a red row.
- **`systemctl status`**: the answer is the first line; pid, memory and the log
  tail are indented beneath it and smaller.
- **Hosting dashboards** (Vercel, Railway, Supabase): state on the card's edge
  rather than inside the text, freeing the text to carry the URL.
- **Xcode / Android Studio**: one control slot whose contents are the state —
  you never scan two buttons to find the applicable one.
- **flutterware's own Run panel**: small bold muted caps for section labels, a
  value in ink with a muted qualifier beside it, one filled accent button,
  warnings in amber beside the control they qualify. The stack block shared
  almost none of it and now does.

## 3. The six rules

- **P1 — One state, one word, one colour, one place.** The state word is the
  only thing in the block rendered in a tone colour, and it is set at heading
  size. Ports, ages and paths go neutral.
- **P2 — Answer, then evidence.** The answer is the state and the one fact that
  makes it actionable. Services, freshness and provenance are evidence:
  smaller, muted, skippable.
- **P3 — Anatomical constancy.** Every state fills the same slots in the same
  order. A failure takes the address's slot; it does not rearrange the block.
- **P4 — The safe direction gets the weight.** `Bring up` is filled only when we
  know the stack is down. `Tear down` is never anything but a quiet outline.
- **P5 — Freshness is metadata until it is stale.** `just now` beside a state
  implies the state is in doubt. It moved to the section line; it is promoted
  into the state's own slot only when the reading is genuinely old.
- **P6 — Glance surfaces get a word.** 100px is twelve characters.

## 4. The three directions, and why C

**A, the status line** — one dense row, name, state, facts, actions. Cheapest,
and the only one that would still work if a project ever declared three stacks.
But it is a run-on with better spacing, and it has nowhere to put a failure
sentence — the state that most needs one.

**B, the card with a tone rail** — a bordered card whose left edge carries the
state, header, service rows, footer of actions. Encodes state twice, which is
what makes it survive a squint. Too heavy: a card with a footer rule implies
siblings, and there is one stack.

**C, answer and evidence** — the state word set large and as the only coloured
thing, the address directly under it, actions right-aligned on the same optical
line, evidence on one muted row below a hairline. **Chosen, with B's rail.**
What C has that neither of the others does is a second slot under the state
that changes meaning per state *without moving*: the address when up, the reason
when down, the failure when the probe broke.

## 5. What shipped (2026-08-11)

| | |
|---|---|
| `app/lib/src/dev_stack/stack_block.dart` | the block, rewritten — section line, railed card, answer/evidence, `_Link` |
| `app/lib/src/plugins/native/dev_stack_plugin.dart` | panel: block → Commands group → Output → provenance footer |
| `app/lib/src/plugins/native/dev_stack_core.dart` | `busyFor`, `isProbing`, `isStale`, `canStart`/`canStop`, word-sized statuses |
| `app/lib/src/plugins/native/dev_stack_results.dart` | `serviceCount`, `isPartial` |
| `app/lib/src/shell/worktree_home.dart`, `shell_view.dart` | `Open panel →` wired to `selectPlugin` |

Three behaviours are new rather than redrawn:

**`up, 3 of 4`.** The probe already reported per-service states and the block
rounded them all to `up`. The headline is now derived from the rows — Tilt's
rule — and the sidebar says `up 3/4`. A service list with no states counts
nothing rather than counting everything as down.

**A transition is clocked.** `busySince` lives on the core, not the widget, so
opening the panel eight seconds into a bring-up shows eight seconds instead of
starting again. Elapsed seconds and an indeterminate bar are the only progress a
*delegated* command can honestly report: nothing here knows what the project's
script is doing, only how long it has been doing it.

**A cold open says what it last saw.** There is a disk cache, so the honest
first frame is the last reading and its age — not "not checked yet", which threw
away a fact we were holding. The word draws muted and both controls are disabled
until the first probe of the session confirms it, because acting on history is
exactly what the muted rendering is warning about.

### Decided while building

- **The block caps at 720px.** Left to fill a maximised window the card
  stretched to eleven hundred pixels and put `Tear down` most of a screen away
  from the `up` it belongs to. A card has a reading width the same way a
  paragraph does.
- **The rail is a clipped child, not a border.** Flutter refuses a
  `borderRadius` on a border whose sides differ.
- **`down` gets no rail colour.** A checkout you are not working in *should*
  have its stack down; only `up`, a transition and a failure colour the edge.
- **A transition never settles.** The bar animates and the clock schedules a
  frame a second, so `pumpAndSettle` hangs while one is in flight and tests use
  `pump()`. Window capture is unaffected — it settles on `busyWith`, which is
  exactly the thing that is true during a transition.
- **The panel's empty output no longer quotes the probe.** It is a command with
  an absolute SDK path in it; repeating it inside a sentence made the sentence
  unreadable to explain what the new provenance footer states plainly.
- **The commands group takes all of them.** One treatment whether or not a
  command needs an argument, rather than bare links for some and a field row for
  others.
- **The evidence rule only draws when there is a list under it.** Above a row
  holding nothing but `Open panel →`, it drew a compartment around empty space.
- **`checking` is the block's word; `not checked` is the status's.** The block
  says `checking` because the block is the surface that actually probes on
  mount. `fw` and a cold sidebar have started nothing, so their status must not
  claim otherwise — caught by running `fw status` and reading a lie.

### Two bugs the screenshots found

Both were invisible in the code and obvious on screen, which is the argument
for photographing every state rather than the happy one.

- **A `detail` on an `unavailable` reading was being dropped.** The example's
  script writes one explanatory line and puts it in `detail`, like every other
  line it writes; only `failure` was read, so the panel rendered *the check
  could not be run* over a probe that had said exactly what was wrong. `detail`
  is now taken as the reason when the state is `unavailable` — two keys for one
  sentence is a distinction a script author has no reason to make.
- **A pid was still on the glance surface**, because the detail string is the
  *project's* words and finding 3 cannot be fixed from this side. The example's
  script now reports the address alone; the pid lives in `logs` and the state
  file, where it is wanted about once a month.

### Not built, and why

- **The explorer column** (finding 8) — the largest piece. It needs a fifth
  `WorktreeFacts` provider reading the existing `stack-<hash>.json` cache and
  **never probing**: a list of eight checkouts must not spawn eight subprocesses.
  The column budget in `explorer_row.dart` is already tight enough to have
  needed a drop order.
- **Live output during a transition** — `runProcess` returns a finished
  `ProcessResult`, so streaming needs a second variant of the seam. The clock
  and the bar are what landed instead.
- **Services as `PluginChild`ren** in the sidebar — the mechanism the Run plugin
  already uses, and it would give the CLI and an agent the same breakdown. A
  different surface from this study's subject; worth doing next.
