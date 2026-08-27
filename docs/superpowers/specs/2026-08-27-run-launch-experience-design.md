# The first ninety seconds of a run

*2026-08-27. Written after a consumer used Run on a real project for the first
time and reported three things: the build says nothing, the tabs go one way
only, and once something is running the launch form is gone.*

All three are real, all three reproduce, and none of them is a missing feature.
The log exists and is not shown, the tabs are disabled and do not look it, and
the launch form is reachable by address and not by any click. What is missing is
the state the cockpit spends the most user-visible time in and was designed
least for: **the run that has not started yet.**

---

## 1. What was measured

A `Studio (dev)` launch on macOS from this worktree, 2026-08-27, warm SDK and a
stale pub resolution. The launcher log is
`~/.flutterware/run/app-cbe6a1ba1ec4-12762-0.log`.

| phase | wall clock | what the log carried | what the panel said |
|---|---|---|---|
| pub resolution | ~15s | 26 plain lines — resolving, downloading, 22 outdated packages | `starting` |
| pod check + build | ~35s | CocoaPods migration advice, an Xcode script-phase warning, `Building macOS application...` | `Running pod install...` (stale — see §3.4) |
| attach | ~3s | `app.debugPort`, `app.started` | `reloadable` |

Fifty seconds in which the tool wrote 41 lines about what it was doing and the
GUI showed one word, and for most of it the wrong one. On a cold Android or iOS
build the same fifty seconds is three to five minutes.

The rail hijack (§3.3) was confirmed against the running window: with one run
live, clicking **Run** in the rail landed on
`fw:///worktrees/…/flutterware.run/app-cbe6a1ba1ec4` — the cockpit for that run
— and not on the launch form.

---

## 2. The shape of the problem

The cockpit was designed around a run that is **up**: a screenshot, a widget
tree, a log stream, a device strip, hot reload. Everything in `_RunView`
(`app/lib/src/plugins/native/run_plugin.dart:238`) is a view *of a live app*,
and the one state that is not — building — is handled by disabling all of it and
drawing a spinner.

That is the right instinct for a run that comes up in two seconds. It is the
wrong one for a run that takes minutes, and it is catastrophic for a run that
never comes up at all, because **every affordance that could tell you why is
switched off by the same flag that says you do not have an app yet.**

The flag is `RunProbe.canInspect`. Three things are gated on it that should
not be:

- the **Logs** tab, whose whole content is a file that has been growing since
  before there was an app;
- the **tab strip's** ability to move at all;
- and, transitively, the user's confidence that the tool is doing anything.

---

## 3. Findings

### 3.1 The build log is written from byte zero and shown nowhere

`launchApp` redirects the launcher's whole stdio into a file:

```
'-c', r'exec "$@" > "$FW_RUN_LOG" 2>&1 < /dev/null'
```

— `app/lib/src/run/launch.dart:166`. Everything `flutter run --machine` says,
plus everything gradle, xcodebuild, CocoaPods and pub say through it, is in that
file the moment it is said. `LogsTab` (`app/lib/src/run/logs_tab.dart`) already
follows it incrementally, filters by source, and filters to errors.

And it is unreachable while the build runs:

```dart
enabled: state.canInspect,                       // run_plugin.dart:302
if (!enabled && id != 'steps') return;           // run_plugin.dart:672
_ when !state.canInspect => _NotYet(…)           // run_plugin.dart:352
```

`_NotYet` (`run_plugin.dart:850`) draws a spinner, one line of status, and the
log's **path as selectable text**. Its own doc comment says *"The logs are
offered rather than described"*. They are described. A path is not an offer.

The same is true of `_FailedRunPage` (`run_plugin.dart:2563`): it shows the
trailing plain lines and, again, the path. A build failure is precisely the
moment somebody wants to scroll the whole log, and the page hands them a string
to copy into a terminal.

### 3.2 The tab strip has no disabled state, so it looks alive and is not

`InspectTabStrip` (`app/lib/src/inspect/inspect_dock.dart:176`) takes ids,
labels and badges. It has no notion of a tab that cannot be opened. The run view
enforces the disable by **swallowing the tap** (`run_plugin.dart:672`).

So during a build all six tabs render in the normal colour, take hover, and do
nothing — except Steps, which works. That is the reported symptom exactly:
*"one tab is available but then we can't switch back"*. You click Steps because
it is the one that responds, land on an empty journal (a fresh run has no
steps), and Screen no longer answers.

A control that is drawn enabled and does nothing is worse than a missing one:
it costs the user a hypothesis about their own machine.

### 3.3 `Run` in the rail cannot reach the launch form once anything is running

`RunCore.report.children` is the worktree's runs and its undismissed failures
(`run_core.dart:664`). The shell fills in a child whenever a plugin is selected:

```dart
void selectPlugin(String id) {
  var children = …report.children;
  var remembered = _lastChild[(selected?.path ?? '', id)];
  var child = children.any((c) => c.id == remembered)
      ? remembered
      : children.firstOrNull?.id;
  go(Address(worktree: name, plugin: id, segments: [?child]));
}
```

— `app/lib/src/shell/shell_controller.dart:1171`.

`_RunPanel` handles the empty address correctly and lands on `_NewRunPage`. It
is never given the empty address. **Nothing in the product ever navigates to
`/new`** — `grep newRunSegment app/lib` returns only `run_address.dart` itself;
every other hit is in tests.

This was believed fixed. `run_panel_test.dart:887` — *"Run lands on the page
that starts one, not on whichever run sorts first"* — mounts the **panel** at
`const []` and asserts `New run`. It is a true statement about the panel and
says nothing about the rail, which is the layer that decides. A test at the
wrong layer that passes is worse than no test: it closed the question.

Two consequences beyond the reported one:

- **A failed run blocks the form too.** Failures are children as well
  (`run_core.dart:675`). One failure you have not dismissed and `Run` opens the
  obituary forever.
- **The rail has two rows to one place and none to the other.** With one run,
  `Run` and `Studio (dev) · macOS` navigate to the same address. The launch
  form, the device desk and the only emulator-boot control in the GUI have no
  row at all.

`selectPlugin`'s fill-in is right for the plugins it was written for — previews,
scenarios, dependencies — whose children are *packages*: a stable set, and
landing on one is landing somewhere. Run's children are *instances*: ephemeral,
plural, and not the plugin's subject. One rule over two kinds.

### 3.4 The progress line is never cleared, so it reports finished work as current

```dart
case AppProgressEvent(:var message, :var finished):
  if (message != null && !finished) progress = message;
```

— `app/lib/src/run/launch.dart:332`. A finished span carries `finished: true`
and a null message, so it updates nothing. The last *started* span stays on the
header and in the rail until the next one begins.

Measured above: `Running pod install...` remained the panel's only word for the
thirty-five seconds *after* pod install finished, while Xcode was building. A
stuck build and a build between spans are indistinguishable, and the tool
confidently names the wrong stage of the one it is in.

### 3.5 Before the first structured event there is no narration at all

`LaunchLog.progress` comes only from `app.progress`, which `flutter run` emits
only once it has started working. Pub resolution — 15 seconds here, minutes on a
cold cache — precedes the daemon handshake entirely. `LaunchLog.summary` falls
through to the literal string `'starting'` (`launch.dart:403`).

`decodeRunLogLine` additionally drops `daemon.logMessage` at `trace` and
`status` level (`app/lib/src/run/logs.dart:136`) on the grounds that
`app.progress` covers them. It does not cover this window, and it is the window
where the user has least to look at.

### 3.6 A hung build holds the window's capture open for three minutes

`RunPlugin.busyWith` returns `'building'` while `RunCore.isStarting`
(`run_plugin.dart:72`), and `isStarting` is true for any own handle with no VM
service that has not stopped (`run_core.dart:201`). A build that hangs is never
either. `waitForSettle` then spins to its full three-minute timeout
(`app/lib/src/capture/settle_wait.dart:45`) for **every** panel capture in the
window, not just Run's.

Secondary to the reported complaints, and it falls out of the same gap: nothing
in the run model distinguishes *building* from *stuck*.

### 3.7 There is no second launch, and no relaunch

`RunCore.launch` returns as soon as the process is spawned and imposes no
serialisation — concurrent runs are supported by the model. What prevents them
is entirely §3.3: no door to the form.

`_RunHeader` offers Hot reload, Hot restart and Stop. Relaunching the same
configuration after a code change that needs a rebuild is stop, navigate to a
form you cannot reach, re-pick, Start.

---

## 4. The design

Four claims, in the order they should be built.

### 4.1 Building is a state of the cockpit, not the absence of one

Replace `_NotYet` with a **Launching pane**: the tab strip's default while
`!canInspect`, and a real pane rather than a placeholder.

It carries, top to bottom:

- **A stage line that is honest.** Derived from a widened `LaunchLog`: the
  current `app.progress` span *while it is open*, and when no span is open, the
  phase inferred from the log's own last plain line — `resolving dependencies`,
  `pod install`, `building`, `installing`, `attaching`. Never a finished span's
  message. §3.4 and §3.5 are one fix: the phase is a function of the whole log,
  not of the last event that happened to set a field.
- **Elapsed, against an expectation.** `started 66s ago` already exists in the
  header. Beside the stage, add what is normal for this platform — a `macos`
  debug rebuild is seconds, a cold `android` is minutes — and let the line change
  tone when it is past it. That is the whole of §3.6's user-facing half: a build
  that is *late* says so, rather than the tool and the user both waiting
  politely.
- **The log, live, below the fold and scrolling.** Not a path. `RunLogTail`
  already does the incremental read; the Launching pane hosts the same
  `LogsTab` body it will host after the app is up, so nothing switches under the
  user at `app.started` except the tab going from default to one of six.
- **Stop, and Stop-and-edit.** Stop already works while building
  (`run_core.dart:3156` explicitly permits it). *Stop and edit* stops and lands
  on the launch form primed with this run's configuration, which is the move
  somebody makes when the log tells them the flavor was wrong.

### 4.2 Logs and Steps are file-backed and never gate on the app

Move `logs` beside `steps` in the exemption at `run_plugin.dart:672` and in the
`switch` at `run_plugin.dart:352`. Both read files. Neither has ever needed a
VM service. This is a two-line change and it is the single highest-value line in
this document.

### 4.3 A disabled tab is drawn disabled

Give `InspectDockTab` an `enabled` flag and `InspectTabStrip` the rendering for
it — muted label, no hover, no ripple, and a tooltip saying *why* (`waiting for
the app`). Then delete the swallow at `run_plugin.dart:672`: with the strip
telling the truth, the guard is the strip's, not the caller's.

This is shared furniture — previews and scenarios use the same strip — so the
flag has to default to `true` and cost them nothing.

### 4.4 A plugin says where its own row goes

`selectPlugin`'s fill-in must stop applying to plugins whose children are
instances. The narrow fix is a property on the plugin:

```dart
/// Where the rail's row for this plugin lands.
///
/// Null means *the first child*, which is right for a plugin whose children
/// are packages. A plugin whose children are ephemeral — runs, sessions —
/// answers with its own landing instead, because "the first one" is not a
/// place.
List<String>? get railLanding => null;   // RunPlugin: const []
```

`selectPlugin` consults it before `children.firstOrNull`. `RunPlugin` answers
`const []`, and `Run` in the rail means the launch desk again — permanently,
whether nothing is running, one thing is, or one thing failed.

Then the test that closed this question moves to the layer that decides: mount
the **shell**, publish a run, click the rail row, assert the address is
`flutterware.run` with no segments. `run_panel_test.dart:887` stays as the
panel-level statement it correctly makes.

With the row fixed, the rail reads: `Run` → the desk; each run → its cockpit.
Two kinds of row, two destinations, no hover-only anything.

---

## 5. What is not in this

- **A `+` in the rail.** Rejected before and still rejected: `Run` being the
  door is one door, and §4.4 makes it work.
- **A run switcher inside a run** (see `project_run_desk_ungated`). The rail is
  the list.
- **Forwarding launcher output through a transport.** Nothing forwards logs in
  this repo and nothing should start; the file is the interface.
- **Killing a hung build automatically.** §4.1 makes lateness visible and leaves
  the decision where it belongs.

---

## 6. Order, and what each step is worth

| # | change | files | worth | |
|---|---|---|---|---|
| 1 | Logs ungated while building | `run_plugin.dart` | the whole of complaint 1 | **done** |
| 2 | Rail landing for Run | `native_plugin.dart`, `shell_controller.dart`, `run_plugin.dart` | the whole of complaint 3 | **done** |
| 3 | Disabled tabs drawn disabled | `inspect_dock.dart`, `run_plugin.dart` | the whole of complaint 2 | **done** |
| 4 | Honest stage line | `launch.dart` | the build stops lying about which stage it is in | **done** |
| 5 | Launching pane | `run_plugin.dart`, new `launching_pane.dart` | the build narrates itself | **done** |
| 6 | Elapsed-vs-expected, Stop and edit | `launching_pane.dart`, `run_plugin.dart` | a hang is visible and escapable | **done** |

1–3 are small, independent, and between them answer every reported complaint.
4–6 are the strengthening: they are what makes the state good rather than
merely not broken.

### What 1–3 look like, built

Measured against a cold `examples/example` build on the iOS simulator,
2026-08-27, from a second Studio driving this one:

* `Run` in the rail lands on **New run** with two runs live. The runs keep
  their own rows.
* At 31s in, the cockpit header reads `Running Xcode build...`, four tabs are
  grey and carry *waiting for the app — the log is live*, **Steps and Logs are
  not**, and the pane offers **Watch the log** rather than a path.
* The log pane draws 105 lines of that build — pub resolution, the CocoaPods
  advice, `Launching … on iPhone 16e` — with its source pills, its errors
  toggle and its search, all before there is an app.
* Tapping the grey `Screen` leaves the address on `…/logs`, and the log goes on
  arriving: 126 lines, ending `Xcode build done. 41.0s`.

Steps 4–6 are what the header still wants: `Running Xcode build...` is honest
here only because the span was open when the picture was taken.

### What 4–6 look like, built

`LaunchPhase` is the ladder, and `LaunchLog.stage` is the phrase: an open
progress span when the tool is narrating, the furthest milestone the log has
passed when it is not, and **null** once the run has started, stopped or
failed — because `building` said about a dead run is the same lie in a new
place. `progress` now tracks open spans only, so a finished one stops being
what the launcher is doing. Every reader moved: the header, the rail row, the
`launch` and `inspect` action results, and `awaitLaunch`'s narration — which
means `fw` and an agent are told about pub resolution too, where before they
watched a blank space until the daemon handshake.

`LaunchingPane` replaces `_NotYet`: the stage as its headline, the elapsed time
against `coldBuildBudget(platform)` under it, **Stop and edit**, and the live
`LogsTab` filling the rest. Past the budget the line and the spinner go amber
and the sentence changes from *usually finishes within 4m* to *longer than a
cold ios build usually takes*. The header's capability pill is suppressed while
this pane is open, by the rule the rail already follows: a row does not repeat
what the row under it is saying.

Measured live, `examples/example` on the iOS simulator at 10s in:

> **Running Xcode build...**
> 10s in — a cold ios build usually finishes within 4m.  · *Stop and edit*

with 35 lines of that build underneath it.

**What 4–6 did not do.** `coldBuildBudget` is a table of generous round
numbers, not a measurement. The figure worth having is this project's own last
successful launch on this platform, and nothing records one — a run's handle
knows when it started and never when it came up. That is the next thing to
build here, and it turns the expectation from a guess into a fact.

`_FailedRunPage` was also still the old shape when this was written. It is not
any more — see §7.

### Four things review caught

1. **Stop and edit primed the form with resolved knobs.** A handle records what
   the app was *built with*, which includes every knob a `from:` worked out for
   a field nobody touched; the form's contract is the other one, where text in
   a field is a deliberate override. So the SDK path stopped tracking whichever
   flutterware launched you, and a per-worktree port froze to the one that run
   happened to get — the failure `_resolveKnobs` already documents.
   `RunCore.chosenKnobs` drops a recorded value that equals what its source
   computes now, which errs safe both ways.
2. **The first probe ran before there were handles to probe.** `track()` fired
   `_probeAll()` alongside `computeAll()` rather than after it, so `_probes`
   stayed empty until the 5s timer — and the panel spent those seconds drawing
   every announced run with a null probe. With the launching pane measuring,
   that made a three-hour-old app read as an overdue build, in amber.
3. **An unprobed run was measured anyway.** Belt to the same braces: `elapsed`
   is now null without a probe, and the expectation line goes with it. Before
   anything has asked, a handle that has not answered is as likely to be a live
   app as a build, and the pane may not turn that into a claim.
4. **The expectation named a device id as a platform.** `platformLabelFor`
   falls back to the id so prose always has a noun, which is right for prose
   and wrong for a sentence that then quotes a number. `RunCore.platformOf`
   answers null instead, and the pane says *a cold build*.

And one worth writing down for its own sake: the first cut of `chosenKnobs` was
a collection-`if` with two arms —

```dart
if (declaredByName[knob.key] case var declared?)
  if (computedValueOf(declared) != knob.value) knob.key: knob.value
else
  knob.key: knob.value,
```

— where the `else` binds to the **inner** `if`. Every declared knob was kept
and every undeclared one dropped: exactly backwards, and it reads correctly.
It is a plain loop now.

---

## 7. The failure page

The last page printing a path instead of the thing it names, and the one where
that hurt most.

`LogsTab` took a `RunHandle`, and a failed launch has none: the handle is
deleted the moment the launcher dies without starting, because a launcher that
is not there must not go on telling the next person a phone is busy. What
survives is a `RunFailure` — a path, a key, and nothing that can be asked a
question. So the state where the log matters most was the one state with no run
to point the log pane at.

`LogsTab.ofFailure` takes the path and the key directly. The `Platform` pill is
dropped there rather than offered and refused: a device log is read by asking a
session about a window of time, and a launch that never came up has no session.
The page is now the reason on top — capped at 168px, scrolling, because it is a
glance — a divider, and the whole log filling the rest. The path is no longer
printed; the log pane's own menu carries it, beside the lines it names.

### The Errors filter found no errors

Measured on a deliberately broken example app, 2026-08-27: `Errors` matched
**0 of 44** on a log whose whole point was the fault it could not find.

`RunLogLine.error` was set by two things — a structured error event, and the
engine's `[ERROR:…]` severity prefix. A Dart build failure produces neither.
The launcher's structured error is `Error: Build process failed`, which is true
of every build failure and names none; the line that says *which* one is the
front end's own diagnostic, and nothing was looking for it:

```
lib/main.dart:119:21: Error: Method not found: 'notAThing'.
final int _broken = notAThing();
                    ^^^^^^^^^
```

Two shapes added, both fixed strings from one emitter each — which is the test
`RunLogLine.error` already applies, and is why it can take them without
weakening its refusal to read a fault out of prose:

* `^\S+:\d+:\d+: (Error|Severe): ` — the Dart front end. Path, line, column,
  severity; a sentence does not produce that by accident.
* `^\*\* BUILD FAILED \*\*` — xcodebuild's last word.

Gradle's `e: file://…` is **not** in there. No log measured here has carried
one, and this repo does not add a rule to a matcher on the strength of a guess.
The next Android build failure that lands is what earns it.

Same run after the change: **2 of 44**, in red, and they are the two lines
anybody wanted.

### Still not closed

`Start again` from the failure page. `Dismiss` already lands on a form this
session has primed, so the button would be a rename in the common case — but a
failure recorded by `fw` in a terminal and read in the GUI has nothing primed,
and there the button would be real. It needs care: priming from a `RunFailure`
loses the knobs, which it does not record, so it must not overwrite a richer
`lastLaunch` that a launch from this panel already left behind.
