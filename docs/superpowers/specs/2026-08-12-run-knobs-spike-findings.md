# E1: the wrapper recompiles on hot restart — 262ms against 29.6s

**Date:** 2026-08-12
**Gates:** `2026-08-12-run-knobs-design.md` § Part A. **E1 holds.** Part A is
buildable as designed; two findings change details, and one of them is a real
cost that was not in the design.

## What was asked

Does `flutter run` hot-restart pick up a rewritten
`.dart_tool/flutterware/run/*_guest.dart`? The whole "hot restart instead of
rebuild" claim rests on it, and it was unverified.

## Method

`examples/example`, `lib/main.dart`, macOS, through the run plugin. The example
already reads `FW_MARKER` and prints it on the home page — a define that exists
to prove which build is on the device — so the baseline came free.

A temporary `String fwSpikeKnob` was added next to it and shown on the same
screen. The generated wrapper was then hand-edited to the shape Part A proposes
and the value read back off the screen with `act {verb: observe}`:

```dart
const knobs = {'SERVER_URL': 'v1'};

void main(List<String> args) {
  entry.fwSpikeKnob = knobs['SERVER_URL']!;
  Object? entryMain = entry.main;
  …
}
```

A **`const` map literal** on purpose, not a bare string: const values are the
part of hot restart worth doubting, and the design passes exactly this.

Reverted after; nothing from the spike is in the tree.

## Result

| step | what changed | how | ms | on screen |
|---|---|---|---|---|
| launch | `FW_MARKER=define-v1` | `run/launch` | — | `define-v1` / `<unseeded>` |
| 1 | wrapper → `v1` | `run/restart` | **262** | `SPIKE_KNOB: v1` |
| 2 | wrapper → `v2` | `run/restart` | **343** | `SPIKE_KNOB: v2` |
| 3 | wrapper → `v3` | `run/reload` | 154 | **`v2` — unchanged** |
| 4 | (same edit) | `run/restart` | **237** | `SPIKE_KNOB: v3` |
| 5 | `FW_MARKER=define-v2` | stop + `run/launch` | **29,600** | `define-v2` / `<unseeded>` |

Three restarts, three times the new value. The rewritten wrapper is recompiled
and re-run, `const` map and all.

**262ms against 29.6s is 113x**, and the baseline is generous to the define: row
5 is a *warm* relaunch of an already-built app on the host platform, measured
around the `run/launch` call from outside. A phone, a cold build, or a first
launch is worse. The client's "100x" was not an exaggeration.

## Finding 1 — reload is not enough, and that costs app state

Row 3 is the one to keep. Hot reload recompiles the wrapper and changes nothing,
because a boot-seeded value is written by `main` and reload does not re-run
`main`. Only restart moves it.

That was implicit in the design and its consequence was not: **a restart loses
the app's state**. You are back at the first screen with an empty cart. For a
value read during startup wiring there is no way around it — the wiring only
happens in `main` — but it means the two delivery paths are not
interchangeable, and the design's split earns its keep:

- read in `build` → live `preset` push, **no restart, state intact**
- read before `runApp` → wrapper seed, **restart, state lost**

So `Knob.of(context)` is not merely the nicer API, it is the cheaper loop, and
the cockpit should say which one a given knob is paying for. A knob read both
ways pays the restart, because the pre-`runApp` read is the one that has to be
right.

## Finding 2 — launch rewrites the wrapper, so the knob write has an owner

Row 5 confirmed it out loud: the relaunch regenerated `main_guest.dart` and the
hand-edit was gone, exactly as `writeGuestEntrypoint`'s doc comment promises.

Two consequences for the build:

- The wished values must be written by **both** paths — `launch.dart:99` at
  launch, and whatever handles a knob change between launches. One function
  producing the file's content, called by both, or they drift.
- A knob write and a launch racing on the same path is possible. Rare and
  cheap to avoid, but it should be avoided deliberately rather than noticed
  later.

## What this does not answer

- ~~**Only macOS.**~~ Measured 2026-08-12 as part of E2, in the design doc: the
  iOS simulator restarts in **263ms** (desktop speed), the Android emulator in
  **3067ms** against a **38.6s** stop-and-relaunch. The mechanism holds on both;
  the *ratio* does not travel — 113x on macOS, 12.6x on Android. Web unmeasured.
- **Nothing about `runGuest(knobs:)`.** The spike wrote the app's variable
  directly, to keep the question to "does the wrapper recompile". Routing the
  same value through the override map is ordinary work with no doubt in it.
