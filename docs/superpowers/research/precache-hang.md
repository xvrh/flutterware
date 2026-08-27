# Why does `precacheImage` on a `FileImage` hang the store frame harness?

## The question

`lib/src/store/frame_harness.dart` composes each store screenshot inside a
`flutter_tester`. It builds the providers a frame is handed, pumps the frame,
then precaches every `Image` in the tree inside `tester.runAsync` so the
pictures are present when it captures.

Today those providers are `MemoryImage`s, built by reading each file eagerly:

```dart
var loaded = <String, MemoryImage>{};
MemoryImage load(String path) => loaded.putIfAbsent(
  path,
  () => MemoryImage(File(path).readAsBytesSync()),
);
var shot = StoreShot(
  image: load(job.image),
  set: [for (var path in job.set) load(path)],   // <- every image of the set
  ...
);
```

`StoreShot.set` is every image of the set, so a frame can paint a neighbour —
a device body that crosses from one screenshot into the next. Most frames touch
two or three of them. But the list is built eagerly, so **every job reads every
file of its set**: 225 reads and roughly 450MB of file I/O for a fifteen-shot
set, ~1800 reads across a full eight-set export, mostly to produce providers
nothing ever decodes.

The obvious fix is to make them lazy, since `FileImage` defers its read until
something resolves it:

```dart
var loaded = <String, FileImage>{};
FileImage load(String path) =>
    loaded.putIfAbsent(path, () => FileImage(File(path)));
```

**That change hangs.** A narrowed export that takes ~16s ran past **ten
minutes** and was killed. Reverting to `MemoryImage` restored 15.7s, measured,
so the swap is the cause and nothing else in that commit was.

## What to find out

1. **Where does it actually stop?** Is the `await precacheImage(...)` never
   completing, or is the harness's outer wait (`live.run()`, the settle, the
   service extension) the thing that never returns?
2. **Is it `runAsync` + real file I/O?** `MemoryImage` only needs a *decode* to
   complete on the real event loop; `FileImage` needs a **read and** a decode.
   Does `File.readAsBytes()` inside `tester.runAsync` complete under
   `flutter_tester`'s binding, or does something about the fake clock or the
   test binding's task queue stall it?
3. **Is it the loop rather than the provider?** The precache is
   `for (element in find.byType(Image).evaluate()) await precacheImage(...)` —
   several awaits inside one `runAsync`. Does the second one hang where the
   first completed? Does hoisting them into one `Future.wait` change anything?
4. **Does it hang per job or once?** If the first job composes and the second
   never starts, the fault is in teardown or in the image cache holding a live
   stream, not in the read.
5. **Does `precacheImage` need the element to still be mounted?** It takes a
   `BuildContext`; the loop passes each `Image`'s own element. Is any of them
   deactivated by the time its turn comes?

## How to reproduce

From this worktree (branch `claude/store-screenshot-extraction-5f5028`):

```bash
cd app && fvm dart run tool/drive_spike/step.dart store/export '{"listing":"play","class":"phone","locale":"en"}'
```

~16s as it stands. Apply the `FileImage` swap above in
`lib/src/store/frame_harness.dart` and it does not return.

The composed set is Play's phone, whose frame is
`examples/example/lib/store_frame.dart` — a panorama that paints three devices
per shot, so it exercises the multi-image precache. `examples/example`'s
scenarios must have been captured; the export does that itself.

For a faster loop than a whole export, `app/lib/src/store/frame_runner.dart`
drives `StoreFrameRunner.compose(jobs, manifestPath:)` directly.

## What a good answer looks like

Either:

- **the lazy version, working** — `StoreShot.set` costing nothing until a frame
  paints it, with the export still at ~16s and the output byte-identical
  (`find … -name '*.png' | sort | xargs shasum | shasum` before and after); or
- **a written reason it cannot be** — what in the tester binding makes a
  deferred read unusable here — so the eager read stays with a comment saying
  why, and the cost is accepted knowingly rather than by accident.

A third outcome is fine too: a different way to make the set lazy that is not
`FileImage` — a custom `ImageProvider` that reads in `loadImage`, or leaving
the list eager but only materialising the neighbours a frame asks for.

## Notes

- The harness's own comment explains why the precache exists at all: a decode
  happens on the real event loop, which fake time never runs, so without the
  `runAsync` turn the frame is captured with the app's pixels missing and the
  picture is a composition around a hole.
- The precache deliberately asks the *tree* what was placed rather than the
  job, so a frame that ignores `StoreShot.set` pays nothing for it. Keep that
  property.
- `StoreShot.set` is published API (`package:flutterware/store.dart`), so its
  type can gain laziness but should not change shape.
- Context: `docs/superpowers/specs/2026-08-26-store-screenshots-design.md`,
  §10j, and the second commit on this branch.
