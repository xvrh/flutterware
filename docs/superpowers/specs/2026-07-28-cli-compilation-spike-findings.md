# CLI compilation and startup — findings

**Date:** 2026-07-28
**Brief:** `2026-07-28-cli-compilation-spike-brief.md`
**Measured on:** macOS arm64, Flutter 3.47.0-0.1.pre via fvm, worktree off
`xha/overhaulrework` @ `44d23c3`.

Answer in one line: **`fw status` goes from ~500ms to ~100ms, and almost none of
the saving is where the brief expected it.** Two of the seven spikes are dead,
one premise was stale, and the largest number in the pipeline turned out to be
an order of magnitude smaller than assumed.

## The headline numbers

| | before | after | what did it |
|---|---|---|---|
| `fw status` | 590–660ms | **100–110ms** | AOT via `dart build cli` + a cached manifest kernel |
| `dart run bin/fw.dart status` | 5.1s | — | never do this; see below |
| GUI build, cold | assumed "minutes" | **23.2s** | nothing — the assumption was wrong |

## Where the time was

`fw status` decomposed, and it is almost entirely one subprocess:

| | |
|---|---|
| `dart run tool/flutterware.dart` (what `Session.open` does) | **510–590ms** |
| the same file, precompiled to kernel | **70–80ms** |
| a `void main(){}` kernel — the bare VM floor | 70ms |

So the manifest emitter's *own* work is unmeasurable against VM startup, and
**~450ms of a 500ms command is `dart run`'s resolution and JIT of a 29-line
file.** `ManifestLoader`'s doc comment says "it costs ~0.5s" — correct, and the
cost is not what the sentence implies.

Layered on top, the process itself:

| how `fw` is run | `status` |
|---|---|
| `dart run bin/fw.dart` | 5.07–5.95s |
| `dart <kernel>.dill` | 590–660ms |
| `dart build cli` AOT bundle | 480–590ms |
| AOT + cached manifest kernel | **100–110ms** |

Two things fall out of that table. The gap between kernel and AOT is ~70ms — the
VM start — so **the choice of compilation strategy was worth 70ms and the
subprocess was worth 450ms.** And `dart run <file>` at 5s is not a warm-up
artifact: it never caches, because only `dart run <package>:<script>` gets a
snapshot. Anything on a hot path must be a `.dill` or an AOT bundle.

**Aside worth its own line: `fvm dart` costs ~170ms per invocation** (210ms
against 40ms for the SDK's `dart` directly). Larger than everything the AOT
build saves. Whatever resolves the SDK should resolve it once and exec the real
binary.

## The stale premise: `dart compile exe` has a successor, and it works

Master plan decision 9 and the GUI/CLI architecture doc both record `dart
compile exe` as broken here, which is still true and still fails the same way:

```
'dart compile' does not support build hooks, use 'dart build' instead.
Packages with build hooks: objective_c.
```

But the command the error names **works**, and nothing in the lineage records
trying it:

```
$ dart build cli -t bin/fw.dart -o /tmp/fwcli
Running build hooks... Running link hooks...
Copying 1 build assets: package:objective_c/objective_c.dylib
Generated: /tmp/fwcli/bundle/bin/fw          # 3.0s
```

It emits a bundle — `bundle/bin/fw` plus `bundle/lib/objective_c.dylib` — rather
than a single file, which is the whole reason `compile exe` refuses: it has
nowhere to put the dylib. A directory is a mildly worse distribution unit than
one binary and it is not a blocker.

**Consequences for decisions already written down.** Decision 9's compile
guardrail — "if the CLI's closure acquires `package:flutter`, the compile fails"
— can be re-armed, against `dart build cli` instead of `dart compile exe`. The
purity walker test stays regardless; it fires in milliseconds and names the
import chain, which a linker error does not.

The kernel choice in `bin/flutterware.dart` is not thereby wrong. Kernel needs
no build step at distribution time and starts 70ms slower. That is the correct
trade for the bootstrapper and the wrong one for a command typed all day.

## S2 and S3 are dead, for opposite reasons

**S3 — build mode. Dead: release is not the expensive part.**

| | cold | no-op rebuild |
|---|---|---|
| `--release` | 23.2s | **33.8s** |
| `--debug` | 21.1s | 9.8s |

Debug buys ~2s cold. Not worth a second mode, a second output path, or the
"which GUI am I running" question. (The debug cold figure ran after a release
build, so it had a warm `build/` and is generous, not pessimistic — which only
strengthens the conclusion.)

**S2 — rebuild trigger. Its kill criterion said stop if an unchanged
`flutter build` no-ops cheaply. It does the opposite: a release no-op costs
33.8s, ~10s more than building from nothing.** So the kill criterion does not
fire, but it does invert the reasoning. The current design — the child CLI
builds only when the binary is *absent*, and the bootstrapper deletes
`build/<os>` when the source stamp changes — is accidentally right: it never
calls `flutter build` to be told there is nothing to do. What remains true is
the original complaint. A one-line edit to `app/lib/src/session/cli.dart`, which
the GUI's window never renders, still deletes the build directory and buys a
23-second rebuild. Splitting the stamp is worth ~23s per CLI-only edit to a
flutterware developer and nothing at all to anyone else.

## S4 is much smaller than it looked

The hypothesis in the brief holds. `~/.flutterware/<sha1>` hashes the
**flutterware package root**, not the user's project:

```
642c18702829a04c7447546ee81c8f5ee905521    ~/.pub-cache/hosted/pub.dev/flutterware-0.5.1/
fa90a7f7d39aad16411577ca95bdaaaaeaf4bdca   ~/projects/flutterware/
```

For an external user that path is `~/.pub-cache/hosted/pub.dev/flutterware-<v>/`
— already per-version, already shared across every project on the machine. There
is no per-project fragmentation to fix. What is left of S4 is only "what should
a path-dependency developer get", which is S6.

**A real bug found while checking it.** `_hash` is

```dart
sha1.convert(...).bytes.map((b) => b.toRadixString(16)).join('')
```

with no zero-padding, so a byte below `0x10` renders as one hex digit and the
output is variable-length — 39, 40 or 41 characters, as the two hashes above
show. It is also genuinely ambiguous: bytes `[0x0a, 0xbc]` and `[0xab, 0x0c]`
both render `abc`. A directory collision between two package roots is
astronomically unlikely and the fix is `.toRadixString(16).padLeft(2, '0')`.

## The stamp costs as much as the whole command should

`_sourceStamp` walks the package with `listFilesInDirectory` (which honours
`.gitignore`) and stats every file, on **every invocation**:

```
files=1280  stamp=138ms
files=1280  stamp=109ms
files=1280  stamp=95ms
```

~100ms, against the 100ms that `fw status` costs in total once the manifest is
cached. It was added to close the never-invalidates `TODO(xha)` and it does; the
point is only that it is now a co-equal term rather than a rounding error, and
it is paid to answer a question that is almost always "no".

For scale, copying the tree it protects is **120ms** for 13MB — so the check
costs about as much as the work it avoids. A cheaper stamp (directory mtimes, or
a git-aware check for the dev case) is the obvious follow-up, but see S6: for
the audience that actually changes these files, the right answer is not to copy
at all.

## S5 — the floor, and what it is made of

**~100ms, and it is reachable with two changes that do not need each other.**

1. `dart build cli` instead of a kernel snapshot: −70ms.
2. Cache a kernel of `tool/flutterware.dart`, keyed on its mtime and
   `package_config.json`'s: **−450ms**.

The second was verified end-to-end with a throwaway 30-line patch to
`ManifestLoader` (reverted): first run 580ms including the one-off
`dart compile kernel`, then a flat 250ms on the kernel-snapshot `fw`, and
100–110ms on the AOT one. Output identical.

**This does not violate decision 4.** That decision forbids a resident compiler,
a spawn-then-swap, and a long-lived per-worktree config process. A `.dill` next
to `package_config.json` is none of those — it is the same plain `dart run`
model with the compile step memoised on disk, and it is re-derived whenever
either input's mtime moves.

## S7 is dead

A resident session would take 100ms to ~20ms. The 2026-07-27 findings paid the
full price of a long-lived daemon — version skew silently serving yesterday's
behaviour, address derivation, orphan sweeps, idle timeouts — and that price is
not worth 80ms. Revisit only if something arrives that is slow for a reason a
cache cannot fix.

## S6 — running in place, which is the real developer finding

Not measured as a variant, because building in the checkout is what the rest of
this spike did all afternoon: `flutter build macos --release` in `app/` works,
and the copy exists only so an *external* install has a writable tree that is
not the pub cache. A path-dependency checkout already is one.

The cost of the copy for a developer is not the 120ms. It is that
`~/.flutterware/<sha1>` is a different tree from the one being edited, so:

- the stamp must walk 1280 files on every run to notice edits;
- any edit deletes `build/<os>` and buys 23s;
- and, before the stamp landed, edits did not propagate at all — which is why
  `main_dev.dart` exists and why **the CLI is developed by a loop that bypasses
  the CLI.**

Skipping the copy when the package root is not inside the pub cache removes all
three at once. That is a condition on one `if`, not a mechanism.

## What to do, in order of value per line changed

1. **Cache the manifest kernel.** −450ms, ~30 lines, no architectural
   commitment. Everything else on this list is smaller.
2. **Run in place when flutterware is a path dependency.** Removes the stamp
   walk, the 23s rebuild-on-any-edit, and the reason `main_dev.dart` is the
   only sane dev loop.
3. **`dart build cli`** for anything typed at a prompt. −70ms, and it re-arms
   decision 9's guardrail.
4. **Split the stamp** so a CLI-only edit does not rebuild the GUI. Worth 23s
   per edit, to us only.
5. **Pad the hash.** One line.

Not on the list, deliberately: a daemon, a build-mode switch, a shared per-version
artifact cache, and any change to how `fw` is reached. The last one was the
question this spike was meant to inform, and the answer it gives is that a
100ms `fw` does not need a walker to feel instant — so that decision can keep
waiting.

## Addendum — `dart install` as the distribution mechanism

Investigated after the spikes, on the question: can `fw` be a global tool
installed with `dart install`, which compiles the CLI and walks up itself?

**It exists in the pinned SDK** (Dart 3.13.0-282.1.beta) and **it is
`dart build cli` with a bookkeeping layer** — the same AOT bundle path that S1
found working. Which means it inherits the property that matters: build hooks
are supported, so `objective_c` is not an obstacle.

Measured, installing `flutterware_app` itself from a local path:

```
Running build hooks... Running link hooks...
Copying 1 build assets: package:objective_c/objective_c.dylib
Installed: ~/Library/Application Support/Dart/install/bin/fw     # 7.2s
```

| | |
|---|---|
| what lands on PATH | a **symlink** into `…/install/app-bundles/<pkg>/local/bundle/bin/<exe>` |
| so the dylib problem is | solved by construction — the bundle stays intact and the symlink points inside it |
| startup | AOT: **0.00–0.01s** for a trivial tool |
| `fw status`, installed, warm | **0.46s** — same as a hand-built bundle, so nothing is lost in the wrapping |
| from a subdirectory | works; resolves that subdirectory's own `tool/flutterware.dart` |
| `dart uninstall <pkg>` | exists, and removes bundles as well as symlinks |

Two mechanical notes. It installs into `~/Library/Application Support/Dart/
install/bin`, which is **not on `PATH`** — it prints the `export` line to add.
And despite the help text promising it will fall back to `bin/*.dart`, it
refused `flutterware_app` with *"The pubspec.yaml contained no executables
section"* until one was added; a workspace member may be why.

### The blocker is SDK discovery, and it is specific

`FlutterSdkPath.findSdks()` tries three things in order:

1. `FLUTTER_HOME`;
2. **walk up from `Platform.resolvedExecutable`** — with its own comment
   explaining that `fvm dart bin/fw.dart` resolves inside the SDK, so the
   Flutter root is three levels up;
3. `.fvm/flutter_sdk`, under a directory found by walking up for a
   **`flutter_version`** file.

A globally installed AOT binary **destroys (2)** — `resolvedExecutable` is the
installed `fw`, which is inside no SDK — and **(3) keys on the marker that was
just declared moot.** The only reason the experiment above worked is that this
repo still carries a legacy `flutter_version` at its root. In an external
project pinning with `.fvmrc`, or with no marker at all, a global `fw` finds no
Flutter SDK and cannot open a session.

This is not an argument against going global. It is the bill for it: **today's
CLI knows which SDK to use because of how it was launched, and a global binary
has no launcher to inherit from.** Discovery has to become explicit — walk up
for `.fvm/flutter_sdk`, then `.fvmrc`, then `which flutter` — and it has to be
written before a global `fw` is useful anywhere but here.

### Which `fw` is it — the whole CLI, or a walker?

The two shapes are genuinely different, and the request named the second:

**A — install the whole CLI globally.** One binary, 7s to install, 0.46s to run
(≈100ms with the manifest cache). The cost is that the plugin cores are compiled
*into* it, so the machine has one flutterware version while each project pins
its own in `pubspec.yaml`. The manifest crossing between them becomes a wire
contract that must survive version skew — a project's `tool/flutterware.dart`
compiled against 0.5 emitting to a global `fw` at 0.6.

**B — install a thin walker globally**, which finds the project, resolves its
SDK, ensures that project's pinned CLI is built, and `exec`s it. Per-project
pinning survives untouched, and it is the layer the 2026-05 architecture called
the walker — minus the bash and minus the SDK bootstrapper.

B has a property worth the extra layer: **the walker would be a new pure-Dart
package with no Flutter dependency**, so it has no build hooks, installs in
under a second, starts in ~10ms, and can be published to pub.dev — which
`flutterware_app` cannot, being `publish_to: none`. Installing A from anywhere
but a local path means a git descriptor against a Flutter-dependent package.

The bootstrap constraint on both: `dart install` needs *a* `dart`, and resolving
`sdk: flutter` dependencies needs that `dart` to be **Flutter's**. A standalone
Dart SDK from dart.dev cannot install A at all. It could install B, because B
depends on no Flutter.

### What this does not settle

Nothing here says a global `fw` should exist yet. The findings above put a warm
`fw` at ~100ms, which is the number that made the walker question deferrable in
the first place. What the addendum changes is the *cost estimate*: the
mechanism is free and works today, and the price is one piece of real work —
explicit SDK discovery — which is owed regardless of whether `fw` ends up
global, because it is the same discovery a walker in any language would need.

## Lessons worth keeping

- **The error message named the fix and nobody ran it.** `dart compile exe`
  fails with "use `dart build` instead"; that sentence sat in two design
  documents as evidence of an unsolvable constraint for three days. It works and
  takes 3 seconds.
- **`dart run <file>` never caches.** 5.07s warm, every time, because only
  `dart run <package>:<script>` gets a snapshot. Every `dart run` on a hot path
  is a bug.
- **"Minutes" was 23 seconds.** The GUI build was the number everything else was
  being traded against, and it had never been measured — including in the
  paragraph of the brief that proposed spending a spike on it.
- **A no-op can cost more than the work.** `flutter build macos --release`
  against an up-to-date tree is 33.8s, 10s *more* than building from scratch.
  Never assume an incremental build is cheap because it has nothing to do.
- **A tool that knows things because of how it was launched cannot be
  installed.** SDK discovery works today by walking up from the `dart` that is
  running us. That is free, invisible, and the first thing to break the moment
  the binary stops being launched by a `dart` at all — which is the whole point
  of installing it.
