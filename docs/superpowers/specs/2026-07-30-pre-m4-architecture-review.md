# Pre-M4 architecture review — is the substrate ready for a second consumer?

**Date:** 2026-07-30
**Status:** Findings, with a committed fix list. Reviewed `master` at `8767483`
(the `fw capture` PR), before starting M4 (the scenario runner). Four
independent review passes — embedder substrate, app-side catalog, published
runtime + guest, and the GUI/CLI/daemon/MCP seams — every claim below verified
in code, not taken from the specs it cross-checks.

## The question, and the answer

M4 builds on everything the catalog built: resident compiler, generated
entrypoint, guest engine, capture, daemon, addresses. The question was whether
any of that deserves costly rework *before* a second consumer entrenches it.

**The answer is no.** No architectural mistake was found that the scenario
runner would entrench. The load-bearing claims of the July specs hold in code
and are machine-checked, not conventional:

- The compiler stack is genuinely multi-consumer: per-session kernels and
  deltas, per-session baselines, `reset()`/`reject()`, one serialized queue.
  S3's economics are implemented, not just measured.
- The daemon's concurrency story (lock + post-lock re-connect, atomic-bind
  loser-exits-0, stale-socket cleanup under the lock, idle suicide) is real and
  integration-tested.
- CLI purity holds: `fw`, `mcp` and the compiler daemon reach zero
  `package:flutter`/`dart:ui` files, and `entry_point_purity_test.dart` guards
  it in CI.
- `Address` is one grammar across GUI routing, `fw capture`, artifacts and MCP;
  the 07-29 address-router-merge spec is essentially fully landed. `Session.invoke`
  is the one dispatch door and the parity test drives both surfaces through it.
- The suspicious-looking pairs are not duplication: `devices.dart` is the single
  device source with `catalog_devices.dart` a mapping layer (test-asserted);
  live and web generation share `CatalogWrapperWriter` and `buildCatalogTree`;
  knob/axis/inspect wire types are defined once in the published package and
  imported directly by the app.

What remains is one theme the catalog could get away with and the runner
cannot — **concurrency between clients of the shared substrate** — plus a
closing publish window, three decisions, and a deletion pass. Days, not weeks.

## Fix now, before M4 (committed scope)

1. **Headless captures collide machine-wide.** `_GuestSession.start` derives
   its socket as `shot-<sha1(workDir)>.sock`, but `workDir` is always
   `appPackageRoot/build/catalog` — one constant path per install
   (`headless_catalog.dart:716`, workDir at `:128, :182, :329`). The comment
   claiming the derived name prevents collision derives it from a value all
   captures share. Every capture also writes the same
   `screenshot.rawframe` and `knobs.scratch.png` scratch files. Two concurrent
   `fw` captures — two agents, or agent + GUI, the normal M4 case — delete each
   other's sockets and swap frames, producing plausible wrong pictures
   silently. The GUI already fixed this exact bug (`cap-$name` per engine,
   `embedded_engine.dart:102`); the headless path has `ready.sessionId` in hand
   and does not use it. Key socket and scratch dir on the session id.

2. **The daemon's `_active` is global; `ifChanged` answers for the wrong
   client.** One `_active` per daemon (`compiler_daemon.dart:176`), and the
   `ifChanged` fast path requires `_active?.id == id` (`:561-573`). The GUI
   fires `reloadIfChanged` on window focus so alt-tabbing never loses demo
   state — but the moment any other client selects a different entry, the
   GUI's next focus reload gets a real compile *and a state-resetting hot
   reload* for an entry its guest was already showing from unchanged sources.
   Under M4, agent/GUI alternation makes this constant ping-pong. Track the
   last-selected entry per `_Session`; answer `unchanged` from the session's
   own entry + disk state. Add an interleaved-two-client select case to
   `compiler_daemon_test.dart` (the multi-client group covers attach, not
   interleaved selects).

3. **`CatalogSession.start()` leaks the daemon client when disposed
   mid-start.** `dispose()` during `await CompilerDaemonClient.connect(...)` —
   which spans the cold compile, i.e. exactly when someone is editing
   `tool/flutterware.dart` and config reload is tearing plugins down — closes
   nulls; when `start()` resumes it assigns `_daemon`, subscribes, then hits
   `if (_disposed) return;` without closing either
   (`catalog_session.dart:844-869`). The leaked client keeps the daemon's idle
   reaper from ever firing. Same shape at `LiveSession.publish` (`:929` before
   the `:937` check). After every await in `start()`, on `_disposed`, tear down
   what that await produced. The fake-daemon harness in
   `daemon_client_test.dart` can drive a test.

4. **Guest startup can hang forever or orphan the process.** The accept is
   raced against `guest.exitCode`, but the VM-service-URI wait is not, in
   either `_GuestSession.start` (`headless_catalog.dart:754`) or
   `CatalogSession` (`catalog_session.dart:910`); a guest that dies before
   printing its URI (or whose stdout format drifts past the scrape regex)
   hangs the caller with the process orphaned, and a throw from `connect`
   kills nothing. Race the URI against exit + a deadline; kill on any
   startup-path exception.

5. **Split the guest exports off `lib/ui_catalog.dart` before tagging
   0.5.2.** v0.5.1 exported four names; the working tree exports ~25,
   including host-driven plumbing (`CatalogParameters`, `GuestInspector`, the
   `Inspect*` types) that is public only because the generated entrypoint
   imports the library like any consumer. 0.5.2 is untagged, so none of it is
   a semver commitment yet — the only irreversible-if-missed item in this
   review. Move the machinery to a `ui_catalog_guest.dart` library documented
   "for generated code", point the two generators
   (`entrypoint_generator.dart`, `catalog_wrapper.dart`) at it, keep
   `ui_catalog.dart` to `Demo`, `FormFactor`, `Figma`, `UICatalog*`.

6. **Deletion pass.** All verified dead:
   - `app/lib/src/ui_catalog/service/` — the "UDP transport to preserve" is
     five empty stubs, and its generated entrypoint imports
     `package:flutterware/src/ui_book/`, a path that has not existed in years.
     Goes with `Project.uiCatalog` and the legacy `UICatalogScreen`.
   - `lib/src/ui_catalog/protocol/` — one field-less `built_value` class,
     imported only by the dead service. The feared "protocol defined twice" is
     a fossil, not a fork.
   - `lib/src/ui_catalog/app_integration.dart`, `widget_container.dart`, and
     the second `WidgetContainer` stub inside `ui_catalog.dart` — zero
     importers.
   - The caller-less `HeadlessCatalog` methods (`tree()`, `hitTest()`,
     `errors()`, `logs()`, `captureAll()`, ~200 lines) left behind by the S6
     collapse onto `observe()`/`auditAll()`.
   - `app/lib/main_shell_dev.dart` — self-labelled "delete once M1 lands"; it
     landed.
   - Stale doc fixes in passing: `catalog_entry.dart` ("discovery does not
     exist yet"), `devices.dart` (describes the retired copied-list design),
     CLAUDE.md (`main_dev.dart` target; pre-shell test-runner described as
     current).

## M4's first commits, not standalone rework

These want the second consumer's perspective, so they open M4 rather than
preceding it:

- **Extract the guest launcher/session into `embedder/`.** The spawn dance
  (bind → spawn host → regex-scrape the VM-service URI → race accept vs exit →
  wire capture → teardown) is hand-rolled four times (`embedded_engine.dart`,
  `headless_catalog.dart`, two spikes), and `_GuestSession` has already been
  copy-pasted once (`inspect_spike.dart` says so). M4 would be the fifth. Fix 4
  above lands inside whatever this extraction produces.
- **host.c gets its platform task runner.** The one item S1 explicitly queued
  for "before scenario authoring starts in anger", still outstanding —
  `FlutterProjectArgs` registers no platform message handling, so every
  unfaked platform call is a silent hang instead of an immediate
  `MissingPluginException`. Catalog demos are curated; scenario targets are
  real screens calling `SystemChrome`/`Clipboard`/path_provider. The only
  genuine native work on this list, with a known design. It is also the
  prerequisite for ever answering `flutter/textinput` — `enterText` remains
  S1's largest open API gap.
- **Thread an event sink through `PluginCore.invoke`; add
  `JobLog`/`JobProgress`.** `JobEvent`'s own comment says these belong "the
  day something streams" — M4 is that day, and retrofitting after runner
  action signatures exist means rewriting every one plus both renderers plus
  the GUI's panel-direct-to-core workarounds. The in-process sink API is the
  cheap-now part; the wire format stays unbuilt per `job.dart`'s warning.
  `busyStatusFor` (`ui_catalog_core.dart:147`) is this hook's ad-hoc first
  occurrence; the runner is the second, which is when it moves onto the
  contract.
- **Extract the generated-`main()` bootstrap.** The ~60 order-sensitive lines
  (zone install, extension registration, `resetFor` fan-out) live as a string
  template in `entrypoint_generator.dart:141-201`; a scenario generator would
  fork them and drift. One published `installGuestRuntime(...)` plus a
  registry that fans out `resetFor`. Add a version echo to the report
  envelopes while in there — skew currently degrades silently, and the
  `setParameter`→`setParameters` silent-swallow week already demonstrated the
  failure mode.

## Three decisions at M4 kickoff — paper before code

> **Settled the same day, elsewhere.** `2026-07-30-scenarios-design.md`
> (written in a parallel session; lands with the M4 work) resettles all
> three: M4 runs scenarios on FakeAsync in a direct-spawned `flutter_tester`,
> **not** in the embedder guest. So (1) resolves to a second daemon service —
> the parked `DaemonAddress` identity split is triggered; (2) resolves to
> in-process `toImage`, leaving `kMsgCapture` step-sync a catalog-only
> question; (3) input goes through the test binding in-process, so
> headless-guest input stays dropped. Consequence for the list above: the
> host.c platform task runner drops from M4-blocking to catalog hygiene; the
> `PluginCore.invoke` event sink stays load-bearing (the runner streams
> steps); the guest-launcher extraction stays right but serves the catalog
> rather than M4. The section is kept as written for the record.

1. **Is a scenario a catalog entry, or a second daemon service?** As entries,
   scenarios flow through discovery/entrypoint/select unchanged, and S3's
   fresh-prefix rule already applies. As a second service, the parked
   `DaemonAddress` identity split activates (it stays deferred exactly as
   `daemon_address.dart:27-45` says, *until* this decision says otherwise),
   and the daemon body wants parametrizing over (scanner, generator, entry
   type) rather than forking a 1000-line process manager.
2. **Which capture mechanism is the per-step one?** The productized
   `kMsgCapture` path is host-initiated and not step-synchronous — "the frame
   at step N" may already contain step N+1. The S1 spike captured in-guest
   (`layer.toImage()`, synchronous but re-rasterized, flagged by S1 as the
   thing to replace). Neither does both. Either a guest→host
   capture-at-step-barrier exchange, or accept in-guest `toImage` for M4 and
   keep IOSurface capture for the live view. Retrofitting step-sync onto
   `FrameCapture` after M4 builds on it is the expensive version.
3. **Input events for headless guests.** The embedder protocol already carries
   `PointerEventMessage`/`KeyEventMessage` (the live panel sends them); the
   headless session sends only resize/capture/shutdown, and the inspection
   panel spec dropped interaction deliberately ("dropped, not deferred"). M4's
   "drive it" reverses that: the extracted guest session learns to send input
   plus a settle rule. Plan it as new capability, not as plumbing.

## Noted, deliberately not in scope

- `Session.open` resolves the worktree by raw path equality where the shell
  canonicalizes — `fw` run from a symlinked cwd mints addresses the GUI cannot
  resolve. One line plus a round-trip test; fold into any session-touching
  change.
- `fw status --json` emits branch-or-path as `worktree`; the canonical
  identity is `Worktree.name`. `fw actions --json` lacks the result `shape`
  MCP publishes.
- `fw capture` is a third pipeline (env-var spawn, no `Session`, unreachable
  over MCP) — an honest landing of decision 5 until the viewer channel exists;
  fold it in then.
- `Demo.figma` is write-only; `skipInTests` from the entry-model spec was
  never added. Its consumer is the runner — decide its shape in M4's design.
- The standalone widget lags the panel (no axes on web, figma dormant); per
  the web-generator doc that is a per-feature decision, not drift to fix here.
- Every transport is unix-domain sockets while the launcher supports Windows;
  if Windows stays on the roadmap, a transport decision needs a line somewhere.
- Two GUI sessions on one project fight over the `LiveSession` handle
  (last-writer-wins, bounded cost — `--live` degrades to a fresh render).
  Noted in-file; fix if two-window use becomes normal.
- Coverage gaps to close with one gpu-tagged integration test when M4 touches
  them: `EmbeddedEngine`, `GuestVmService`, the runtime `kMsgCapture` path,
  and the select→reload→render loop itself (`compiler_daemon_test.dart:30`:
  "everything below stops at the kernel").

## Where this leaves the plan

Master-plan open question 2 (platform channels) is now scheduled rather than
open; open question 4's catalog costing stands; the memory note deferring the
daemon identity split stands *conditional on* kickoff decision 1. M4 starts on
a substrate that four hostile reads failed to find a structural fault in —
the remaining work is hygiene, and it is listed above.
