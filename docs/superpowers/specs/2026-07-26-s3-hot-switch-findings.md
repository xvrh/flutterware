# S3 — Hot-switching catalog entries in a warm compiler: findings

**Date:** 2026-07-26
**Status:** Spike complete. **Succeeded**, with one trap that constrains the design.
**Follows:** `2026-07-26-s1-scenario-in-embedder-findings.md`
**Raised by:** the UI-catalog session (master plan § "Where to pick up → A").

## The question

S1 proved that *editing* a library and hot-reloading it into a live embedder guest
costs ~11ms compile + ~117ms reload. The catalog needs something S1 never tested:

> Can a **newly reachable library** enter a running isolate via `reloadSources` —
> so that switching catalog entries is a hot reload rather than a restart?

If yes, the framework is compiled once per worktree session and every entry switch
after that is milliseconds. If no, every entry switch pays a cold compile.

## Verdict

**Yes.** New libraries load into a live isolate, on both the VM and Flutter
targets, and revisiting an entry is nearly free because the resident compiler
retains everything it has ever compiled.

**But**: rebinding an existing import prefix to a different library is **silently
ignored**. The generated entrypoint must emit a *fresh prefix* on every switch.

## Results

### Pure Dart — new libraries enter a live isolate

Resident `frontend_server` + `dart --enable-vm-service`, `reloadSources` with the
incremental dill:

| switch | incremental compile | reload | new code ran |
|---|---|---|---|
| add a 1-library local file | 7ms | 56ms | yes |
| add `package:analyzer` (**718 new libs**) | 1344ms | **45ms** | yes |
| switch back to the small library | 2ms | 11ms | yes |
| **re-visit analyzer** (second time) | **7ms**, 0 new sources | 18ms | yes |

Two things to take from this:

- **Reload cost is flat in subtree size.** 718 new libraries reloaded in 45ms.
  Compile dominates; reload does not.
- **The resident compiler is the cache.** A revisited subtree reports
  `newSources=0` and costs ~7ms. Browsing is monotonically cheaper.

Incidental but useful: one case had a compile error. The compiler `reject()`ed,
the guest kept running, and the next switch reloaded normally. **A broken demo
does not kill the session.**

### Flutter target — the prefix trap

Harness: `frontend_server` with `target: flutter`, guest run under
`flutter_tester --run-forever`, real `WidgetsFlutterBinding` + `runApp`, the
element tree walked on a timer, `reloadSources` + `ext.flutter.reassemble`
exactly as S1 does it.

**First attempt failed.** The entrypoint kept `import 'demo_a.dart' as demo;` and
swapped the target to `demo_b.dart`. The 199 new libraries compiled,
`reloadSources` reported `success: true` — and nothing changed. Even a direct
`demo.label()` call still returned the old library's value.

A control case discriminated it: editing `demo_a.dart` *in place* worked
(`direct=A-EDITED tree=DEMO A EDITED`). So reload, reassemble, and the rebuild
are all fine. The failure is specific to **rebinding a prefix**.

**Generating a fresh prefix per switch fixes it completely:**

| switch | compile | reload | rendered tree |
|---|---|---|---|
| A→B, brand-new library (+199 libs) | 218ms | ~117ms | `DEMO B` |
| B→A revisit | 16ms | ~64ms | `DEMO A` |
| A→B revisit | 12ms | ~64ms | `DEMO B` |

Reload figures are net of a 1s settle delay left inside the timed region (raw
output reads ~1100ms). The corrected ~117ms matches S1's number exactly.

**Not disambiguated:** whether the failure is prefix reuse or the unchanged call
site. With the same prefix the call site is necessarily identical, so the two are
confounded by construction. The operational rule is unaffected — emit a fresh
prefix *and* fresh call sites — but the root cause is not established.

## Compile economics

Measured with `frontend_server`, Flutter target, SDK 3.45.0-0.1.pre, against
the reference project's web-app package — a real ~300-entry catalog.

| entrypoint | libraries | cold compile |
|---|---|---|
| bare `MaterialApp` (framework floor) | 772 | **2.3s** |
| `package:server/client.dart` alone (no Flutter) | 2741 | 5.9s |
| the design-system barrel alone | 3587 | 8.5s |
| one View — `AvatarTile` + `MaterialApp` | 3588 | 8.5s |
| one demo entry — `avatar_tile.dart` | 3623 | 9.5s |
| **the full catalog — all ~300 demos** | 5954 | **12.9s** |
| incremental recompile after an edit | — | **10ms** |

### Three separable costs, in surprising order

1. **Framework floor — 2.3s / 772 libs.** Verified that
   `flutter_patched_sdk/platform_strong.dill` contains `dart:*` + `dart:ui` and
   **not** `package:flutter`, so the framework is compiled from source per
   `frontend_server` instance. Real, constant, and the *smallest* of the three.
2. **A dependency leak — ~6s / 2741 libs, paid by every entry.**
   `web_app/lib/src/utils.dart:6` — the barrel every View imports — has
   `export 'package:server/client.dart' show Date, WeekDay;`. `show` filters
   *names*, not compilation, so two date types drag the entire backend closure
   (`aws_client`, a generated API client, powersync) into the closure of a widget
   that renders an avatar row.
3. **Catalog breadth — +2.3k libs / +3.4s** for one entry → all 300. The
   *cheapest* term. Compiling one entry instead of the whole catalog saves 26%,
   not an order of magnitude.

**Conclusion: the catalog map is not the problem.** An earlier hypothesis that
per-entry entrypoints were the speed lever is refuted by the 26% figure.

### Marginal cost per entry, browsing lazily

One resident compiler, a generated entrypoint, real demos added one at a time:

```
demo 1  mobile/team/avatar_tile.dart              cold=8590ms   3624 libs
demo 2  mobile/team/group_list_view.dart          +102ms        +113
demo 3  mobile/login/login.dart                   +22ms         +16
demo 4  mobile/case/carousel.dart                 +20ms         +3
demo 5  mobile/case/size_evolution_chart.dart     +584ms        +125
demo 6  desktop/.../environments_table.dart       +572ms        +237
demo 7  desktop/case/chat.dart                    +19ms         +3
demo 8  mobile/form/summary.dart                  +28ms         +7
demo 9  ui/loading.dart                           +17ms         +2
back to demo 1                                    12ms          +0
re-visit demo 9                                   14ms          +2
```

The first entry pays for everything, including all of `package:server`.
Subsequent entries cost 17ms–580ms. Revisits cost ~12ms. Nine entries browsed
lazily: ~10s total, against 12.9s to compile the catalog up front.

The design holds *because* of the leak, not despite it — once `package:server` is
in the closure, it is in for every entry in the session.

### Worktree switching: ~85% of the closure is path-stable

Bucketing the full catalog's 5954 libraries by whether their URI changes across
git worktrees:

| bucket | libs | share |
|---|---|---|
| pub-cache (path-stable) | 4360 | **73.2%** |
| Flutter SDK (path-stable) | 685 | 11.5% |
| repo-local (worktree-specific paths) | 909 | 15.3% |

A dill cache keyed on (SDK version, resolved package set) lets a newly opened
worktree skip ~85% of the compile work. **This is the lever for the
worktree-switch goal**, and it is independent of everything else in the design.

Verified obstacle: `frontend_server_client` 4.0.0 **never passes
`--initialize-from-dill`** — the flag is absent from its argument list.
`frontend_server` itself supports it (it is how `flutter run` / `flutter test`
get fast restarts), so this needs a direct invoke or a small fork.

## Consequences

- **The inner loop is settled**: one long-lived resident compiler per worktree, a
  generated entrypoint with a fresh prefix per switch, reload-to-switch. Cold
  once per worktree; 17ms–580ms for a new entry; ~12ms for a revisit.
- **Focus mode vs. browse mode is a UI question, not a process question.** They
  are the same warm process; browsing simply means more of the tree has been
  reloaded in.
- **Import hygiene in the target project is worth ~6s of cold start** but is
  one-time per session, and ~85% of it amortises across worktrees. Cache-sharing
  beats import policing. *(Owner's call, 2026-07-26: not worth policing — any
  View may legitimately import a model type from the server package.)*
- **M4 inherits this.** The scenario runner switches scenarios the same way; the
  fresh-prefix rule applies there too.

## Not proven

- The Flutter-target run used `flutter_tester`, not the embedder guest. The
  embedder adds the shared-`IOSurface` path but nothing that touches kernel
  loading; still, the two were not wired together.
- The shared dill cache is analysed, not built. `--initialize-from-dill` across
  worktrees is untested.
- No test of many entries loaded at once (memory growth of a long browse
  session), of unloading, or of a worktree whose `package_config.json` changed
  mid-session.
- All reference-project compiles reported 4 pre-existing errors in `package:server`
  (`forcePathStyle`, `regenerateProjectApiKey`). The CFE compiles the reachable
  closure regardless, so timings are representative — and it independently
  confirms `package:server` is reachable from a View — but those entrypoints do
  not currently compile clean.

## Harnesses

The spike ran entirely in the session scratchpad; nothing was committed and both
repos were left clean. Worth landing under `app/tool/` if reproducibility is
wanted:

| harness | role |
|---|---|
| `host.dart` + `entry.dart` | pure-Dart: resident compiler, VM-service reload, new-library cases |
| `fhost.dart` + `scene.dart` | Flutter target under `flutter_tester`; the in-place-edit control case |
| `gen_host.dart` | generated entrypoint with a fresh prefix per switch — the working design |
| `bench2.dart` / `bench3.dart` / `marginal.dart` | closure sizes, path-stability buckets, marginal cost per entry |
