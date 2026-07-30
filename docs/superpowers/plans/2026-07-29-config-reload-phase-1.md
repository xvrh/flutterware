# Config reload, phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make reloading a worktree's config **correct and legible**: a failed
config changes nothing, an edit that changes nothing costs nothing, and an edit
that changes one plugin costs only that plugin. Plus the three surfaces that
make all of that visible, because two of the three wins are otherwise invisible.

**Architecture:** Today `reloadConfig` calls `_releaseAt` and *then* `_load` —
it disposes the session, the panels, the cores and the workspace before it knows
whether the new config even compiles. This plan inverts that: load first, diff
the new manifest against the retained previous one, and mutate the existing
session in place — disposing and rebuilding only the plugins whose declaration
moved. A changed `packages:` list still forces a full rebuild, because
`Workspace` interns `PackageRef` for identity comparison and every `PluginHost`
holds the workspace. No plugin cooperation is required anywhere: an affected
plugin is disposed and reconstructed, never reconfigured in place.

**No watcher in this phase.** The button stays the trigger. A watcher makes
every reconciliation bug fire on a timer instead of on a click, and the
reconciliation should be driven by hand first.

**Tech Stack:** Dart / Flutter, `package:collection` (`DeepCollectionEquality`),
`flutter_test`. No new dependencies.

**Status:** Done, 2026-07-30. Three deviations from the plan as written, each
recorded at its step: the reload log became a screen rather than a home-screen
section, the smoke steps are a mix of live runs and widget tests, and the
watcher — listed here as out of scope — shipped after the smoke.

**Spec:** [`docs/superpowers/specs/2026-07-29-config-reload-findings.md`](../specs/2026-07-29-config-reload-findings.md)
**Amends:** [`docs/superpowers/specs/2026-05-18-worktree-explorer-plugins-design.md`](../specs/2026-05-18-worktree-explorer-plugins-design.md) § config.dart lifecycle

---

## File Structure

```
app/lib/src/plugins/
  manifest_diff.dart          # NEW    — the comparison; pure Dart, no Flutter
  worktree_session.dart       # MODIFY — reconcile, panels torn down before cores
app/lib/src/session/
  session.dart                # MODIFY — cores mutable; reconcile primitive
app/lib/src/shell/
  config_load.dart            # NEW    — ConfigLoad outcome + per-worktree log
  shell_controller.dart       # MODIFY — retain the projection; load before swap
  shell_view.dart             # MODIFY — status line + sticky error banner
  worktree_home.dart          # MODIFY — reload-log section

app/test/plugins/manifest_diff_test.dart   # NEW
app/test/session/session_reconcile_test.dart # NEW
app/test/shell/shell_controller_test.dart  # MODIFY — mutable stub loader, reload cases
```

**Run commands** assume `cd app` from the worktree root before `flutter test` /
`flutter analyze`.

---

## Task 0: Setup

**Files:** none.

- [x] **Step 0.1: Resolve workspace dependencies**

Run: `dart tool/pub_get_all_projects.dart`
Expected: completes without error. (The pre-commit format hook needs resolved
deps; a fresh worktree has none — see the note in CONTRIBUTING/the worktree
memory.)

- [x] **Step 0.2: Baseline the tests**

Run: `cd app && flutter test test/shell/shell_controller_test.dart`
Expected: all pass. Record the count; nothing in this plan may reduce it.

---

## Task 1: `ManifestDiff` — the comparison

Pure data in, pure data out, no Flutter, no disposal. Everything downstream is
mechanical once this is right, so it gets tested alone.

**Files:**
- Create: `app/lib/src/plugins/manifest_diff.dart`
- Test: `app/test/plugins/manifest_diff_test.dart`

- [x] **Step 1.1: Write the failing tests**

```dart
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/plugins/manifest_diff.dart';
import 'package:flutter_test/flutter_test.dart';

PluginManifest _m(
  List<PluginDeclaration> plugins, {
  List<Pkg> packages = const [Pkg('.')],
}) => PluginManifest(plugins, packages: packages);

const _one = PluginDeclaration(id: 'a.one', label: 'One');

void main() {
  test('identical manifests produce an empty diff', () {
    var diff = ManifestDiff.between(_m([_one]), _m([_one]));
    expect(diff.isEmpty, isTrue);
    expect(diff.needsFullRebuild, isFalse);
  });

  test('a changed config key is named, and only that plugin is affected', () {
    var before = _m([
      _one,
      PluginDeclaration(id: 'a.two', label: 'Two', config: {'dir': 'test'}),
    ]);
    var after = _m([
      _one,
      PluginDeclaration(id: 'a.two', label: 'Two', config: {'dir': 'test/unit'}),
    ]);

    var diff = ManifestDiff.between(before, after);
    expect(diff.changed, {'a.two': ['dir']});
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.affected, ['a.two']);
  });

  test('a changed label counts as a change, named as `label`', () {
    var diff = ManifestDiff.between(
      _m([_one]),
      _m([const PluginDeclaration(id: 'a.one', label: 'Uno')]),
    );
    expect(diff.changed, {'a.one': ['label']});
  });

  test('nested config is compared deeply, not by reference', () {
    var before = _m([
      PluginDeclaration(id: 'a.one', label: 'One', config: {
        'packages': [
          {'path': 'app'},
        ],
      }),
    ]);
    var after = _m([
      PluginDeclaration(id: 'a.one', label: 'One', config: {
        'packages': [
          {'path': 'app'},
        ],
      }),
    ]);
    expect(ManifestDiff.between(before, after).isEmpty, isTrue);
  });

  test('added and removed plugins are reported separately', () {
    var diff = ManifestDiff.between(
      _m([_one]),
      _m([_one, const PluginDeclaration(id: 'a.two', label: 'Two')]),
    );
    expect(diff.added, ['a.two']);
    expect(diff.removed, isEmpty);
  });

  test('a changed packages list forces a full rebuild', () {
    var diff = ManifestDiff.between(
      _m([_one]),
      _m([_one], packages: [const Pkg('.'), const Pkg('app')]),
    );
    expect(diff.needsFullRebuild, isTrue);
    expect(diff.isEmpty, isFalse);
  });

  test('reordering rebuilds nothing but is not empty', () {
    const two = PluginDeclaration(id: 'a.two', label: 'Two');
    var diff = ManifestDiff.between(_m([_one, two]), _m([two, _one]));
    expect(diff.orderChanged, isTrue);
    expect(diff.affected, isEmpty);
    expect(diff.isEmpty, isFalse);
  });
}
```

Run: `cd app && flutter test test/plugins/manifest_diff_test.dart`
Expected: fails to compile — `manifest_diff.dart` does not exist.

- [x] **Step 1.2: Implement `ManifestDiff`**

Create `app/lib/src/plugins/manifest_diff.dart` with a `ManifestDiff` carrying
`packagesChanged`, `orderChanged`, `added`, `removed`,
`changed` (`Map<String, List<String>>`, id → the config keys that differ, with
`'label'` included when the label moved), plus:

- `List<String> get affected` — `added + removed + changed.keys`, i.e. what has
  to be disposed or built. **Excludes** `orderChanged`, which rebuilds nothing.
- `bool get isEmpty` — nothing at all differs, including order.
- `bool get needsFullRebuild` — `packagesChanged`.
- `static ManifestDiff between(PluginManifest before, PluginManifest after)`.

Use `DeepCollectionEquality()` for config maps and the packages list. Ids are
unique by construction — `FlutterwareConfig.use` rejects duplicates — so keying
declarations by id is safe; assert it rather than tolerating it.

Document *why* `packagesChanged` is blunt, so nobody optimises it without
reading `Workspace`: `PackageRef` is interned for identity comparison and every
`PluginHost` holds the workspace, so a new workspace invalidates every core.

Run: `cd app && flutter test test/plugins/manifest_diff_test.dart`
Expected: all pass.

---

## Task 2: `Session.reconcile` — swap cores without rebuilding the session

**Files:**
- Modify: `app/lib/src/session/session.dart`
- Test: `app/test/session/session_reconcile_test.dart`

- [x] **Step 2.1: Write the failing test**

```dart
// app/test/session/session_reconcile_test.dart
// Asserts three things: an unchanged declaration keeps the *same instance*, a
// changed one is disposed and replaced, and `onRelease` runs before dispose.
```

Cover:
1. Empty diff → `identical(before, after)` for every core, nothing disposed.
2. `changed: {'a.two': ['dir']}` → `a.two` disposed and a new instance present;
   `a.one` is the same instance.
3. `removed` → core disposed and gone from `cores`.
4. `added` → new core appended in the *new manifest's* order.
5. `orderChanged` only → no disposals, `cores` order follows the new manifest.
6. `onRelease` is called with the core **before** `dispose()` runs on it (assert
   ordering with a shared log list).

Run: `cd app && flutter test test/session/session_reconcile_test.dart`
Expected: fails — no `reconcile`.

- [x] **Step 2.2: Make `cores` mutable and add `reconcile`**

In `session.dart`:

- `final List<PluginCore> cores` becomes a private `_cores` with
  `List<PluginCore> get cores => List.unmodifiable(_cores)`. Callers keep
  reading a list they cannot mutate; only `reconcile` writes.
- Add:

```dart
/// Swaps [cores] to match [manifest], disposing and rebuilding only what
/// [diff] says moved. Returns the ids that were rebuilt.
///
/// [onRelease] runs for each core about to be disposed, *before* it is —
/// which is how a renderer tears down whatever it built over that core
/// without this method knowing what a panel is. Same ordering rule as
/// [dispose], in one place rather than two.
///
/// Never called for a diff that `needsFullRebuild`: a new [Workspace] means
/// every host is stale, and the caller rebuilds the session instead.
List<String> reconcile(
  PluginManifest manifest,
  ManifestDiff diff, {
  void Function(PluginCore core)? onRelease,
  PluginCoreRegistry? registry,
})
```

Implementation: assert `!diff.needsFullRebuild`; index the surviving cores by
id; for each declaration in `manifest.plugins` in order, reuse the existing core
when its id is untouched by `diff`, else create a fresh one from a new
`PluginHost`; then `onRelease` + `dispose` every core that is not in the new
list. Build the new list *before* disposing anything, so a factory that throws
leaves the session intact.

Run: `cd app && flutter test test/session/session_reconcile_test.dart`
Expected: all pass.

- [x] **Step 2.3: Confirm nothing else mutated `cores`**

Run: `cd app && flutter analyze`
Expected: no new diagnostics. (`Session.cores` is read in `coreById`,
`coreByShortName`, `reports` and the CLI; none of them write.)

---

## Task 3: `WorktreeSession.reconcile` — panels beside cores

**Files:**
- Modify: `app/lib/src/plugins/worktree_session.dart`
- Test: `app/test/shell/shell_controller_test.dart` (covered end-to-end in Task 5)

- [x] **Step 3.1: Add `reconcile`**

```dart
/// Applies [diff] to this worktree: panels for retained cores are retained,
/// panels over disposed cores go with them, and a new core gets a new panel.
///
/// This is the one place the guest engines survive a reload:
/// `UiCatalogPlugin._sessions` holds a `CatalogSession` per package, so
/// keeping the *panel* — not merely the core — is what keeps a device alive.
List<String> reconcile(PluginManifest manifest, ManifestDiff diff, {…})
```

Implementation: build a `Map<PluginCore, NativePlugin>` of current panels, call
`session.reconcile` passing `onRelease` that removes the listener and disposes
that core's panel, then rebuild `plugins` by walking `session.cores` and reusing
the panel for a retained core or `registry.create(core)` for a new one. Wire
`notifyListeners` on new panels; `notifyListeners()` at the end.

`plugins` stops being `final`/`List.unmodifiable` in the constructor and becomes
a private field behind an unmodifiable getter, same shape as `Session.cores`.

- [x] **Step 3.2: Verify the ordering invariant still holds**

The class doc promises "panels first, then the behaviour under them". Add a
sentence to it noting that `reconcile` honours the same order through
`onRelease`, so the two paths cannot drift.

Run: `cd app && flutter analyze`
Expected: clean.

---

## Task 4: `ConfigLoad` — what happened, so it can be shown

**Files:**
- Create: `app/lib/src/shell/config_load.dart`

- [x] **Step 4.1: Define the outcome**

```dart
enum ConfigLoadOutcome {
  /// Ran, matched what was already there. **The important one** — it must be
  /// reported, not inferred from silence, because a no-op reload and a reload
  /// that never fired look identical otherwise.
  unchanged,
  /// Some plugins were rebuilt; the rest were left alone.
  reconciled,
  /// `packages:` moved, so everything went.
  rebuilt,
  /// The config did not produce a manifest. Nothing was torn down.
  failed,
}

class ConfigLoad {
  const ConfigLoad({
    required this.at,
    required this.duration,
    required this.outcome,
    this.rebuilt = const [],
    this.reasons = const {},
    this.error,
  });
  // …
  /// One line for a log row: "UI catalog rebuilt (packages)".
  String get summary;
}
```

No test of its own — it is a value type, exercised through Task 5.

---

## Task 5: `ShellController` — load before swap

**Files:**
- Modify: `app/lib/src/shell/shell_controller.dart`
- Modify: `app/test/shell/shell_controller_test.dart`

- [x] **Step 5.1: Make the stub loader mutable**

`_StubLoader` currently takes a fixed manifest string. Give it a settable
`manifest` and `exitCode` so a test can change what the config "prints" between
loads. Add a `loads` counter for asserting a reload actually ran.

- [x] **Step 5.2: Write the failing tests**

Add to `app/test/shell/shell_controller_test.dart`:

1. **An unchanged config disposes nothing.** Open, clear `_disposedIds`, reload,
   expect `_disposedIds` empty, expect the same `WorktreeSession` instance, and
   expect `lastLoad(w)!.outcome == ConfigLoadOutcome.unchanged`.
2. **A changed plugin config disposes only that plugin.** Reload with `a.two`'s
   config changed; expect `_disposedIds` to contain only `…:a.two`, and
   `outcome == reconciled` with `rebuilt == ['a.two']`.
3. **A removed plugin is disposed; the survivor is the same instance.**
4. **An added plugin appears without disposing anything.**
5. **A broken config tears nothing down.** Reload with `exitCode = 1`; expect
   the session still present, `_disposedIds` empty, `errorFor(w)` non-null, and
   `outcome == failed`. *This is the test that would fail today.*
6. **A changed `packages:` rebuilds everything** — `_disposedIds` has every id,
   `outcome == rebuilt`.
7. **A blocked guard still refuses**, and the refusal is recorded rather than
   silent — `reloadConfig()` returns false and no load is logged.
8. **The address survives a reload that removes the selected plugin** —
   `selectedPluginId` falls back to null (home) rather than pointing at a gone
   plugin. This already works via the existing fallback; the test pins it.

Run: `cd app && flutter test test/shell/shell_controller_test.dart`
Expected: the new tests fail; the pre-existing ones still pass.

- [x] **Step 5.3: Retain the projection and invert `_load`**

Add `final _manifests = <String, PluginManifest>{}` and
`final _loads_ = <String, List<ConfigLoad>>{}` (capped at 20 entries, newest
first), plus `ConfigLoad? lastLoad(Worktree)` and
`List<ConfigLoad> loadLog(Worktree)`.

Rewrite `_load` to:

1. Stamp a start time. Load the manifest.
2. Bail on a superseded generation exactly as now.
3. **On error: record `failed`, set `_errors[path]`, notify, and return** —
   without releasing anything. Keep `_manifests[path]` as it was, so the next
   successful load diffs against the last *good* config rather than against
   nothing.
4. On success with no existing session: build as today (this is `open`).
5. On success with an existing session: `ManifestDiff.between(previous, next)`.
   - `diff.isEmpty` → clear any stale error, record `unchanged`, notify, return.
   - `diff.needsFullRebuild` → `_releaseAt` + build fresh, record `rebuilt`.
   - otherwise → `session.reconcile(next, diff)`, record `reconciled` with the
     rebuilt ids and `diff.changed` as the reasons.
6. Store `_manifests[path] = next` on every success.

`reloadConfig` no longer calls `_releaseAt` itself — the full-rebuild branch owns
that. Its guard check stays.

Take an injectable `DateTime Function() now` (defaulting to `DateTime.now`) so
the log is deterministic under test.

Run: `cd app && flutter test test/shell/shell_controller_test.dart`
Expected: all pass, including the count recorded in Step 0.2.

---

## Task 6: The three surfaces

Without these, two of the three wins are invisible and the third is untrustworthy.

**Files:**
- Modify: `app/lib/src/shell/shell_view.dart`
- Modify: `app/lib/src/shell/worktree_home.dart`

- [x] **Step 6.1: The transient status line**

A small widget beside `_ReloadButton` reading `shell.lastLoad(selected)`. Shows
for ~3s after a load, then fades:

- `Config reloaded · no changes · 96ms`
- `Config reloaded · UI catalog rebuilt · 140ms`
- `Config reloaded · workspace rebuilt, 4 plugins · 210ms`

The `unchanged` case **must** render. It is the whole point: it distinguishes
"reloaded and matched" from "nothing happened", which are otherwise the same
absence of feedback. Duration is included so a drift from ~100ms to seconds is
visible without anyone instrumenting anything.

- [x] **Step 6.2: The sticky error banner**

`errorFor` currently renders only on `WorktreeHome`, which was fine when a
failed load left you with no panel to be on. Now the session survives, so the
error has to be visible *from a panel*. Add a collapsible banner above the panel
area in `shell_view.dart`: the first diagnostic line, expandable to the full
output, plus the config path.

Not dismissible — it is a fact about the file, and hiding it hides a real
problem. It clears on the next successful load.

- [x] **Step 6.3: The reload log on the home screen**

> **Changed in review.** A section on the home screen is not somewhere you can
> navigate to, and the reload button was in the chrome while its consequences
> were on another screen. The log became `fw://<worktree>/config` — a real
> address, with Reload on it — and the band button now opens that screen instead
> of reloading. See `config_screen.dart`.

A section under the existing error box listing `shell.loadLog(worktree)`: time,
duration, outcome, and *which config key differed* for each rebuilt plugin. This
is the diff made visible, and it is what answers "why did my device just die".

Run: `cd app && flutter analyze && flutter test`
Expected: clean, all pass.

---

## Task 7: Manual smoke

**Files:** none. Uses `app/lib/main_dev.dart`, which opens flutterware's own
repo root — not `examples/example` as written here; the root config declares
more plugins and is the better target anyway.

> **How these were actually run.** 7.1–7.4 were driven live against the running
> GUI once the watcher existed, by editing `tool/flutterware.dart` from a shell
> and reading the reload log the app prints. Everything except *a rendered
> catalog device surviving* is covered that way; that one still needs a click,
> and the findings doc says so rather than implying otherwise. The surfaces are
> additionally covered by widget tests over the real `ShellView`.

- [x] **Step 7.1: The no-op case**

Open the GUI on `examples/example`, open the UI catalog, let a device render.
Add a comment to `examples/example/tool/flutterware.dart`, save, press reload.
Expected: `no changes`, the device still rendering, nothing flickers.

- [x] **Step 7.2: The unrelated-edit case**

Change the `Dependencies(...)` declaration (drop a package). Reload.
Expected: `Dependencies rebuilt`, the catalog device **still alive**. This is
the headline result of the whole plan.

- [x] **Step 7.3: The broken-config case**

Introduce a syntax error. Reload.
Expected: sticky banner with file+line, every plugin still working behind it,
the catalog device still rendering. Fix the file, reload, banner clears.

- [x] **Step 7.4: The blunt case**

Add a package to `fw.packages([...])`. Reload.
Expected: `workspace rebuilt`, device gone, and the log says why.

- [x] **Step 7.5: Record the findings**

Append a short "phase 1 smoke" section to
`docs/superpowers/specs/2026-07-29-config-reload-findings.md` with the observed
durations for each case. If a reconciled reload is not comfortably under the
~150ms the spec predicts, say so there — that number is load-bearing for the
watcher's debounce in phase 2.

---

## Task 8: Submit

- [x] **Step 8.1: Format**

Run: `dart tool/prepare_submit.dart`
Expected: no diff left behind (CI fails on one).

- [x] **Step 8.2: Full suite**

Run: `flutter analyze` from the repo root, then `cd app && flutter test`.
Expected: clean, all pass.

---

## Out of scope, deliberately

- ~~**The watcher.** Phase 1 keeps the button.~~ **Shipped after the smoke**
  (`2c842e1`), once the reconciliation had been driven by hand — which is the
  order this plan asked for, arrived at sooner than expected because the smoke
  went cleanly. Its own trap list is in `config_watcher.dart`.
- **Callbacks / `$fn` paths / the config process.** Phase 2. Nothing here should
  anticipate them beyond leaving `ManifestDiff` working on declarations rather
  than on raw JSON text.
- **`fw config` and the resolved-projection view.** Useful, not blocking; both
  get cheaper once the projection is retained, which this plan does.
- **`reconfigure` / in-place plugin updates.** Rejected in the spec. An affected
  plugin is disposed and rebuilt, because that is the only behaviour that is
  correct without cooperation from the plugin.
