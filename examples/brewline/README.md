# Brewline

A small coffee-shop app, wired up with [flutterware](https://github.com/flutterware/flutterware).
It exists to be cloned: one command opens the studio and every tool below is
already pointed at something real.

```sh
git clone https://github.com/flutterware/flutterware_example
cd flutterware_example
dart run flutterware
```

That is the whole setup. The first run is slow — it builds the studio — and it
needs no SDK of its own: the `dart` you type is the `dart` it uses, so
`fvm dart run flutterware` works the same way if that is how you pin.

## What to look at

**Previews** — `demo/shop.dart` has one entry per screen, annotated with
Flutter's own `@Preview`. They open framed on a phone because
`tool/flutterware.dart` says the app is one; nothing is written on the
annotations.

**Scenarios** — `test/scenarios/shop_test.dart` is a `flutter_test` that
screenshots itself. `flutter test` runs it like any other test; the studio runs
the same file and draws the flow, including the `split` that fans out into every
way through the menu. Every step leaves a picture, a widget tree and the visible
texts, in both languages.

**Translations** — the words are in `assets/i18n/`, and because the scenarios
record which key each screen asked for, the panel can say where a string
actually appears.

**Dependencies, Assets, Splash, Launcher icon** — what this project resolves to,
what it weighs, and what the platforms will actually show.

**Run** — launch the app on a device and drive it: by hand, from `fw`, or from
an agent over MCP.

## The command line and agents

Everything the window does is also a command, because they run the same code:

```sh
alias fw='dart run flutterware'

fw status                       # what every tool says about this project
fw actions                      # what can be invoked, and with what
fw run previews screenshot --entry='demo/shop.dart#shopMenu'
fw run scenarios run
```

`dart run flutterware` also wrote an MCP server into `.mcp.json`, so an agent
opening this repo finds the same tools without being told.

## Layout

```
lib/shop/        the app — welcome, menu, drink, cart, confirmation
demo/            @Preview entries, one per screen
test/scenarios/  the scenario, and the config that says which devices and
                 languages it replays on
assets/i18n/     the words, English and French
tool/flutterware.dart   which tools this project gets, and how they are aimed
```
