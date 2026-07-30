# Assets added mid-session: the rebundle that must not delete

**Date:** 2026-07-30
**Status:** Spike findings, measured end-to-end. Recommends wiring the
existing refresh path; not yet implemented.
**Spike:** the driver lived at `app/build/midsession_spike/spike.dart`
(gitignored build output); every number below is from running it against
`examples/example`.

## Today

`_ensureAssetBundle` runs once per daemon `_prepare`. Editing an existing
asset works live — the bundle entry is a symlink to the project's file — but
a **new** file in a declared directory, a new declaration, or a new font is
invisible until the daemon restarts. The workaround is exactly that restart:
seconds of cold prepare, plus every session's guest relaunching, to notice
one file.

## Findings, in the order they bit

**1. Rebuilding onto the live directory bricks every running guest.**
`AssetBundleBuilder.build` starts with delete-and-recreate. The engine holds
a file descriptor to the assets *directory* and opens every asset relative to
it, so after the recreate the guest cannot load anything — measured as
`Unable to load asset: "AssetManifest.bin"` from a fresh manifest read, on a
guest that kept rendering its already-loaded scene as if nothing were wrong.
The naive fix is strictly worse than the bug. Any mid-session rebundle must
**build beside and sync into the existing inode**: write the new manifests
over the old, add/remove payload symlinks, never touch the directory itself —
and never touch `kernel_blob.bin`, which the builder's delete would destroy
and which the sync never sees (builder output carries no kernel).

**2. An in-place rebundle costs 32ms** on `examples/example` (initial build
of the same bundle: ~75ms). Per-session assets dirs are top-level symlink
mirrors of the shared dir, so an in-place update flows through them with no
per-session work.

**3. The guest notices nothing until told.** The framework caches
`AssetManifest.bin` in `rootBundle`; a rebundled manifest sat unread and the
new key kept failing. This is not a defect to engineer around — it is the
hot-reload contract: `flutter_tools` sends `ext.flutter.evict` per synced
asset. For an *added* asset the manifest is the thing that changed, so:

```
ext.flutter.evict   value=AssetManifest.bin
ext.flutter.reassemble
```

**27ms** for both, and the added key then resolves, decodes and paints —
verified at every layer (fresh manifest read sees the key, `rootBundle.load`
returns the bytes, an `AssetImage` resolve delivers 48px, the capture shows
the pixels). An *edited* asset additionally wants `evict value=<key>` so its
decoded image drops out of the image cache; reassemble alone already clears
`imageCache`, so the minimal pair above covers both cases.

## Recommendation

Wire it to the daemon's existing `refresh()` — the rescan the reload button
and entry discovery already drive — rather than to a filesystem watcher:

- `_ensureAssetBundle` becomes build-beside-and-sync (finding 1), run on
  every `refresh()`; at 32ms it needs no fingerprint guard.
- After a sync that changed anything, each connected GUI session sends the
  evict + reassemble pair over the guest VM service it already holds.
  Headless guests need nothing: they are launched per capture and read the
  shared bundle fresh.
- A watcher stays out until someone misses it. `refresh()` is where "the
  project changed" already lands, and 59ms end-to-end means the button is
  effectively free.

Against the workaround: a daemon restart is seconds, kills guest state
(knobs, navigation, everything a reload preserves), and asks the user to know
*why* their image is missing. The refresh path is two orders of magnitude
cheaper and reuses machinery that exists.
