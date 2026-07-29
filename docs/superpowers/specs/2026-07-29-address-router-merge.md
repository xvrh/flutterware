# RouterOutlet, and what an address names

**Date:** 2026-07-29
**Status:** Decided, unbuilt. `ca40bef` answered the routing half by building
`AddressScope`; what is left is one migration and two facts about the address.

---

## 1. `RouterOutlet` is prohibited here. It stays published, unchanged.

`AddressScope` won on merit, not incumbency: aspect-granular rebuilds via
`InheritedModel` (a knob drag redraws one knob — `MatchedPathProvider` is a
plain `InheritedWidget` and `SubMatches.updateShouldNotify` returns `true`
unconditionally), and namespaced parameters whose nesting order *is* their
lifetime. Routing the catalog through `RouterOutlet` would be a downgrade.

One live caller remains:

- `dependencies/list.dart:35` — routes `''`, `'upgrade'`,
  `'packages/:packageName'`. The package already comes from
  `AddressScope.segment(context, 0)` (`dependencies_plugin.dart:48`), so the
  panel nests `AddressScope(eat: 1)` and the screens below switch on segment 0.
- `list.dart:289`, `detail.dart:86,153` — `context.router.go(…)` becomes
  `setSegments(…)`. Two of the three target `'/project/dependencies'`, a
  pre-shell path that is already dead.
- Then `shell_view.dart:58`'s `RouterOutlet.root` shim goes, and with it the
  process-wide `UrlSourceFake` — which is why two worktrees showing
  Dependencies currently share one path.

Everything else importing `RouterOutlet` (`app/app.dart`, `project_view`,
`about`, `drawing`, `test_runner/*`, `main_test_runner_web`) is unreachable from
the shell. Migrate as plugins or delete; they get no vote here.

Nothing in the app wants `:param` matching afterwards. If a plugin later does,
that argues for a small matcher over `AddressView.segments`, not for reviving
`RouterOutlet` inside the shell.

## 2. The worktree segment is git's own name, not the directory.

`worktree.dart:28–35` claims *"git guarantees worktree directory names are
distinct within a repo"*. **False, and tested:**

```sh
git worktree add ../b/feature          # fatal: 'feature' is already used
git worktree add -b m2 ../c/main       # ok — collides with the MAIN worktree
git worktree add -f -b f2 ../d/feature # ok — --force bypasses the check
```

Basenames: `main`, `feature`, `main`, `feature`. With `firstOrNull`
(`shell_controller.dart:132, 366`) that silently picks one — and decision 4
turns picking one into *opening* one.

The admin directory name under `.git/worktrees/` is unique through all three
(`feature`, `feature1`, `main`) and survives `git worktree move`, which the
basename does not. **The main worktree has no admin entry**, and no ordinary
token is safe for it — a *linked* worktree at `…/main` really does take the
admin name `main`. `~` is safe: git sanitizes admin names into valid refname
components, so `has~tilde`→`has-tilde`, `has^caret`→`has-caret`,
`..weird`→`-weird`, `has.lock`→`has`. `~` is a refname operator and cannot
survive.

**Encode it like every other segment.** A literal `/` cannot reach an admin name,
but refnames permit `#`, `&`, `=`, `+`, `@` and `%` — and a directory named
`has%2Fslash` yields an admin name that, left unencoded, round-trips into a
*different* name containing a slash. `Address._encode` already handles
`% / ? # &`; the rule is that the segments the shell parses itself get no
exemption.

**Branch is input, never identity.** It is the more meaningful name — this repo
has `dreamy-chaum-1068ca` on branch `claude/ui-catalog-launch-error-1d608a` —
but a worktree outlives its branch (`git checkout`), a branch moves between
worktrees, a detached worktree has none, and `--force` allows duplicates
(verified). So: **emit the admin name; resolve admin name first, then branch;
the palette matches on branch too.** Forgiving input, canonical output.

Correct the false doc comment while passing through — it is why the
`firstOrNull` looked safe.

## 3. `fw:///` — the authority is the project.

```
fw://<project>/<worktree>/<plugin>/<tail…>?<params>
fw:///flutterware/flutterware.ui_catalog/lib%2Fteam.dart%23Team?axis.theme=dark
```

Empty authority means "the project this shell was launched in", which is every
address emitted today; migration is one character. `//` stays because a scheme
without it is not linkified anywhere that matters, and because OS deep links
need the scheme registered either way. Empty authority is RFC-valid
(`file:///Users/x`), so `Uri.parse` starts *agreeing* with our parser — today's
`fw://wt/…` puts the worktree in the authority, which is exactly why
`Address.tryParse` had to avoid `Uri.parse` (it lowercases the authority;
worktree names may have capitals — `address.dart:133`).

**The scheme is `fw`.**

**Corrected when built:** this said a relative address would carry no scheme,
since with an authority the path must be absolute and `fw:///ui_catalog/x` would
read `ui_catalog` as the worktree. That form was never designed, because it
turned out there was nothing to design it for — `isRelative` and `resolveIn` had
no callers outside their own tests. They are deleted. `worktree == null` now
means "names no worktree", which is where the shell sits before the first one
opens, and `fw:///` is free to mean an empty project. Session-relative
addressing can come back when something actually wants it, and by then the
project slot will say how it should work.

**The project slot stays empty until deep links exist.** One shell is one repo,
so nothing can collide today. When it is populated it needs to be legible,
stable across machines, and always present — `<basename>~<short root sha>` is
the only candidate that is all three, but nothing depends on it yet.

**Not doing:** demoting `worktree`/`plugin` to ordinary segments. `AddressScope`
already enforces the plugin boundary mechanically — a level cannot write above
its own `segmentOffset` — so the uniformity argument has no work left to do.

## 4. Pointing at a worktree opens it.

Opening *is* the navigation. Kill:

| Where | What |
|---|---|
| `shell_controller.dart:354–358` | the doc claim *"navigation must not silently land somewhere other than where it was told"* — self-refuting; refusing is exactly landing somewhere else |
| `shell_controller.dart:363–371` | resolve against all `_worktrees`, `open()` when closed |
| `GoResult.worktreeNotOpen` | unreachable. `worktreeUnknown` stays as the only refusal |
| `shell_controller.dart:397` | `select()`'s `if (!isOpen(worktree)) return;` |
| `shell_controller_test.dart` | `'a worktree that is not open is refused, not opened'` → its opposite |

`go` stays synchronous: `open()` already sets the address and notifies before
awaiting `_load`, and the shell already draws an open-but-loading tab.

Reopens a question `2de5004` half-settled — it narrowed search to the selected
worktree partly because *"a hit in another checkout switches the whole shell out
from under you"*. That becomes policy rather than accident. The warming-cost half
still stands.

## Order

1. Dependencies off `RouterOutlet` (§1). Closes the question this branch opened.
2. `Worktree.name` → admin name (§2). **Before 3** — auto-open turns a name
   collision from a wrong tab into a wrong checkout.
3. `go` opens (§4).
4. `fw:///` and the project slot (§3) — only this one touches anything already
   written down elsewhere.

## Invariant

`path.dart` and `url_source.dart` import no Flutter, which is what lets `fw` and
MCP resolve headlessly — `ca40bef` leaned on the same property moving the device
list to plain Dart *"because `fw` links it and cannot load Flutter"*. It holds by
accident. A test should assert it.
