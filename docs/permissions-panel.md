# A permissions panel — in your app, not in flutterware

Keeping an eye on what the OS has granted, and flipping one on before you walk
to the screen that needs it, is a genuinely useful thing to have in the devbar.
It is also about sixty lines, and they belong in your project.

flutterware ships no permissions plugin, on purpose. Every app reaches
permissions through a package it chose — `permission_handler`, or the
platform channels it wrote itself — and a panel that lives here would have to
translate that package's vocabulary into one of ours. That translation is
lossy in exactly the place it hurts: see [the traps](#the-traps-worth-knowing)
below, where `permission_handler`'s six states collapse to two under any
honest mapping. Written in your project against your own package, there is no
mapping and nothing is lost.

What flutterware provides is the seam: implement `DevbarPanelSource` and your
panel is mirrored to the run cockpit, to `fw`, and to MCP from the one
declaration — the same path the feature-flag and database panels take.

## The whole thing

```dart
import 'package:flutterware/channels.dart';
import 'package:flutterware/devbar.dart';
import 'package:permission_handler/permission_handler.dart';

/// The permissions this app cares about, by the name you want to see.
const _permissions = <String, Permission>{
  'camera': Permission.camera,
  'location': Permission.locationWhenInUse,
  'notifications': Permission.notification,
};

class PermissionsPlugin implements DevbarPlugin, DevbarPanelSource {
  static PermissionsPlugin Function(DevbarState) init() =>
      (_) => PermissionsPlugin();

  @override
  String get panelId => 'permissions';

  @override
  String get panelLabel => 'Permissions';

  @override
  void describePanel(Panel panel) {
    panel.state(
      'status',
      'Status',
      description: 'What this app believes about each permission, right now.',
      read: _status,
    );

    panel.action(
      PluginAction(
        'request',
        'Request',
        danger: true,
        description:
            'Asks the OS for one permission — the real dialog, on the real '
            'device. Answers with what came back.',
        parameters: [
          ActionParameter(
            'permission',
            'Permission',
            kind: ActionParameterKind.choice,
            description: 'Which one to ask for',
            options: [
              for (var name in _permissions.keys) ActionOption(name),
            ],
          ),
        ],
      ),
      _request,
    );

    panel.action(
      const PluginAction(
        'openSettings',
        'Open settings',
        description:
            "Opens this app's page in the OS settings — the only route back "
            'from a permanent denial.',
      ),
      (_) async => {'opened': await openAppSettings()},
    );
  }

  /// Every permission in one call.
  ///
  /// One call rather than one per permission because this is a column: N round
  /// trips over a phone's channel to fill one column is N-1 too many.
  Future<Map<String, Object?>> _status() async {
    var statuses = <String, Object?>{};
    for (var entry in _permissions.entries) {
      // One failing permission must not cost the others.
      try {
        statuses[entry.key] = (await entry.value.status).name;
      } on Object {
        statuses[entry.key] = 'unknown';
      }
    }
    return {'permissions': statuses};
  }

  Future<Object?> _request(Map<String, Object?> arguments) async {
    var permission = _permissions['${arguments['permission'] ?? ''}'];
    if (permission == null) {
      return {'error': 'Which permission? One of ${_permissions.keys}.'};
    }
    // The status *after*, read from the platform — never the request echoed.
    return {'status': (await permission.request()).name};
  }

  @override
  void dispose() {}
}
```

Register it like any other plugin:

```dart
Devbar(
  plugins: [
    PermissionsPlugin.init(),
    // …
  ],
  child: const MyApp(),
)
```

## What that buys

The declaration is the only thing you write. From it:

- the **run cockpit** draws the panel — statuses, a Request button, Open
  settings;
- **`fw`** reaches the same three through the generic panel verbs —
  `fw run run panelState --panel=permissions --state=status`,
  `fw run run panelInvoke --panel=permissions --action=request …`;
- **MCP** exposes them to an agent with no extra plumbing.

Reading a status from inside the process is also the only reading available at
all on a physical iPhone and on macOS, where the host has no store anything
else can read.

## What it cannot do

Worth knowing before you build a workflow on it.

**You cannot revoke or reset from inside the app.** Neither platform offers it.
So this is a convenience for getting *into* a granted state, not a way to test
the denied path or to reproduce a first install. Returning an app to its
never-asked state still means uninstalling it, or `adb shell pm
reset-permissions` / `xcrun simctl privacy … reset` from a terminal.

**On iOS, `request` shows a dialog once per install.** After the first answer
the platform returns the stored one without asking, so the button quietly
becomes a no-op and Open settings is the only route — which backgrounds the
app, and iOS then suspends it.

**On Android it works best**, and even there the status you can read is
coarser than it looks. Which brings us to:

## A panel scoped to something that opens and closes

The plugin above is declared in the devbar's plugin list, which is right for a
panel the app has all the time. Some panels are not like that: a database
opened at login and closed at logout has nothing to hand a devbar built at
`runApp`, and the same goes for anything belonging to a checkout, a document, a
selected workspace.

Two shapes, and the first is usually the better one.

**Keep the panel and let it say why it is empty.** Close over the lookup rather
than over the thing, resolve it inside each handler, and throw a sentence when
there is nothing to resolve. `DatabaseAdapter`'s own documentation carries the
worked version, `DatabaseUnavailable` and all.

**Or scope the panel to the subtree** with `AddDevbarPanel`, which serves a
`DevbarPanelSource` for exactly as long as it is mounted:

```dart
AddDevbarPanel(
  source: _session.databasePanel,
  child: signedInApp,
)
```

The list of panels is announced on every change and every host re-reads it, so
a panel appearing halfway through a run reaches the cockpit, `fw` and MCP with
none of them knowing what a session is.

The reason to prefer the first: **a panel that is not there cannot explain
itself.** Ask for `db:main` when it has gone and every surface answers *"this
app declares no panel db:main"* — the same sentence whether the app has no
database at all or the user is one tap away from opening one. Reach for
`AddDevbarPanel` when the panel genuinely does not exist outside its scope,
not merely when its data does not.

## The traps worth knowing

If you use `permission_handler`, two of its states do not mean what the names
suggest. Both were found by driving a real app against what the OS actually
held.

**`denied` does not mean denied.** `permission_handler` has no *undetermined*:
a permission nobody has ever been asked for and one the user turned down both
arrive as `PermissionStatus.denied`. If you show that word, a brand-new
install reads as though the user refused everything.

**`permanentlyDenied` is meaningless on Android before the first ask.** It is
derived from `shouldShowRequestPermissionRationale`, which is false *both*
before the first request and after a "don't ask again". So a fresh install
reports every permission permanently denied — and there is no way to tell that
apart from a real permanent denial.

Between them, an honest mapping on Android leaves you with *granted* or *don't
know* and little in between. That is the real resolution of what this package
can tell you there, and it is worth rendering as such rather than picking a
word that looks more precise than the data.

A package that asks the platform directly — or your own code, tracking whether
you have ever issued a first request — can do better. That is the line to
change, and it is in your project, which is the point.
