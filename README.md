# Flutterware

Development tooling for Flutter projects.

Declare the tools you want in `tool/flutterware.dart`. You then get them three
ways: a desktop app, a `fw` command line, and an MCP server. They all run the
same code, so an agent can do anything you can do from the window.

## Quick start

```shell
dart pub add flutterware
```

```shell
# Run this in your Flutter project directory
dart run flutterware
```

That opens the GUI. The first launch is slow — it builds the CLI and the
desktop app — and it also initializes the project: it writes `.flutterware/`
(a pointer to the Flutter SDK you just ran it with), adds that directory to
`.gitignore`, scaffolds a `tool/flutterware.dart` if you have none, and
registers `fw mcp` in `.mcp.json` so an agent opening the repo finds the tools
without being told.

Anything after `dart run flutterware` is passed to the CLI instead:

```shell
dart run flutterware status     # what every tool says about this project
dart run flutterware actions    # what can be invoked, and with what
dart run flutterware help
```

### Put `fw` on your PATH

Once per machine, not per project:

```shell
dart install flutterware
```

`fw <command>` is then `dart run flutterware <command>` from anywhere inside a
project, and the rest of this file is written that way.

It is worth doing even if you like typing. `dart run` has to be started from a
package root and uses whichever `dart` is on your PATH; `fw` walks up to the
project itself and re-execs with the SDK that project recorded in
`.flutterware/`, so it is right in a monorepo, right under fvm, and right when
the `dart` you happen to have is not the one the project resolves against.

**Agents need it.** An MCP client spawns a command; `fw mcp` is a single entry
that works for every project on the machine, where `dart run` would need the
client to already be standing in the right package with the right SDK. See
[The three surfaces](#the-three-surfaces) below.

## Configure the project

`tool/flutterware.dart` is a plain Dart file — the tools are objects you
construct, not YAML keys:

```dart
import 'package:flutterware/plugins.dart';

const app = Pkg('.');

void main() => Flutterware.configure((fw) {
  fw.use(Dependencies(packages: [.new(app)]));
  fw.use(Assets(packages: [.new(app)]));
  fw.use(NativeSplash(packages: [.new(app)]));
  fw.use(UiCatalog(packages: [.new(app)]));
});
```

Monorepos declare a `Pkg` per package and hand each tool the subset it applies
to — see [this repo's own config](tool/flutterware.dart) for a three-member pub
workspace, and [the sample project's](examples/example/tool/flutterware.dart)
for the single-app case.

## The three surfaces

**GUI** — `fw`, with no command. A tab per open git worktree, a sidebar of the
tools you declared, and a command palette on `⌘K`.

**CLI** — the same commands, without the window:

```shell
fw run ui_catalog entries
fw run ui_catalog screenshot --entry='demo/buttons.dart#buttons'
fw status --json
```

An action that produces a file prints its path, so `… | xargs open` works.
Everything else prints as JSON.

**MCP** — `flutterware_status`, `flutterware_actions` and `flutterware_invoke`,
over stdio. Same session, same plugins, so an agent can do what you can do from
the window.

`fw init` already wrote this into your project's `.mcp.json`, which is why
there is usually nothing to do:

```json
{
  "mcpServers": {
    "flutterware": { "command": "fw", "args": ["mcp"] }
  }
}
```

It is merged rather than written, so another server in that file stays and an
entry you have edited is left alone. Put the same three lines in your client's
own config if you would rather not commit it.

The entry names `fw`, so it resolves only if `fw` is installed — see
[Put `fw` on your PATH](#put-fw-on-your-path). Nothing else is per project: the
client sets the working directory, and `fw` finds the project by walking up
from it.

Start with `flutterware_status`. `flutterware_actions` lists what can be
invoked, with each action's parameters and the shape of what it returns, and
`flutterware_invoke` runs one — a screenshot comes back as an image rather than
as a path the agent cannot open.

Stdout is the wire, so logs and anything flutterware has to build before it can
answer go to stderr.

Every capability of every surface is listed in
[docs/capabilities.md](docs/capabilities.md), which is generated from the
plugin declarations rather than written by hand.

## Tools

### UI catalog

Annotate a widget with `@Demo` and it becomes a catalog entry — no map to
register it in, no file to keep in sync:

```dart
import 'package:flutterware/ui_catalog.dart';

@Demo(name: 'Buttons', wrapper: wrapInApp)
Widget buttons() => const ButtonsShowcase();
```

The GUI renders your entries live, and moving between them is near-instant.
From the CLI or from an agent, those same entries can be screenshotted,
inspected (widget tree, layout, what a build printed, what is under a point),
and audited in bulk for anything that fails to compile or render.

`Demo` extends Flutter's own `Preview`, so one annotation serves both the
flutterware catalog and Flutter's widget previewer.

> The catalog is **macOS only** for now. The other tools run everywhere.

### Dependencies

Every dependency of every declared package, with the resolved version, the
constraint that asked for it, and where pub got it from.

### Assets

What a package's bundle actually resolves to, what each asset weighs and which
densities exist, plus an audit for declarations that resolve to nothing, files
a directory declaration never reaches, gaps in a density ladder, duplicates and
oversized rasters.

### Native splash

Resolves your `flutter_native_splash` config the way the platform will —
per surface (including Android 12+, which reads different keys), per theme,
per flavor — tells you which config key won each value, and can run the
generator.

## Libraries

`package:flutterware` also ships runtime libraries your app can depend on.
They are independent of the tools above.

| Library | What it is |
|---|---|
| `ui_catalog.dart` | The `@Demo` annotation the catalog tool discovers, plus `UICatalog` — a standalone catalog app, with its own map-based API, that builds for the web or runs on a device |
| `devbar.dart` | A hidden developer overlay inside your app: logs, network, analytics, device frames, knobs, feature flags |
| `feature_flag.dart` | Feature flags, readable and overridable at runtime |
| `router_outlet.dart` | Nested, URL-driven routing |
| `flutter_test.dart` | Screenshot every step of a `flutter_test` — see [example](doc/app_tests.md) |
| `drawing.dart` | Path building and drawing helpers |
| `plugins.dart` | The plugin contract `tool/flutterware.dart` is written against |

The devbar composes from small plugins:

```dart
import 'package:flutterware/devbar.dart';
import 'package:flutterware/devbar_plugins/logger.dart';
import 'package:flutterware/devbar_plugins/log_network.dart';

Devbar(
  plugins: [LoggerPlugin.init(), LogNetworkPlugin.init()],
  child: MyApp(),
);
```

> The test visualizer's GUI is currently being rewritten and is not in the
> shell. `package:flutterware/flutter_test.dart` still ships and still records
> a screenshot per step.

## Contributing

Any contribution is welcome.
Open GitHub issues and pull requests with your ideas :-)

See [CONTRIBUTING.md](CONTRIBUTING.md), and [CLAUDE.md](CLAUDE.md) for how the
repo is laid out and how the launch flow works.
