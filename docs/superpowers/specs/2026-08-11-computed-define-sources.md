# Computed define sources: a script the project already has

**2026-08-11.** Where `DartDefine.from` landed, why `servers` is gone, and why the
thing that replaces it runs a script rather than a command.

## The case

rimbaud (`/Users/xavier/projects/iot-d/rimbaud`) allocates each git worktree a
contiguous 100-port block, so concurrent dev stacks do not collide. Its Flutter
clients read the result as two defines:

```dart
static const localHost = String.fromEnvironment('LOCALDEV_HOST', defaultValue: 'localhost');
static const localPort = int.fromEnvironment('LOCALDEV_SERVER_PORT', defaultValue: 8086);
```

The port is computed by `tool/local_env.dart up` and written to a gitignored
`.env`. `8086` is the *main checkout's* port. So a launch from a worktree that
does not set the define compiles, installs, runs, and talks to another
worktree's database — and nothing on screen says so. That failure mode is what
every decision below is shaped around.

## What was already there, and why it could not do it

`DefineSource` offered `servers` and `hostAddresses`, both contributing *options
to pick from* (`RunCore.optionsFor`). Decision D4 of the launcher brainstorm had
deliberately reduced "inject the local server IP" to "picking rather than
looking up".

`hostAddresses` covers `LOCALDEV_HOST`. Nothing covered the port:

- `servers` only sees servers announcing themselves through
  `package:flutterware/server.dart`. rimbaud's `server_local` is a plain Dart
  server and announces nothing.
- It yields a base URL string; the config wants a bare int.
- The value lives in an allocation table, not in a running process. With the
  stack down the list is empty and the launch silently bakes in `8086`.

## `servers` is deleted

Not superseded — deleted, on its own merits. `optionsFor` returns
`List<String>`, so two servers arrived as two bare URLs with nothing to tell
them apart; the type could not carry the name the handle already had. And
`RunCore` called `scanServerHandles` **without `underRoot`**, so the list was
every `srv-*.json` on the machine, from every project. A source whose answer you
cannot identify is worse than no source.

Side effect worth having: `run_core.dart` no longer imports
`package:flutterware/server.dart` at all.

`hostAddresses` stays, and each address now carries the interface it was found
on (`en0`). `NetworkInterface.list` returns every non-loopback IPv4 — Wi-Fi plus
a VPN `utun`, a Docker bridge, a VM's vnic — and exactly one of them is the one
the phone can reach. Nothing here can tell them apart without asking the
network, which `computeAll` may not do, so the interface name goes out with each
one and the reader decides.

## A script, not a command

Rejected: `DefineSource.command(['dart', 'run', …])`.

A command has to name an executable, and no config file can know which one. A
`dart` on `PATH` is routinely older than the SDK a project pins — this repo's own
is, which is why `CLAUDE.md` says to use `fvm dart` — so a config saying `dart`
would be saying "whichever SDK happens to be first". That is not a thing anybody
means.

So the config names a **script**, and it is run with `dartExecutable`: the same
`dart` that compiles and runs `tool/flutterware.dart` itself, from the worktree
root. Non-Dart commands drop out of scope, which is a real limitation and the
right one — every project with this problem has a Dart tool script already.

## Selection is an argument, not a `pick:`

Rejected: `pick: 'SERVER_HOST_PORT'`, naming a key in a JSON object the script
prints.

It would have grown a path syntax the first time somebody's output was nested,
and it puts a data-extraction expression in a declarative config. Since `args:`
exists, the selection is expressible as an argument to the script —
`args: ['port', 'server']` — which puts it in the tool that owns the data, where
it can be a real function of that tool's model.

Cost: N defines from one script is N process spawns. At two defines that is
nothing. If it ever hurts, "one script, many defines" is a separate shape that
can be added without taking anything back.

## One line is a value; a JSON array is a list

The whole point is that the port gets *injected*, not offered — a chip you have
to click every time is not injection. So:

- **One line** → the script computed the value. It becomes the define's default,
  beating the config's declared default and the code's own fallback, because it
  is the only one of the three worked out just now.
- **A JSON array** → the script listed possibilities. They become suggestions.

The discriminator is a **leading `[`**, not "try JSON and see". Most values worth
computing are also valid JSON — `8186` parses as a number, `null` as null — so
deciding by what the text parses to would make printing a port and printing a
word behave differently for no reason a user could predict.

More than one line is a failure, not a value with a newline in it. Taking the
last line would quietly bake a debug `print` into the build.

## Failure refuses the launch

Everything else in `run_core.dart` degrades: an unreadable handle is a handle
that does not exist, an OS that will not list interfaces means a shorter list.
This one may not. The value is compiled in, and an app built against the wrong
port is indistinguishable from a correct one until it is talking to another
worktree's database.

So a script that could not answer fills `DartDefineEntry.problem` (outranking
"nothing reads this"), shows under the field in the panel, and **refuses the
launch**. Passing the define explicitly launches anyway — the refusal is about
not guessing a value nobody chose, and somebody who typed one has chosen.

## Where it runs

Not in `computeAll`, which may not spawn processes — the rule `track()` already
documents. `resolveScriptSources()` is called by the `entrypoints` action, by
the panel on mount, and by every launch.

Every call re-asks. The point of the source is that it knows something that
changes without the project changing, so a cache keyed on the script's content
would hold a port from before the stack moved and be confident about it.

`launch` resolves **the defines it was handed**, not the core's entry-point
scan. An earlier version swept `entrypointsFor`, which is empty until
`computeAll` has run — so a launch that relied on it found no source to ask and
then refused itself for a value it never looked up.

## One thing fixed on the way past

The two launch paths disagreed about defaults. The action omitted a scanned
default deliberately (`_resolveKnobs`); the panel seeded its text field with one
and then sent it, so the same launch through two surfaces produced two different
build commands. Defaults are now filled in inside `RunCore.launch`, which both
call, and the panel shows a default as `hintText` — so leaving the field empty
and leaving it at its default are the same thing.

## Not done

Dogfooding against rimbaud's real `local_env.dart`: declare `LOCALDEV_HOST` and
`LOCALDEV_SERVER_PORT` in its config, launch from a worktree with an allocated
block, and confirm the app reaches that worktree's server and not `8086` — then
confirm the refusal fires with the stack down. That is the only thing that will
prove the shape is right.
