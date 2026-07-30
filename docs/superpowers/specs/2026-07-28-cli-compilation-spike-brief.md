# CLI compilation and startup — spike brief

**Date:** 2026-07-28
**Status:** Brief. Written before the spikes run, so they stay spikes.
**Parent:** `2026-07-25-overhaul-master-plan.md` (decisions 9, 10),
`2026-07-27-gui-cli-mcp-architecture.md` ("Next", item 1 — *the CLI story
proper*), `2026-07-27-compile-pipeline-performance-findings.md`.

## The question

*Everything between typing a command and something happening* — and only the
part that is **fixed cost**.

The marginal loop was measured on 2026-07-27 and is already fast: a cold catalog
compile is ~320ms, an entry switch is 6–16ms plus a ~100ms reload, a second
client attaches in 19ms. None of that is in scope. What is in scope is the
scaffolding around it: resolving, copying, compiling and building the tool
itself before any of that can run.

## Scope, set by the 2026-07-28 discussion

Three things were explicitly pulled out of the CLI story and are **not** spiked:

- **SDK management.** The user brings their own Flutter SDK. No `flutter_version`
  marker, no `.fvmrc` reading, no install. `tool/fw`'s installer was a prototype
  and stays one.
- **The walker.** Also a prototype. How `fw` is reached is deliberately left
  open until the numbers below say what it would be worth.
- **A downloadable GUI.** The GUI is built from source on the host. Simpler, and
  it avoids signing, notarization and a stapled ticket for a `.app` that arrives
  over the network.

What that leaves is one honest question: given the user's own SDK and a GUI
built from source, **how fast can this be, and where does the time actually
go.**

## Already landed — do not re-spike

Two of the obvious candidates are done on `xha/overhaulrework` and are baseline,
not experiments:

| | |
|---|---|
| **`dart compile kernel`, not `exe`** | `exe` refuses to run once anything in the resolution has a build hook (`objective_c` ← `path_provider_foundation`). Kernel does not link native assets ahead of time and is unaffected. |
| **A source stamp** | `.source_stamp`, a sha1 over every copied file's relative path, size and mtime. The `TODO(xha)` about never invalidating is closed. |

Both are in `bin/flutterware.dart`. The spikes below measure what they cost and
what they still leave on the table.

## The stages, and who pays for each

An external user's first run, in order:

| | stage | paid by |
|---|---|---|
| 1 | `dart run flutterware` — pub resolution + JIT of the bootstrapper | everyone, every run |
| 2 | `_sourceStamp` — stat every file in the package (1277 tracked files, 13MB) | everyone, **every run** |
| 3 | copy the package tree → `~/.flutterware/<sha1(packageRoot)>/` | on a changed stamp |
| 4 | `dart pub get` in the copy | on a changed stamp |
| 5 | `dart compile kernel app/bin/flutterware.dart` | on a changed stamp |
| 6 | `flutter build macos --release` in the copy | whenever the built GUI is absent — **and stage 5 deletes it** |

Stages 2 and 6 are where the suspicion is. Stage 2 is O(files) on every single
invocation including `fw status`. Stage 6 is minutes, and today *any* source
change — including a one-line edit to a CLI file the GUI never links — deletes
`build/macos` and forces the whole thing again.

The three audiences hit this differently, which is why the baseline has to cover
all three rather than one:

| | how it is reached | what dominates |
|---|---|---|
| **External user** | `dart run flutterware` from a pub-cached version | once: stages 3–6. Then only 1–2. |
| **Dogfood user** | same, warm | stages 1–2, on every command |
| **Us, developing flutterware** | a path dependency on a live checkout | stage 6, repeatedly, because the stamp keeps changing |

**A hypothesis worth testing before spiking S4:** for an external user the
package root is `~/.pub-cache/hosted/pub.dev/flutterware-<version>/`, so
`sha1(packageRoot)` is *already* per-version and already shared across every
project on the machine. If that holds, the per-project fragmentation the copy
looks like it causes only ever hits path-dependency users — and S4 is worth much
less than it appears. Check this first; it is one `ls`.

## The spikes

### S1 — Baseline

**Question.** Where does the time actually go, per stage, for each of the three
audiences, cold and warm?

**Method.** Instrument the six stages. Alternate cold and warm rather than
measuring once each — the 2026-07-27 findings record a 7× "improvement" that
survived several runs and turned out to be environmental.

Three secondary facts to nail down while instrumented, because everything else
is argued from them:

- What `_sourceStamp` costs per invocation.
- Whether `dart compile exe` is genuinely broken here, or was broken once and
  fixed upstream. The whole kernel decision rests on it.
- Whether `flutter build macos --release` no-ops cheaply when nothing changed.
  The findings put a cmake no-op at ~110ms; if a full no-op rebuild is seconds
  rather than minutes, S2 changes shape entirely.

**Success.** A table nobody has to guess at again.

### S2 — What should trigger a GUI rebuild

**Question.** Stage 5 deletes `build/macos` on any stamp change. Should a change
that cannot reach the GUI's import closure trigger a full release build?

**Success.** Editing `app/lib/src/session/cli.dart` does not rebuild the GUI;
editing `app/lib/src/shell/` does.

**Kill criteria.** If S1 says an unchanged `flutter build` no-ops in ~1s, delete
the deletion and stop — Flutter's own incrementality is the answer and a second
staleness model is a bug surface for nothing.

### S3 — Build mode for the GUI

**Question.** Is `--release` needed? What do `--debug` and `--profile` cost, and
what is lost?

**Why it matters.** This is the largest single number in the whole pipeline and
the least examined. `--debug` also gets hot reload, which matters for us.

**Kill criteria.** If a debug GUI is visibly worse to use, this is a
developer-only switch, not a default — say so and move on.

### S4 — Where the build lives

**Question.** Is `~/.flutterware/<sha1(packageRoot)>/` the right key, or should
the built artifacts be shared per flutterware *version* across projects?

**Do the hypothesis check above first.** If the pub-cache path already makes
this per-version for external users, reduce this to "does a path-dependency
developer need anything", which is S6.

### S5 — The floor of one invocation

**Question.** How fast can `fw status` be? Break the ~700ms recorded for `fw`
into process start, session open, and work.

**Success.** A number, and a statement of what the floor is made of. `<200ms` is
the target worth aiming at; whether it is reachable is the finding.

### S6 — Skip the copy entirely, for development

**Question.** The copy exists so there is a writable tree to `pub get` and build
in. A developer's checkout is already writable. What actually breaks if we run
in place?

**Success.** A flutterware developer edits `app/lib/`, runs the CLI, and sees the
change — with no copy, no stamp, and no cache.

**Why it earns a spike.** Today this path does not exist, which is why
`main_dev.dart` exists and why nobody runs the CLI while developing it. The tool
we are designing is bypassed by the loop that develops it.

### S7 — A warm session daemon

**Question.** Would a resident session, found by a derived address the way
`DaemonAddress` already works, take a second `fw` invocation to ~20ms?

**Run this last, and only if S5 says the floor is high.** The catalog daemon
went 2313ms → 19ms for a second client, so the mechanism is proven and the
pattern is already written. What is unproven is that anything here is slow
enough to deserve it. A daemon that saves 100ms is not worth its lifetime,
version-skew and orphan-sweep problems — the 2026-07-27 findings paid all three
of those in full.

## Do not build

No walker, no global install, no SDK download, no distribution. No refactoring
of the CLI's command surface — `FwCli` and the `app` command staying separate is
a known problem with a known fix and it is not this. Hardcode, measure, throw
away.

## How it gets recorded

`2026-07-28-cli-compilation-spike-findings.md`, in the shape of the 2026-07-27
performance findings: the numbers, what was wrong about the assumptions going
in, and the lessons worth keeping. A spike that only produces a recommendation
has thrown away the part that lasts.
