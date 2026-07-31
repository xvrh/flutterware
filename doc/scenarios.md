# Scenarios

A scenario is a `flutter_test` that screenshots itself.

```dart
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Order a cappuccino', (s) async {
    await s.pumpWidget(const ShopApp());
    await s.tap(ShopKeys.getStarted);
    await s.tap('Cappuccino');
    await s.tap(ShopKeys.addToCart);
    await s.enterText(ShopKeys.cupName, 'Xavier');
    await s.tap(ShopKeys.placeOrder);
  });
}
```

`flutter test` runs it like any other test. The flutterware runner runs the
same file and keeps what happened: a picture, a widget tree and the visible
texts for **every step**, in a flow you can walk in the GUI, from the CLI, or
from an agent.

`package:flutterware/flutter_test.dart` re-exports `package:flutter_test` 1:1,
so a file that imports it keeps `expect`, `find`, `testWidgets` and everything
else. Changing the import is the whole migration.

## The verbs

Each one acts, waits for the screen to settle, and captures.

| verb | what it does |
|---|---|
| `pumpWidget(widget)` | mounts the app |
| `tap(target)` | taps |
| `longPress(target)` | presses and holds |
| `enterText(target, text)` | types into a field |
| `drag(target, offset)` | drags by an offset |
| `scrollTo(target)` | scrolls until the target is on screen, then stops |
| `back()` | the Android back button — pops the route |
| `wait(duration)` | moves the fake clock past a timer |
| `screen(name)` | captures without acting |
| `split({...})` | forks the flow |

Everything takes a **target**, which can be a `String` (visible text), a `Key`,
a `Type`, an `IconData`, a `Finder`, or one of:

```dart
await s.tap(Target.label('Add to cart'));          // the semantics label — the
                                                   // handle on an icon that
                                                   // carries no text
await s.tap(Target.tooltip('Delete'));
await s.tap(Target.containing('Buy'));             // text *containing* this,
                                                   // where a plain String
                                                   // matches the whole label
await s.tap(Target.within(ShopKeys.cart, 'Buy'));  // the Buy of *that* card
await s.tap(Target.nth('Buy', 1));                 // the second one
```

They compose, because the scope and the index take targets of their own:
`Target.nth(Target.within(ShopKeys.cart, 'Buy'), 0)`.

When a target matches nothing or matches several things, the error says which
targets *were* on screen and what to reach for instead.

`s.tester` is the real `WidgetTester` if you need something the verbs do not
have. Frames it draws are counted and reported on the next step, so a flow with
a gap in it says so rather than quietly missing a screen.

## Settling

Every verb takes a `settle:`.

```dart
await s.tap(button);                          // Settle.standard — up to 5 seconds
await s.tap(button, settle: Settle.none);     // don't wait
await s.tap(button, settle: Settle.frames(3));
await s.tap(button, settle: Settle.upTo(Duration(seconds: 30)));
```

The default gives up after five (fake) seconds instead of throwing. This
matters: a screen with a spinner on it **never** settles, and
`pumpAndSettle` throws on one. A scenario that reaches a loading state records
`settled: false` on that step — the GUI says *"still animating"* — and carries
on.

## Shots

By default every verb captures. `Shot('name')` names the picture; the unnamed
ones are collapsed as detail steps in the flow.

```dart
scenario('Long flow', shots: Shots.manual, (s) async {
  await s.tap(next);                       // no capture
  await s.tap(next, shot: Shot('Summary')); // captured
});

await s.tap(next, shot: Shot.skip);        // skip just this one
await s.tap(next, shot: Shot('Home', tags: ['store']));
```

Tags are how the store lane picks its screenshots — see below.

## Splitting a flow

One scenario, every path through it:

```dart
scenario('Around the shop', (s) async {
  await s.pumpWidget(const ShopApp(), shot: Shot('Welcome'));
  await s.tap(ShopKeys.getStarted, shot: Shot('Menu'));
  await s.split({
    'a cappuccino': () async {
      await s.tap('Cappuccino');
      await s.split({
        'small cup': () async {
          await s.tap(ShopKeys.size(DrinkSize.small));
        },
        'large cup': () async {
          await s.tap(ShopKeys.size(DrinkSize.large));
        },
      });
      await s.tap(ShopKeys.placeOrder, shot: Shot('Order placed'));
    },
    'the empty cart': () async {
      await s.tap(ShopKeys.openCart, shot: Shot('Empty cart'));
    },
  });
});
```

The body **replays once per path**, so each branch starts from exactly the
state the fork was reached with. Steps before the fork are captured once and
shared; the flow graph fans out where the app does. Splits nest, and a failure
inside one names the branch that reached it.

Because the body replays, anything a branch needs freshly built belongs in the
body — `setUp` runs once per scenario, not once per path.

## Devices and languages

A folder says what it is for, once, in the file `flutter test` already looks
for:

```dart
// test/scenarios/mobile/flutter_test_config.dart
import 'dart:async';
import 'package:flutterware/flutter_test.dart';

const phones = ScenarioProfile(
  'phones',
  devices: [Devices.iphone16, Devices.iphoneSe, Devices.androidTall],
  languages: ['en', 'fr'],
);

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    runScenarios(testMain, profile: phones);
```

**The list is the offered set, and its head is the default.** No scenario
mentions a device. `test/scenarios/desktop/` can name a different profile, and
opening a scenario from either folder frames it the way that folder says — the
GUI remembers a device *per folder*, so picking an iPhone on a phone scenario
never follows you to a desktop one.

`flutter test` runs one pass at the head of each list. CI brings its own:

```sh
flutter test test/scenarios/mobile \
  --dart-define=fw.devices=iphone-se,android-tall \
  --dart-define=fw.languages=en,fr
```

That declares one real test per combination — `Counter [iPhone SE · en]` … —
from a single invocation and a single compile. `FW_DEVICES` / `FW_LANGUAGES`
do the same for a CI job that would rather set an environment block.

Inside a body, `s.assignment` reports what this pass is running as, so an
expectation can adapt to the screen it is on.

## Running them

In the GUI, opening a scenario runs it and draws the flow. From the CLI or an
agent — the same actions, the same shapes:

```sh
fw run scenarios list
fw run scenarios run --file=test/scenarios/mobile/shop_test.dart
fw run scenarios run --devices=iphone-se,android-tall --languages=en,fr
fw run scenarios run --tag=smoke
```

A matrix writes one directory per point — `<output>/<device>-<language>/` —
with an `index.json` beside them mapping each assignment to its directory and
result. Each step leaves a PNG, a `.tree.json` and its texts; a failing
scenario reports the error **with the frame captured at the failure**, not the
one before it.

`--tag` filters scenarios by `scenario(tags: [...])`, the same tag
`flutter test --tags` uses.

Runs share a warm harness, so the second one skips the compile. `restart`
drops it when you want a cold start.

## Store screenshots

```sh
fw run scenarios shots --languages=en,fr --tag=store
```

Keeps only the **named** shots, at each device's own pixel ratio, into

```
<output>/<language>/<device>/01-welcome.png
                             02-menu.png
                             03-order-placed.png
```

With no `--devices`, each folder's profile answers, so one invocation produces
a phone tree for the mobile folder and a window tree for the desktop one. The
output directory is emptied first: what is in it afterwards is exactly this
run.

## Standalone captures

No runner, no GUI — a bare `flutter test` writes the pictures itself:

```sh
flutter test --dart-define=screenshots-destination=build/shots
```

(`SCREENSHOTS_DESTINATION` works too.) Files land under
`<destination>/<assignment>/<scenario>/<index>-<name>.png`.
