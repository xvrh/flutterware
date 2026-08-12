# Http-profile spike: the DevTools network data source, from the run's VM service

**Date:** 2026-08-12
**Question:** can the cockpit's Network tab be fed from `ext.dart.io.getHttpProfile`
— the data source behind DevTools' Network page — over the VM service connection
the run already holds? `2026-07-31-sl3-inspect-surface-findings.md` measured the
RPCs *responding*; this spike runs the full loop a tracker would run: enable,
generate traffic, poll with a cursor, fetch bodies by id, survive a hot restart.
**Answer: yes, and the loop's semantics are exactly the feed shape the cockpit
already speaks — poll a list, upsert by id, fetch detail lazily.**

Measured against `examples/example` `lib/network_spike.dart` (a self-serving
traffic generator: in-app loopback `HttpServer`, requests fired through both
`dart:io` `HttpClient` and `package:http`) on macOS and the iPhone 16 Pro Max
simulator (iOS 18.1). Flutter 3.47.0-0.1.pre, the `.fvmrc` pin. Instrument:
`app/tool/http_profile_spike.dart`, run per subcommand against the run handle's
`vmService` URI. Both platforms behaved identically; latencies below are macOS,
the sim was the same to within noise.

## What is there

| step | call | measured |
|---|---|---|
| enable | `ext.dart.io.httpEnableTimelineLogging {enabled: true}` | 3ms |
| list | `ext.dart.io.getHttpProfile` | 5 requests → 7.2 KB raw, 4–47ms |
| list, incremental | same, `updatedSince: <last timestamp>` | 65 bytes when nothing changed |
| detail | `ext.dart.io.getHttpProfileRequest {id}` | 1.5–1.7 KB raw, 6–66ms |
| clear | `ext.dart.io.clearHttpProfile` | 2ms |

The detail is complete: request and response headers, both bodies byte-exact
(the JSON POST came back 28 b up / 37 b down, verbatim), and a per-request
event list — `Connection established`, `Request sent`, `Waiting (TTFB)`,
`Content Download` — with microsecond timestamps. That event list *is* the
waterfall; the 2-second `/slow` handler showed up as a 2.019 s gap between
`Request sent` and `Waiting (TTFB)`.

`package:vm_service` ships all of this typed (`DartIOExtension`,
`HttpProfile`, `HttpProfileRequest`) — no hand-rolled JSON. One trap in the
typed model: `HttpProfileRequestRef.events` lives on the ref, not on
`request`.

## The cursor is an upsert stream

`updatedSince` returns every request *touched* since the timestamp, not every
request *started*:

- An in-flight request appears immediately (response still null) — the 8 s
  `/slow` showed up on the next 500 ms poll tick as `IN FLIGHT`.
- On completion the **same id is delivered again**, response filled in.
- An unqualified first poll replays everything since enable — a Network tab
  opened late still gets history, the same replay-on-attach property the
  server feed has.

So the tracker keys on request id and upserts — the notifications-panel lesson
(`2026-08-11-devbar-run-bridge-design.md` step 7, "key on identity, not on
position") applies before any code is written, not after a bug.

## Capture must be armed in the entry point

`HttpClient.enableTimelineLogging` defaults to **false**, and the profile
records nothing retroactively: the spike app's startup request was absent on
first poll, unrecoverable. With `HttpClient.enableTimelineLogging = true` as
the first line of `main`, the startup request is captured on both platforms
with zero host involvement — that one line is the run-guest change, the whole
of it.

Enabling over the wire works (3 ms) and is the right fallback for a guest-less
run (`flutter run` by hand, then attach) — it just misses whatever fired
before the host connected.

**The web constraint:** `lib/src/drive/run_guest.dart` is deliberately
`dart:io`-free — the inspector split (`2026-08-11-devbar-run-bridge-design.md`
step 1) exists so guests compile to JavaScript, and `run/launch` offers
Chrome. The arming line therefore goes behind a conditional import
(`if (dart.library.io)`), a stub on web. There is no web capture either way:
no `dart:io`, no profile.

## Hot restart resets everything except the arming

After `hotRestart`: the profile is **wiped**, the isolate id **changes**, and
the in-app arming line re-runs with `main` — so the startup request of the
*new* session is captured too. The tracker treats a restart as a fresh
session: re-resolve the isolate, drop the cursor, keep the old rows only if
the tab wants cross-restart history (the journal precedent says it does not —
Steps also starts fresh).

## Coverage, confirmed and not

- **Confirmed:** `dart:io` `HttpClient` directly, and `package:http` on the VM
  (its `IOClient` rides `HttpClient` — the spike's `package:http` request is
  indistinguishable in the profile). dio's default adapter is the same ride;
  not separately spiked, mechanically identical.
- **Reports into the same profile, untested:** `cupertino_http` /
  `cronet_http` via `package:http_profile`.
- **Not covered by design:** web (no `dart:io`), release/profile builds,
  websockets and gRPC (socket profile territory — `getSocketProfile` responds
  but records only after its own separate enable; deferred).

## Memory is the VM's, and it is unbounded

Profile data — bodies included — accrues in the app's heap until
`clearHttpProfile` or restart. The cockpit inherits the motion-capture
reasoning (`2026-08-11-scenario-motion-capture-findings.md`): the *host* keeps
a bounded copy and the tracker calls clear on a policy, or a long-running app
with chatty network grows without limit. Detail bodies are fetched lazily by
id, so the host bound is on what somebody looked at plus the list itself.

## Apparatus notes, for whoever reruns this

- `dart run tool/http_profile_spike.dart` costs ~8 s per invocation in this
  workspace (build hooks), which is why the `watch` subcommand exists — the
  in-process 500 ms poll loop is both the in-flight instrument and a working
  prototype of the tracker.
- `lib/network_spike.dart` stays as a run entry point (`Network spike` in
  `tool/flutterware.dart`): a network feature needs a traffic generator the
  way the server feature needs `example_server.dart`. Its `main` currently
  arms the profiler in-app; **remove that line when the run guest takes over
  the job**, or the guest change cannot be verified against it.

## Consequences for the build (tasks 2–4)

1. `RunNetworkTracker` mirrors `TrackedServer`: id-keyed upsert from a
   `updatedSince` poll, lazy detail cache, bounded bodies, restart = new
   session. Poll only while something is watching; one-shot with a cursor for
   `fw`/MCP, the `_withPanels` pattern.
2. Duration comes from the event list / response end — `HttpProfileRequest`'s
   own `endTime` is the *request phase* end (the 2 s `/slow` read "18ms" by
   `endTime - startTime`).
3. The guest arming line goes behind `if (dart.library.io)`.
4. The Network tab is a native cockpit tab (layer 1, every debug run), not a
   devbar-plugin tab — `run_address.dart`'s reserved `Network` name gets its
   tenant, and `log_network`'s descriptor-mode conversion is off the critical
   path.
