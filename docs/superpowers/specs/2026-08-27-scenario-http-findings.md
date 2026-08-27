# Scenarios and real HTTP — what is possible, and what is a good idea

*Measured 2026-08-27 on this machine, Flutter 3.48.0-0.2.pre, `fvm flutter test`
against the root package. Every number below comes from a throwaway probe file
under `test/scenarios/`; none of it is committed, and none of the tree changed.*

A consumer migrating a real suite reports that a scenario cannot make an http
request — an `Image.network` comes back blank. The same consumer solved this
twice in the system before flutterware: first by pre-downloading every image
into a committed folder, then by simply letting the test hit the network and
pumping real time until it arrived. The second was, in their words, much much
easier.

This is what actually blocks it, what it would take to unblock it, and which of
the two roads is worth taking.

## Three things stand between a scenario and a socket, not one

**1. `flutter_test` mocks `HttpClient` globally.** `TestWidgetsFlutterBinding`
calls `setupHttpOverrides()`, which sets `HttpOverrides.global` to a mock
answering **400** to everything, and printing a warning once. Nothing reaches
the network: an `Image.network` against a local server produced **zero** hits.
`package:http` is caught by the same net — its `IOClient` is `HttpClient()`
underneath — and so is a client the app builds for itself at boot.

The override is a plain static setter. Clearing it, or replacing it, is one
line, and everything downstream — `Image.network`, `package:http`, an
app-owned `HttpClient` — reaches the network immediately. Measured: 200, 69
bytes, all three doors.

`NetworkImage` needs one extra line. Its client is
`static final _sharedHttpClient = HttpClient()`, created once for the life of
the *process* — so a body that runs after anything has touched it inherits a
mock that no later override can dislodge. `debugNetworkImageHttpClientProvider`
is the sanctioned door and it is checked on every load.

**2. Fake time does not deliver a real response.** A request started under fake
time reaches the server — the connection is real — but its future does not
complete: **5 seconds of fake time, nothing; one 300ms turn of the real loop,
done.** That is the shape `landRealWork` was already built for, and it needs no
new verb: `imageCache.pendingImageCount` is non-zero while a network image is
in flight, which is exactly the "announced work" `RealWorkBudget` waits on. A
localhost image lands **inside the step that mounts it**, in 59ms; ten of them
in one screen cost 63ms.

**3. TLS never completes, and this is the actual bug.** `dart:io` arms the
timers of a connection in the zone that opened it. An `ImageProvider` resolves
under fake time, so those are *fake* timers — and nothing in the settle or the
landing loop advances fake time, so they never fire.

Plain http survives this; a TLS handshake does not. Isolated:

| what | plain client | client whose `openUrl` runs in `Zone.root` |
|---|---|---|
| localhost, plain http, no redirect | 59ms | — |
| localhost, plain http, **302** | 156ms | 34ms |
| remote **https**, no redirect | **never lands** (2185ms, blank) | **239ms** |
| remote **https**, one redirect | **never lands** (3 steps, 3.2s, blank) | **376ms** |

Reproduced 3/3, byte-identical. Redirects are not the trigger; TLS is. So
"a scenario cannot do http" is more precisely **"a scenario cannot do https"**,
and it fails by hanging rather than by erroring — the step reports a blank
frame, `landed: false`, and nobody reads that.

## The mechanism, in full, and it is small

One `HttpOverrides` for the body, handing out one harness-owned client:

- **Every door funnels through it** — `HttpClient()` in app code,
  `package:http`, `Image.network` via `debugNetworkImageHttpClientProvider`.
  Verified with all three in one body; all three landed, and all three appeared
  in one log at one point in the code.
- **`openUrl` runs in `Zone.root`**, which puts the whole `dart:io` state
  machine on real timers. This is the line that makes https work at all, and it
  is also 4× faster on plain localhost (34ms against 156ms).
- **Only the harness closes it.** A client with a live keepalive connection
  holds a timer, and `flutter_test` asserts `!timersPending` at the end of every
  body — so an app that closes "its" client must not close the shared one, and
  the harness must close the shared one before the invariant check. Verified in
  both directions: unclosed fails the body, closed passes.

Two behaviours already fall out for free and are worth having whatever else is
decided:

- **Failures are already bounded.** An unreachable host errors in 31ms and the
  `errorBuilder` renders. A black-hole host does not hang the run: the step
  spends its `realWorkWait` allowance and reports `landed: false` after ~2.05s
  of wall clock. The existing budget is already a network timeout.
- **Every exchange has somewhere to go.** `AppEvent.request` exists,
  `AppChannel.network` is already coloured in the scenario events view, and
  `DevbarHttpClient` already does this shape for a running app. A funnel means a
  scenario's network shows up on the step for the price of one call.

## What it costs to just open the tap

The mechanism is a day's work. The question is whether a scenario should hit the
real network on every run, and the repo has already answered the same question
once, about the clock:

> Pinning is what makes "these two pictures differ" mean "the code changed".
> — `lib/src/clock.dart`

A live network breaks that property in exactly the way a wall clock does, and
worse: it is not merely different per run, it is absent on a plane, rate-limited
in CI, and slower than the entire rest of the suite. Concretely:

- `resetAnnouncedWork()` clears the image cache at the top of every body — by
  design, so that a body's picture depends on the body. So it is not N requests
  per suite, it is N per *scenario*. A 46-scenario suite with a dozen avatars on
  screen is ~550 round trips against a suite that currently costs 2.3s.
- A comparison across a branch would diff network weather.
- The step budget is per step and currently 1s; a healthy CDN lands in 239ms, so
  the default holds — but a cold API on a bad link would need it raised, and
  raising it globally makes every *non*-network step's failure slower to report.

None of that argues against the capability. It argues against the capability
being the *default*, and it is the same argument the pre-downloaded folder was
making — just paid by hand.

## The three shapes, and a recommendation

**A. Live.** Open the tap. Cheapest to build, honest about what the app does,
and the ergonomics the consumer liked. Costs determinism, offline, CI and speed.

**B. Record and replay.** The same funnel, plus a store on disk keyed by method
and URL. One run records; every run after replays, offline, in microseconds, and
byte-identically. This is the pre-downloaded folder with the hand-work taken
out: the author writes the scenario the way they would write A, runs it once,
and commits what came back. A miss under replay is a refusal naming the URL and
the command that would record it — not a blank frame.

**C. Declared fakes.** `s.http.get('/users', json: {…})`. Not a competitor:
it is the only way to *state* a 500, an empty list or a slow response, which no
recording can be asked to produce on demand. It is the surgical tool, and B is
the bulk one.

**Recommendation: B as the default, A as a stated per-run mode, C later.**
Which is `fw.clock`'s shape exactly — a project default in `tool/flutterware.dart`,
overridable for one run on the command line, and *stated* in the report either
way, because a run whose pictures came off a recording and a run whose pictures
came off the wire are not the same run and the report should say which.

Whatever is decided, **the silent hang is a bug on its own** and should be fixed
first: an https request from a scenario today neither succeeds nor fails, and
the step says nothing a human would read. Even keeping the mock, a refused or
unlanded request should reach the step as an event and the panel as a badge.

## Open questions for the design

1. **Where does the store live, and is it committed?** Committed is what makes a
   fresh clone reproducible, so probably yes — which puts a size discipline on
   it: dedupe by content hash, and expect images to be the bulk.
2. **Keyed per project or per scenario?** Per project dedupes the avatar forty
   scenarios share; per scenario makes a scenario portable. The shots/report
   split suggests a shared store with a per-scenario index.
3. **What is the match key?** Method + URL is the 90% case. A timestamp or a
   nonce in a query string needs a normaliser hook, and a POST needs the body in
   the key or explicitly out of it.
4. **Secrets.** A recording holds response bodies and request headers.
   `Authorization` and `Cookie` must never reach disk; the safe default is an
   allow-list, not a deny-list.
5. **Scope.** Websockets, gRPC and `cupertino_http`/`cronet_http` do not go
   through `HttpOverrides` and are out for v1. Say so out loud rather than
   letting a consumer discover it as another blank frame.

---

# The feature, as a developer meets it

*Built 2026-08-27: `off`, `live`, stubs, and the events. `record` and `replay`
are the next piece and are sketched at the end.*

A scenario's network has a **mode**, and it is said in the same places `shots`
is. That is the whole of the design; the rest is spelling.

## The modes

| mode | what a request does | offline | deterministic | speed |
|---|---|---|---|---|
| `ScenarioNetwork.off` | fails at once, **named on the step** | yes | yes | instant |
| `ScenarioNetwork.live` | goes out, and what comes back is today's | no | no | network |
| `replay` *(next)* | is served from the recording on disk | yes | yes | ~0.1ms |
| `record` *(next)* | goes out, and what came back is written | no | no | network |

`off` is the default and is what `flutter_test` already did, except that
`flutter_test` answered an empty 400 silently and **hung** on https. Now the
request fails immediately with a message naming itself, and the exchange is on
the step.

It does **not** fail the scenario. A decorative avatar is not a reason to throw
away a flow's other twelve assertions, and the alternative would turn every
existing suite with an `Image.network` on screen red on upgrade. The step says
so instead — and that is a real change from "a blank box and nothing else".

## Where you say it

**A folder**, in its `flutter_test_config.dart`, beside `shots` and `profile`:

```dart
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones, network: ScenarioNetwork.live);
```

**One run**, from the panel, the CLI or the MCP:

```sh
fw run scenarios run --scenario=checkout --network=live
```

```sh
# the bare `flutter test` lane, which reads no request and no manifest
FW_NETWORK=live flutter test
flutter test --dart-define=fw.network=live
```

**One scenario**, when it is the odd one out:

```dart
scenario('the real payment sandbox', network: ScenarioNetwork.live, (s) async {
  …
});
```

Precedence: the scenario's own, then the run's, then the folder's, then `off`.
The run beats the folder deliberately — a `--network=live` on one run is
somebody saying "not this time", which is the whole reason a run flag exists.

The run report carries every mode that actually ran (`"network": ["off",
"live"]`), and the panel puts a **live network** badge on a run that reached
out — the same argument that puts the clock origin beside it. A picture taken
with the network open and one taken with it shut are not the same evidence, and
the picture does not say which.

There is deliberately no `fw.network(...)` project slot yet. It would be a
project saying "we are an `off` project", which is the default, or "we are a
`live` project", which nobody should be. It arrives with `replay`, which is the
answer a project *would* want to state once.

## Stating an answer

A stub is a fact about *this* scenario — the empty inbox, the 503, the train —
and no reading of a real server can be asked to produce one on demand.

```dart
scenario('the inbox is empty', (s) async {
  s.network.get('/api/messages', json: []);
  await s.pumpWidget(const App());
  await s.screen('the empty state');
});

scenario('the phone is on a train', (s) async {
  s.network.any(throws: const SocketException('Network is unreachable'));
  await s.pumpWidget(const App());
  await s.screen('the offline banner');
});
```

The full set — matching a path, a whole url or a `RegExp`:

```dart
s.network.get(url, json: …);              // encodes, sets the content type
s.network.get(url, body: bytes, contentType: …);
s.network.get(url, status: 503);
s.network.get(url, throws: …);
s.network.post(url, json: …);             // and put / patch / delete
s.network.any(…);                         // everything no stub claimed
s.network.image(url, scenarioPlaceholderPng(width: 96, red: 0x4C));
```

Three rules, each of them a footgun that was designed out rather than
documented:

- **A stub always beats the mode.** A scenario under `live` can pin the one
  response it is about and let the other forty go out.
- **A path never matches by substring.** `'/api/me'` does not answer
  `/api/messages`. A stub that fires for a url nobody meant it to is exactly the
  failure this surface exists to prevent; a `RegExp` is how anything looser is
  said out loud.
- **`any()` is a slot, not a stub at the end of the list.** A catch-all
  competing on registration order would swallow every stub written after it,
  and a rule you have to remember the order for is a rule that gets got wrong.

Re-stating a url changes what it answers from there on, which is how "and now
the list has the new item in it" is written. A `split` resets the stubs at the
top of every branch, because each path states its own answers.

## What you see afterwards

Every exchange is an `AppEvent.request`, so it rides the step with no extra
call — the flow view's Events pane, `scenarios read`, and the same
`AppChannel.network` colour the devbar already uses. Measured on the example
suite:

```
GET https://example.com/ada.png → off      (refused — the network is off …)
GET https://example.com/ada.png → 200      (answered: stub)
GET https://example.com/ada.png → stub     (SocketException: Network is …)
```

And in the body, when the request *is* the assertion:

```dart
await s.tap('Place order');
expect(s.network.requests.last.url.path, '/api/orders');
expect(s.network.requests.last.status, 201);
```

## How it works, in three lines

One `HttpOverrides` installed for the length of the body, handing out one
harness-owned client:

1. **Every door funnels through it** — `HttpClient()` in app code,
   `package:http`, `dio`, and `Image.network` via
   `debugNetworkImageHttpClientProvider` (which is needed separately because
   `NetworkImage`'s client is a process-lifetime `static final`).
2. **`openUrl` runs in `Zone.root`.** This is the line that makes https work
   at all — see the findings above.
3. **Only the harness closes it.** `flutter_test` asserts no timer is pending
   at the end of a body and a live keepalive holds one, so the app closing
   "its" client is a no-op and the shared pool is closed before the invariants
   are checked.

A per-client setting the app makes — a proxy, a bad-certificate callback for a
self-signed dev API, a user agent, a connection timeout — reaches the shared
pool, last writer wins. That is the price of one pool and one thing to close,
and everything an app actually sets here is pool-shaped anyway.

Nothing new pumps: `landRealWork` already waits on `imageCache.pendingImageCount`,
so a `live` image lands inside the step that mounts it.

## Not covered

`HttpOverrides` catches `dart:io`. It does **not** catch `cupertino_http` /
`cronet_http` (platform channels, already unimplemented in a test binding),
websockets, or gRPC. Said out loud so it is not rediscovered as another blank
frame.

## What `record` and `replay` still need deciding

1. **Where does the store live, and is it committed?** Committed is what makes
   a fresh clone reproducible — which puts a size discipline on it: dedupe by
   content hash, and expect images to be the bulk.
2. **Keyed per project or per scenario?** Per project dedupes the avatar forty
   scenarios share; per scenario makes a scenario portable. The shots/report
   split suggests a shared store with a per-scenario index.
3. **What is the match key?** Method + url is the 90% case, and the stub
   matcher above already has the vocabulary. A nonce in a query string needs a
   normaliser; a POST needs the body in the key or explicitly out of it.
4. **Secrets.** A recording holds response bodies and request headers.
   `Authorization` and `Cookie` must never reach disk; the safe default is an
   allow-list, not a deny-list.
