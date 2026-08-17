# Flutterware

Development tooling for Flutter projects.

Declare the tools you want in `tool/flutterware.dart`. You then get them three
ways: a desktop app, a command line, and an MCP server. They all run the same
code, so an agent can do anything you can do from the window.

## Quick start

**Use whichever Dart your project already uses.** Flutterware does not install
an SDK, ask you to switch one, or care how you manage them:

```shell
dart pub add flutterware          # or: fvm dart pub add flutterware
```

```shell
# Run this in your Flutter project directory
dart run flutterware              # or: fvm dart run flutterware
```

That opens the GUI. The first launch is slow — it builds the CLI and the
desktop app — and it also initializes the project: it scaffolds a
`tool/flutterware.dart` if you have none, and registers flutterware in
`.mcp.json` so an agent opening the repo finds the tools without being told.

**The SDK you run it with is the SDK it uses**, every time, and nothing is
recorded anywhere. If your project pins with fvm, run `fvm dart run
flutterware` and that is the pin honoured — there is no second place for the
answer to be written down and go stale, and nothing here competes with your
version manager. An alias is worth having:

```shell
alias fw='fvm dart run flutterware'   # or 'dart run flutterware'
```

Put that in your shell's rc file — `~/.zshrc`, `~/.bashrc` — and the rest of
this README reads as written: **`fw` below is that alias**, and nothing
installs a binary by that name. Because the alias names the `dart` in it, the
SDK stays yours to choose, and a project that switches version managers is one
edited line rather than a reinstall.

Anything after `dart run flutterware` is passed to the CLI instead:

```shell
fw status     # what every tool says about this project
fw actions    # what can be invoked, and with what
fw help
```

### Agents

An MCP client spawns a command, so `fw init` writes one into `.mcp.json`:

```json
{ "mcpServers": { "flutterware": {
  "command": "dart", "args": ["run", "flutterware", "mcp"]
} } }
```

It names no version manager on purpose — whichever `dart` your client provides
is the SDK, resolved when the server is spawned rather than recorded when the
entry was written. Prefix it (`fvm dart …`) if that is how your project says
which SDK it wants. One caution if you do: a version manager asked for a
version it has not cached may install it and narrate the download onto stdout,
which is where the protocol lives — install it once by hand first. See
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
  fw.use(Previews(packages: [.new(app)]));
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
fw run previews entries
fw run previews screenshot --entry='demo/buttons.dart#buttons'
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
    "flutterware": {
      "command": "dart", "args": ["run", "flutterware", "mcp"]
    }
  }
}
```

It is merged rather than written, so another server in that file stays and an
entry you have edited is left alone. Put the same lines in your client's own
config if you would rather not commit it.

The command is the one you would type, and it names no version manager: your
client's `dart` is the SDK, resolved when the server is spawned. Change it to
`fvm dart …` — or whatever your project uses — if that `dart` is not the right
one. The client sets the working directory, so it has to be the package the
`flutterware` dependency is in.

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

### Previews

Annotate a widget with Flutter's own `@Preview` and it becomes an entry — no
map to register it in, no file to keep in sync, and **nothing of flutterware's
to import**:

```dart
// demo/buttons.dart
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Buttons')
Widget buttons() => const ButtonsShowcase();
```

That is the whole of it. If you already write `@Preview` for Flutter's own
previewer, those previews open here unchanged — on a real device frame, with
`dart:io`, plugins, knobs and screenshots. `package:flutterware/previews.dart`
is only for what the annotation does not carry: a shell (`PreviewShell`) and
knobs (`context.knobs.*`).

**It also goes on a widget's constructor**, as long as the constructor is
public and takes no required arguments. That is Flutter's rule, not ours, and
it is the one worth knowing if you are *moving* a catalog rather than starting
one: a catalog written against a map API already has a widget per entry, so
annotating each is two import lines and one annotation per file, where writing
a top-level function per entry would leave you with a function, a class and a
`main()` for every one of them.

```dart
class SymptomCardExample extends StatelessWidget {
  @Preview(name: 'Card')
  const SymptomCardExample({super.key});
  ...
```

**Previews are found wherever you write them.** The whole package is scanned —
beside the widget in `lib/`, in `demo/`, wherever — skipping what `git` skips,
so nothing you have ignored is compiled. A package that wants the scan bounded
to one directory says so once:

```dart
fw.use(Previews(packages: [.new(app, directory: 'demo')]));
```

**The tree in the panel is your directory layout.** A preview in
`demo/care_planner/add_or_edit.dart` lands under `care_planner`, and a file
holding several entries becomes a level of its own — so the folders you already
have are the grouping, and there is nothing to declare. **Every label is spelled
the way its source spells it**: a directory as it is on disk, a file as it is on
disk, a `group:` and a `name:` as you typed them. Nothing is prettified, so a
row in the tree always names something you can open. `@Preview(group:)` is how
you say it differently — entries sharing a `group:` are gathered into a folder
by that name, under the directory they live in, so `group: 'Care planner'`
across several files in one directory is one folder rather than one per file.
It is a label rather than a path, so `group: 'Assessment/Detail'` is a single
folder with a slash in its name and not two levels.

**Say what your app is shaped like, once.** With no device a preview renders in
a 900 × 700 rectangle — landscape, desktop-shaped — which for a phone app is
the wrong picture in the direction that hides the bug: nothing overflows,
nothing wraps, and the screenshot looks fine. A package that is all phones says
so in one place instead of passing `--device` to every screenshot, script and
CI invocation:

```dart
fw.use(Previews(packages: [.new(app, device: Devices.iphone16)]));
```

The panel opens on it, `screenshot`, `inspect` and `compare` frame with it, and
a call that names its own `--device` still wins — `--device=fit` is how one call
asks for the plain rectangle back. `orientation:` turns it.

**One package, two form factors.** A phone app and a desktop dashboard sharing a
theme and a widget library is an ordinary monorepo shape, and one device on the
package frames half the catalog on the wrong screen. Say where each of them
lives instead, and the longest prefix wins:

```dart
fw.use(Previews(packages: [
  .new(app, directory: 'demo', canvases: [
    PreviewCanvas('demo/mobile', devices: [Devices.iphone16, Devices.iphoneSe]),
    PreviewCanvas('demo/desktop', devices: [Devices.macbookPro]),
  ]),
]));
```

`device:` is the same thing with no prefix, so nothing above changes. **The list
is the offered set, and its head is the default** — the panel's picker offers
all of them under *Declared*, and anything drawing one picture takes the first.

**Your tests can read the same list.** `PreviewCanvas` is plain Dart, so keep it
in your own package and hand it to both this config and a test that walks your
catalog — a desktop entry pumped on a phone surface reports overflows that are
not real, and this is the one fact that stops the tool and the test disagreeing
about your directories:

```dart
import 'package:flutterware/flutter_test.dart';
import 'package:demo/canvases.dart';

testWidgets(entry.name, (tester) async {
  var reset = tester.applyCanvas(canvasFor(canvases, entry.path));
  await tester.pumpWidget(entry.build());
  reset(); // in the body — a tearDown runs too late to undo the platform
});
```

If you have never written one, `fw run previews new --name='Buttons'` writes
the first — or press **New preview** in the panel, which is what it shows when
it finds none. New files land in `demo/`, or in the directory you named.

The GUI renders your entries live, and moving between them is near-instant.
From the CLI or from an agent, those same entries can be screenshotted,
inspected (widget tree, layout, what a build printed, what is under a point),
and audited in bulk for anything that fails to compile or render.

![The Previews panel, showing a Buttons preview rendered live beside the entry
tree and the inspection pane](doc/screenshots/ui_catalog.png)

The preview is a real Flutter engine in its own process, not a re-render of
your widget in the tool's. A preview can pin its own canvas — a phone, a tablet
— and get that device's size and pixel ratio from `MediaQuery`, because the
guest's window *is* the device screen:

![The same panel showing a preview pinned to an iPhone 13 canvas, drawn inside
a device frame](doc/screenshots/ui_catalog_device.png)

> Previews are **macOS only** for now. The other tools run everywhere.

### Scenarios

A `flutter_test` that screenshots itself. The verbs act, wait for the screen to
settle and capture — so a test you would have written anyway leaves a picture,
a widget tree and the visible texts for every step:

```dart
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Order a cappuccino', (s) async {
    await s.pumpWidget(const ShopApp());
    await s.tap(ShopKeys.getStarted);
    await s.tap('Cappuccino');
    await s.tap(ShopKeys.placeOrder);
  });
}
```

`flutter test` runs it like any other test. The GUI runs the same file and
draws the flow — including `s.split`, which replays the body once per path so
one scenario covers every way through a screen. Devices and languages are
declared per folder, so nothing repeats them per test, and CI brings its own
matrix. `fw run scenarios shots` turns the named captures into a store-ready
tree by language and device.

See [doc/scenarios.md](doc/scenarios.md).

### Dependencies

Every dependency of every declared package, with the resolved version, the
constraint that asked for it, and where pub got it from.

![The dependencies table, listing each package with its type, origin,
constraint and resolved version](doc/screenshots/dependencies.png)

### Assets

What a package's bundle actually resolves to, what each asset weighs and which
densities exist, plus an audit for declarations that resolve to nothing, files
a directory declaration never reaches, gaps in a density ladder, duplicates and
oversized rasters.

![The assets panel, listing every asset with its size and variants, above two
flagged problems](doc/screenshots/assets.png)

### Native splash

Resolves your `flutter_native_splash` config the way the platform will —
per surface (including Android 12+, which reads different keys), per theme,
per flavor — tells you which config key won each value, and can run the
generator.

![The splash previewer, showing the same config rendered for Android, Android
12+, iOS and web in both themes](doc/screenshots/splash.png)

### Server inspection

A Dart server that imports `package:flutterware/server.dart` announces itself
however it was launched — `dart run`, the IDE, an agent — and the GUI shows
its requests live: a waterfall of the queries and logs each one caused, an
N+1 badge when a query shape repeats inside a request, request and response
with headers and bodies, and a SQL view aggregating every query by shape.
Explain and requery run inside your server, on its own connection. Inert in
release builds; adapters are copy-paste snippets —
see [doc/server_inspection.md](doc/server_inspection.md).

The same answers reach the CLI and MCP: `requests`, `errors` and `sql`
actions return the correlated data with no GUI running.

Dart servers only — the server announces itself by importing that library in
its own process, so a backend in another language is out of scope rather than
unsupported-for-now.

![A request opened in the server inspector: the N+1 warning naming the
repeated query, and the waterfall of its queries](doc/screenshots/server.png)

## Libraries

`package:flutterware` also ships runtime libraries your app can depend on.
They are independent of the tools above.

| Library | What it is |
|---|---|
| `previews.dart` | What a `@Preview` needs beyond Flutter's annotation: `PreviewShell` for the top bar's axes, and `context.knobs.*` for knobs |
| `ui_catalog.dart` | `UICatalog` — the shell `previews build-web` mounts to make a browsable page of your previews. Mountable in your own app too, through its older map-based API |
| `devbar.dart` | A hidden developer overlay inside your app: logs, network, analytics, device frames, knobs, feature flags |
| `feature_flag.dart` | Feature flags, readable and overridable at runtime |
| `router_outlet.dart` | Nested, URL-driven routing |
| `flutter_test.dart` | A strict superset of `package:flutter_test`, plus the scenario API — see [doc/scenarios.md](doc/scenarios.md) |
| `server.dart` | Live inspection for Dart servers — the primitives behind the server tool above, and the protocol its attachers use |
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

> `package:flutterware/flutter_test.dart` is a drop-in superset of
> `package:flutter_test`: everything re-exported 1:1, nothing hidden. An
> existing test file compiles with only its import changed.

## Contributing

Any contribution is welcome.
Open GitHub issues and pull requests with your ideas :-)

See [CONTRIBUTING.md](CONTRIBUTING.md), and [CLAUDE.md](CLAUDE.md) for how the
repo is laid out and how the launch flow works.

The screenshots above are generated, not taken by hand (except the shell and
server ones, which need a hand anyway) — flutterware
photographs itself:

```sh
fvm dart tool/screenshots.dart
```

The script shoots with the `dart` that ran it, so this repo's own pin is the
one to name — see [CONTRIBUTING.md](CONTRIBUTING.md) for the fvm setup.

Each one is a `fw capture` of the GUI at a fixed size, density and theme, so
re-running it leaves the files untouched unless what they show has actually
changed. See [tool/screenshots.dart](tool/screenshots.dart) for the list, and
`fw help capture` for how a panel can tell it is being photographed.
