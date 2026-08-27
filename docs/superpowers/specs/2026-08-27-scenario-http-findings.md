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

*All five are answered below, and the fourth is answered the other way round:
request headers are not written at all, and response headers are kept by
deny-list — because what an allow-list drops, it drops silently. See
**Recording, once**.*

---

# The feature, as a developer meets it

*Built 2026-08-27, all four modes.*

A scenario's network has a **mode**, and it is said in the same places `shots`
is. That is the whole of the design; the rest is spelling.

## The modes

| mode | what a request does | offline | deterministic | speed |
|---|---|---|---|---|
| `ScenarioNetwork.off` | fails at once, **named on the step** | yes | yes | instant |
| `ScenarioNetwork.replay` | is answered from the recording on disk | yes | yes | ~0.1ms |
| `ScenarioNetwork.record` | goes out, and what came back is written | no | no | network |
| `ScenarioNetwork.live` | goes out, and nothing is written | no | no | network |

`off` is the default and is what `flutter_test` already did, except that
`flutter_test` answered an empty 400 silently and **hung** on https. Now the
request fails immediately with a message naming itself, and the exchange is on
the step.

It does **not** fail the scenario. A decorative avatar is not a reason to throw
away a flow's other twelve assertions, and the alternative would turn every
existing suite with an `Image.network` on screen red on upgrade. The step says
so instead — which is the whole change from "a blank box and nothing else".

That takes a filter rather than good luck. An `Image.network` with no
`errorBuilder` has no error listener of its own, so the throw reaches
`FlutterError.reportError`, and in a test binding that is what turns a test
red; `_runScenario` drops a `ScenarioNetworkRefusal` at the top of its error
chain, which also keeps it out of the runner's caught-errors buffer. A stub's
own `throws:` is **not** filtered — an author who wrote
`throws: SocketException(...)` is injecting an error on purpose and wants it to
behave like one.

## Where you say it

**The project**, in `tool/flutterware.dart` — the slot `fw.clock` sits in:

```dart
fw.clock(DateTime(2026, 1, 1, 9, 41));
fw.network(ScenarioNetwork.replay);
```

**A folder**, in its `flutter_test_config.dart`, beside `shots` and `profile`:

```dart
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones, network: ScenarioNetwork.replay);
```

**One run**, from the panel, the CLI or the MCP:

```sh
fw run scenarios run --scenario=checkout --network=record
```

```sh
# the bare `flutter test` lane, which reads no request and no manifest
FW_NETWORK=replay flutter test
flutter test --dart-define=fw.network=replay
```

**One scenario**, when it is the odd one out:

```dart
scenario('nothing is recorded for this one', network: ScenarioNetwork.off,
    (s) async { … });
```

Precedence: the scenario's own, then the run's, then the folder's, then the
project's, then `off`. The run beats the folder deliberately — a
`--network=record` on one run is somebody saying "not this time", which is the
whole reason a run flag exists.

Two things follow from the manifest being a Dart file that has to be
*executed*: a bare `flutter test` reads no manifest, so a project that says
`fw.network(...)` still needs `FW_NETWORK=` in that lane. Exactly the
asymmetry `fw.clock`/`FW_CLOCK` already has, and the reason a folder is the
better altitude for "these ones talk to an API" — a folder config is read by
both lanes.

The run report carries every mode that actually ran (`"network": ["off",
"replay"]`), and the panel badges the run accordingly — **recording**,
**live network**, **replayed**, or nothing at all for `off`. Same argument that
puts the clock origin beside it: a picture taken with the network open, one
taken off a recording, and one taken with it shut are three different kinds of
evidence, and the picture does not say which.

## Recording, once

Write the scenario as though the network were simply there:

```dart
scenario('the profile', (s) async {
  await s.pumpWidget(const Profile());
  await s.screen('the profile');
});
```

Run it once with `--network=record`. What came back lands beside the scenarios
at `test/scenarios/network/`, two files per exchange:

```
get-api-example-com-v1-profile-bfe5e75c.json          ← what it was
get-api-example-com-v1-profile-bfe5e75c.body.json     ← what came back
get-cdn-example-com-avatars-ada-png-5481188e.json
get-cdn-example-com-avatars-ada-png-5481188e.body.png
```

```json
{
  "version": 1,
  "method": "GET",
  "url": "https://api.example.com/v1/profile",
  "status": 200,
  "contentType": "application/json; charset=utf-8",
  "bytes": 106,
  "body": "get-api-example-com-v1-profile-bfe5e75c.body.json",
  "recorded": "2026-08-27T09:41:00.000Z"
}
```

Commit it. Every run after that is offline, byte-identical and instant — and a
fresh clone reproduces the screenshots with no network at all.

Four decisions in that layout, each of them a failure designed out:

- **The body is a sibling file with the right extension**, never a string
  inside the metadata. A committed recording is read in a diff, and a 5KB JSON
  response escaped onto one line is a recording nobody reviews.
- **One file per exchange, and no index.** `flutter test` runs files
  concurrently in separate processes; a single index would be a
  read-modify-write race between them, and a recording that loses entries
  depending on how the runner scheduled the suite is not a recording.
- **The name is a slug plus a digest.** The slug is for the human reading
  `git status`; the digest is what makes it an identity.
- **No request headers, and response headers by deny-list.** A request's
  headers are not part of the key, so keeping them would write an
  `Authorization` into a committed file for nothing. A *response's* are kept
  except two groups: credentials (`Set-Cookie` and its neighbours) and the
  transfer's own description (`Content-Encoding`, `Content-Length`,
  `Transfer-Encoding`, the connection pair), which would describe bytes the
  store does not hold — what is written is the body after decoding.

  A deny-list, deliberately, and not the allow-list that sounds safer. What an
  allow-list drops it drops *silently*, and the first thing it drops is `Link`:
  a screen that paginates works under `live`, gets recorded, and quietly renders
  one page forever after, with the recording looking correct in the diff. A
  deny-list can only be wrong about a header nobody thought of, and it is wrong
  about it in a file somebody reads before committing — which is also the answer
  for a response *body* that carries a token.

`record` always goes out and never partly reads the store: "refresh what I
have" and "fill in what I am missing" would otherwise be the same command, and
the one you wanted is whichever you did not get. What it fetches it overwrites,
what it does not ask for it leaves — so one endpoint is refreshed by running
one scenario. And the caller is handed the bytes that were *written*, not the
ones off the wire, so a record run and every replay after it draw the same
picture. That is a test, not a hope.

## A miss is a refusal, not a blank frame

```
no recording for this request

The recording holds nothing for GET https://api.example.com/v3/messages?page=1.

It holds 2 requests for api.example.com:
  GET https://api.example.com/v1/profile
  GET https://api.example.com/v1/settings

Record it:
  fw run scenarios run --network=record

Answer it here:
  s.network.get('/v3/messages', json: {…});
```

The query string is part of the identity and nothing is normalised: a store
that quietly answered `?page=1` with what it recorded for `?page=2` would be
worse than no store at all, and a url carrying a nonce is better served by a
stub that says so than by a matcher guessing which parts of a url matter.

## Stating an answer

A stub is a fact about *this* scenario — the empty inbox, the 503, the train —
and no reading of a real server can be asked to produce one on demand.

```dart
s.network.get('/api/messages', json: []);
s.network.get('/api/messages', status: 503);
s.network.any(throws: const SocketException('Network is unreachable'));
s.network.image(url, scenarioPlaceholderPng(width: 96, red: 0x4C));
s.network.post('/api/orders', json: {'id': 7}, status: 201);
```

Three rules, each a footgun designed out rather than documented:

- **A stub always beats the mode** — including `replay`, so one scenario can
  pin the response it is about and let the rest come off the recording.
- **A path never matches by substring.** `'/api/me'` does not answer
  `/api/messages`; a `RegExp` is how anything looser is said out loud.
- **`any()` is a slot, not a stub at the end of the list.** A catch-all
  competing on registration order would swallow every stub written after it.

Re-stating a url changes what it answers from there on, which is how "and now
the list has the new item in it" is written. A `split` resets the stubs at the
top of every branch, because each path states its own answers.

## What you see afterwards

Every exchange is an `AppEvent.request`, so it rides the step with no extra
call — the flow view's Events pane, `scenarios read`, and the same
`AppChannel.network` colour the devbar already uses. Measured on the example:

```
GET https://api.example.com/v1/profile → 200    (answered: replay)
GET https://api.example.com/v1/profile → 503    (answered: stub)
GET https://api.example.com/v1/profile → SocketException: Network is …
GET https://api.example.com/v1/profile → refused — the network is off …
```

And in the body, when the request *is* the assertion:

```dart
expect(s.network.requests.last.url.path, '/api/orders');
expect(s.network.requests.last.status, 201);
```

## How it works, in three lines

One `HttpOverrides` installed for the length of the body, handing out one
harness-owned client:

1. **Every door funnels through it** — `HttpClient()` in app code,
   `package:http`, `dio`, and `Image.network` via
   `debugNetworkImageHttpClientProvider` (needed separately because
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

The shared client sets `autoUncompress = true`, unlike `NetworkImage`'s own,
which turns it off so `Content-Length` counts the bytes that arrive. What is
worth more here is that a body is always plain: a recording of gzipped bytes
replayed without the `Content-Encoding` that explained them is a body nothing
can decode.

Nothing new pumps: `landRealWork` already waits on
`imageCache.pendingImageCount`, so a `live` image lands inside the step that
mounts it.

## Not covered

`HttpOverrides` catches `dart:io`. It does **not** catch `cupertino_http` /
`cronet_http` (platform channels, already unimplemented in a test binding),
websockets, or gRPC. Said out loud so it is not rediscovered as another blank
frame.

Nor is a request whose url changes per run — a nonce, a timestamp, a cache
buster. `replay` refuses it every time, correctly and unhelpfully. A normaliser
hook is the obvious next thing and is deliberately not guessed at yet: the
shape it wants is a real consumer's real url, not an invented one.
