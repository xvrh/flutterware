import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutterware/plugins.dart';
// The tree types, not the umbrella: same rule as `headless_catalog.dart`, and
// for the same reason — `node.dart` is plain Dart and `ui_catalog.dart` is not.
// ignore: implementation_imports
import 'package:flutterware/src/inspect/error.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/log.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/axis.dart';
// ignore: implementation_imports
import 'package:flutterware/src/ui_catalog/knob.dart';
import 'package:path/path.dart' as p;

import '../../previews/authoring.dart';
import '../../previews/catalog_entry.dart';
import '../../previews/debug_flags.dart';
import '../../previews/devices.dart';
import '../../previews/discovery.dart';
import '../../previews/inspect_client.dart';
import '../../previews/live_session.dart';
import '../../previews/protocol.dart';
import '../../previews/headless_catalog.dart';
import '../../previews/web_build.dart';
import '../plugin_core.dart';
import 'previews_address.dart';
import 'previews_results.dart';
import '../plugin_host.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const uiCatalogPluginId = 'flutterware.previews';

/// The action that compiles a browsable page.
///
/// Named once because two places spell it: the declaration below, and the
/// command the GUI's build dialog shows so the same thing can be run from a
/// terminal. A rename that reached only one of them would put a command that
/// fails in front of a user.
const webBuildActionId = 'build-web';

/// What a package is scanned for when it does not say otherwise: all of it.
const _defaultRoot = defaultCatalogRoot;

/// What the scan knows about a package before anything is compiled.
enum CatalogSetup {
  /// Nothing has scanned this package yet.
  unknown,

  /// The declared directory is not on disk — usually a misspelt `directory:`.
  missing,

  /// The directory is there and holds no entries — every project, before its
  /// first demo. Not an error, and the state the tool should be best at.
  empty,

  /// There is at least one entry.
  ready,
}

/// Entries the text projection lists before it starts counting. A projection is
/// read, not scrolled.
const _projectedEntries = 20;

/// Entry ids spelled out inline as action options. Beyond this the caller reads
/// them from the view, which is what `optionsFrom` says.
const _inlinedOptions = 50;

/// What `--knobs` is, written once because five actions take it.
///
/// `optionsFrom` cannot help here the way it does for `entry`: a knob's names
/// depend on the entry, so there is no one list to point at. What an agent can
/// be given instead is where the names come from and how to ask.
const _knobsDoc =
    'Values to turn before this runs: `name=value,name=value`, or a JSON '
    'object. A knob is whatever the preview asked for while it built — a '
    'preview calling `context.knobs.string("label", "Hello")` '
    'declares one named `label` — so the names come from the preview itself '
    'and differ per '
    'entry. Read them with `describe --entry=<id> --knobs=true`. Each value is '
    'coerced to the kind the preview declared, and a picker takes one of its '
    'option labels; a name the entry does not declare is an error listing the '
    'ones it does.';

/// What `--debug` is. Third of a family, and the distinction is who owns it.
const _debugDoc =
    'The debug switches the framework itself registers, as '
    '`name=value,name=value`. These '
    'belong to neither the preview nor its shell but to the guest process, and '
    'the framework registers them whether anything asks or not — so unlike '
    'knobs and axes the set is fixed and listed in `--help`. '
    '`paint=true` draws the layout guides, `brightness=dark` moves '
    '`MediaQuery.platformBrightness` (dark mode without a shell axis for it), '
    '`banner=false` drops the DEBUG ribbon, `platform=iOS` changes what '
    '`defaultTargetPlatform` reports, `timeDilation=5` slows animations enough '
    'to photograph. Only what you name is set; the rest are left as they are.';

/// What `--axes` is. The distinction from a knob is the whole content.
const _axesDoc =
    'Values for the shell *around* the preview — theme, locale, flavour. Same '
    'syntax as knobs: `name=value,name=value` or a JSON object. The difference '
    'is who declares it and how long it lasts: a knob is asked for by the preview '
    'and travels with the entry, an axis is declared by the `PreviewShell` '
    'wrapping it and stays put as you move between entries. Read them with '
    '`describe --entry=<id> --axes=true`, which also names the shell; an entry '
    'whose wrapper is not a shell offers none.';

/// What `--live` is, on every read that can be answered by a window somebody
/// already has open.
const _liveDoc =
    'Read the entry from a GUI session that is already showing it, instead of '
    'building a fresh guest. **Off unless you ask.** What it buys is real: '
    'attached, the answer describes the preview *as the person left it* — the '
    'dropdown they opened, the tab they switched to, the row they scrolled to, '
    'and anything their clicking made it print or throw. No fresh render can '
    'reach that, because no fresh render performs the clicks. What it costs is '
    'determinism: the same command answers differently depending on whether a '
    'window happens to be open, which is a poor default for CI and for an agent '
    'that did not know to look. So it is opt-in, and `readFrom` says which one '
    'you got either way. Even switched on it declines unless a session is open '
    'on this exact entry and nothing here would change what is drawn, and it '
    'never switches what that window is showing.';

/// Previews' entries, per declared package — everything but the panel.
///
/// Two tiers, and the split is the point. The **scan** parses a package's demos
/// in ~38ms and touches no compiler, so `fw` and an agent read the entry list
/// without building anything. **Screenshots** run the real pipeline headlessly
/// — `HeadlessCatalog` needs no Flutter, which is what lets the button, `fw`
/// and an agent reach the same artifact by the same route.
///
/// What is *not* here is the live compile loop (`CatalogSession`): it drives a
/// guest engine into a texture, so it is Flutter-bound and belongs to the
/// panel. Its progress reaches [report] through [busyStatusFor], which the GUI
/// supplies and a CLI leaves null — correctly, since there is no session in a
/// CLI to be busy.
class PreviewsCore extends PluginCore {
  PreviewsCore(super.host);

  /// Declared packages, filtered to those the workspace knows about, so a typo
  /// cannot make the plugin scan a directory that is not there.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.exists(path)) path,
  ];

  /// The web build in flight per package, so it can be refused a second time
  /// and killed when the worktree goes — see [dispose]. A `flutter build web`
  /// child is not reaped when the Dart process exits.
  final _builds = <String, WebCatalogBuilder>{};

  final _scans = <String, ScanResult>{};
  final _failures = <String, String>{};
  final _scanning = <String>{};

  /// What the GUI's compile loop is doing for a package, when there is one.
  ///
  /// A hook rather than a dependency: the core cannot import the session
  /// without importing Flutter, and the sidebar would otherwise lose the only
  /// status here that takes seconds.
  Status? Function(String path)? busyStatusFor;

  /// The scan failure for [path], for a panel that wants to show it directly.
  String? failureFor(String path) => _failures[path];

  /// What the scan noticed about [path] but did not act on — a duplicate id, an
  /// annotation on something that cannot be an entry.
  ///
  /// Public for the panel's empty state, which is the one place these matter
  /// most: with no entries to show, a diagnostic is the whole explanation of
  /// why, and without it the screen says "you have written none" to somebody
  /// who has.
  List<ScanDiagnostic> diagnosticsFor(String path) =>
      _scans[path]?.diagnostics ?? const [];

  /// Ends anything still running, which for this plugin means a web build.
  ///
  /// Called by the [Session] when the worktree closes. Without it a compile
  /// started from the dialog outlives the window it belongs to and keeps writing
  /// into the user's project.
  @override
  void dispose() {
    for (var builder in _builds.values) {
      unawaited(builder.cancel());
    }
    _builds.clear();
    super.dispose();
  }

  /// Scans [path], unless it already has been. Idempotent.
  ///
  /// Deliberately does **not** start the compile loop: a scan reads files, a
  /// session spawns a daemon, and only mounting the panel justifies the second.
  void track(String path) {
    if (_scans.containsKey(path) ||
        _failures.containsKey(path) ||
        _scanning.contains(path)) {
      return;
    }
    _scanning.add(path);
    notifyChanged();
    unawaited(_scan(path));
  }

  /// Releases [path]. The scan stays — demand says what work is justified, not
  /// what must be discarded.
  void untrack(String path) {}

  /// Scans every declared package and waits — what `fw` does for the duration
  /// of one request, where there is no panel to subscribe on its behalf.
  @override
  Future<void> computeAll() async {
    await Future.wait([
      for (var path in packages)
        if (!_scans.containsKey(path) && !_failures.containsKey(path))
          _scan(path),
    ]);
  }

  Future<void> _scan(String path) async {
    var root = p.join(host.worktree.path, path);
    var entryRoot = rootFor(path);
    var annotations = previewAnnotationsFor(path);
    _scanning.add(path);
    try {
      // Off the calling isolate: a large catalog is tens of milliseconds of
      // file reads and parsing, which is a dropped frame if it runs on the UI
      // isolate.
      var result = await Isolate.run(
        () => CatalogScanner(
          projectRoot: root,
          roots: [entryRoot],
          previewAnnotations: annotations,
        ).scan(),
      );
      _scans[path] = result;
      // A scan that worked supersedes one that did not. Without this the
      // failure outlives its cause for the life of the process: the sidebar
      // keeps the error badge after the demo is fixed, `track` keeps declining
      // to look again because it treats a recorded failure as "already
      // scanned", and `build-web` keeps refusing with the stale message while
      // holding a perfectly good entry list.
      _failures.remove(path);
    } catch (e) {
      _failures[path] = '$e';
    } finally {
      _scanning.remove(path);
      notifyChanged();
    }
  }

  /// What the package is scanned for: `directory` when declared, else the whole
  /// package.
  ///
  /// Public because it is part of the daemon address — `roots` is one of the
  /// fields [DaemonConfig] hashes — so the panel has to reach *this* answer
  /// rather than compute its own. It had a byte-identical copy in
  /// `PreviewsPlugin` until that copy became the next `appPackageRoot`.
  String rootFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] != path) continue;
      var directory = config['directory'];
      if (directory is String && directory.isNotEmpty) return directory;
    }
    return _defaultRoot;
  }

  /// Where a *new* preview file goes — `demo/` unless the package narrowed the
  /// scan, in which case it goes where the scan is looking.
  ///
  /// Apart from [rootFor] because the two stopped being the same question when
  /// the scan widened to the package: everything is found, so nothing has to
  /// live anywhere, and the tool still has to put a scaffold *somewhere*.
  String authoringDirectoryFor(String path) {
    var root = rootFor(path);
    return root.isEmpty ? defaultAuthoringDirectory : root;
  }

  /// The annotation names that mark an entry in [path], without their `@`.
  ///
  /// Part of the daemon address, like [rootFor] and for the same reason: the
  /// panel and `fw run previews` must arrive at one daemon, and two sides
  /// deciding this independently would be two daemons scanning for different
  /// things.
  List<String> previewAnnotationsFor(String path) {
    for (var config in host.packageConfigs) {
      if (config['path'] != path) continue;
      if (config['previewAnnotations'] case List<Object?> names) {
        var registered = names.whereType<String>().toList();
        if (registered.isNotEmpty) return registered;
      }
    }
    return defaultPreviewAnnotations;
  }

  /// What the scan says about [path], before anything is compiled.
  ///
  /// **The gate on the compile loop.** A package with no entries used to reach
  /// the daemon anyway: it bound a socket, scanned the same directory in 1ms,
  /// refused, and exited before the client's first poll — which then ran to its
  /// 30-second deadline and reported that the daemon "never started listening".
  /// Half a minute of waiting for a fact this answers instantly, off a scan the
  /// panel has already paid for.
  ///
  /// [CatalogSetup.missing] is kept apart from [CatalogSetup.empty] because a
  /// misspelt `directory:` is otherwise indistinguishable from a directory
  /// nobody has written a demo in yet — the scanner skips a directory that is
  /// not there without a word ([CatalogScanner] takes the roots on trust).
  CatalogSetup setupFor(String path) {
    var scan = _scans[path];
    if (scan == null) return CatalogSetup.unknown;
    if (scan.entries.isNotEmpty) return CatalogSetup.ready;
    return Directory(
          p.join(host.worktree.path, path, rootFor(path)),
        ).existsSync()
        ? CatalogSetup.empty
        : CatalogSetup.missing;
  }

  /// True while any declared package is being scanned.
  bool get isScanning => _scanning.isNotEmpty;

  /// Every entry found so far, across packages, in scan order.
  List<CatalogEntry> get entries => [
    for (var path in packages) ...?_scans[path]?.entries,
  ];

  /// Where an entry *is*, as the one identifier every surface carries.
  ///
  /// ```
  /// fw:///worktrees/<worktree>/flutterware.previews/<package>/<file…>/<file.dart%23symbol>
  /// ```
  ///
  /// The package comes first because two packages may legitimately declare the
  /// same entry id, and an address that cannot tell them apart is not an
  /// identity.
  ///
  /// The segments come from [catalogSegments], which the panel reads back
  /// through its inverse. Both halves live in one file so that this — the way
  /// in — and the way out cannot drift apart.
  ///
  /// [axes] are *applied*, not identity — the same entry rendered differently —
  /// which is what makes an address with its axes resolved a complete capture
  /// spec rather than an under-specified one.
  Address addressFor(
    String packagePath,
    String entryId, {
    Map<String, String> axes = const {},
  }) => Address(
    worktree: host.worktree.name,
    plugin: host.id,
    segments: catalogSegments(packagePath, entryId),
    axes: axes,
  );

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: _status,
    badge: _failures.isNotEmpty || _scans.values.any((scan) => !scan.ok)
        ? const StatusBadge.dot(Tone.error)
        : StatusBadge.none,
    children: [
      for (var path in packages)
        PluginChild(
          id: path,
          label: path == '.' ? 'root' : path,
          status: _packageStatus(path),
        ),
    ],
    actions: [
      PluginAction(
        'entries',
        'Entries',
        returns: CatalogEntriesResult,
        description:
            'Every catalog entry, with its id and address — the whole list, '
            'not the projection the report carries',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; all of them when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
        ],
      ),
      PluginAction(
        'new',
        'New preview',
        returns: CatalogNewResult,
        description:
            'Writes a preview file where the package keeps them, creating the '
            'directory if it is not there, and reports the id that renders it. '
            'The scaffold renders as written, so start here when you have '
            'never written one: it is the API, in a file that already works.',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'Which declared package; the only one when there is one',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
          const ActionParameter(
            'name',
            'Name',
            required: true,
            description:
                "The preview's name — what the panel lists and what `@Preview(name:)` "
                'carries',
          ),
          const ActionParameter(
            'file',
            'File',
            required: false,
            description:
                'Package-relative path to write. Defaults to a snake_cased '
                "`.dart` file under the package's preview directory. Never "
                'overwrites.',
          ),
        ],
      ),
      PluginAction(
        'check',
        'Check',
        returns: CatalogCheckResult,
        description:
            'Which entries the compiler can build, and the diagnostics for '
            'those it cannot',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; all of them when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
        ],
      ),
      const PluginAction(
        'describe',
        'Describe',
        returns: CatalogEntryDescription,
        description:
            'One entry: what it is, where it is, and the knobs it declares',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            description: 'The id of the entry to describe',
            optionsFrom: 'entries',
          ),
          ActionParameter(
            'knobs',
            'Read the knobs',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Compile the entry and run it to read the knobs it declares — '
                'the names and kinds every other action takes as `--knobs`. '
                'Off by default because it costs a build; without it the '
                'answer is what the scan knows.',
          ),
          ActionParameter(
            'axes',
            'Read the axes',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Run it and read what the shell around it offers — the names '
                'and kinds every other action takes as `--axes`, plus which '
                'shell declared them. Costs a build for the same reason knobs '
                'do: an axis is declared by a shell asking for it while it '
                'builds.',
          ),
        ],
      ),
      PluginAction(
        'screenshot',
        'Screenshot',
        returns: Artifact,
        description: 'Render one entry to a PNG',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            description: 'The id of the entry to render',
            // Points at the `entries` action, not at the report's view: the
            // view stops at 20 and this list does not, so the old pointer sent
            // a caller to a shorter list than the one it was truncating.
            optionsFrom: 'entries',
            options: [
              for (var entry in entries.take(_inlinedOptions))
                ActionOption(entry.id, label: entry.name),
            ],
          ),
          const ActionParameter(
            'output',
            'Output file',
            required: false,
            description: 'Where to write the PNG; a build path when omitted',
          ),
          const ActionParameter(
            'knobs',
            'Knobs',
            required: false,
            description:
                '$_knobsDoc Recorded on the address, so two settings are two '
                'artifacts rather than one file written twice.',
          ),
          ActionParameter(
            'device',
            'Device',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'Render as a device: its screen, its pixel ratio and its safe '
                'areas, so the preview reads the phone from `MediaQuery` rather '
                'than a rectangle. Omitted means the panel. The same value the '
                'GUI writes as `?device=`, so an address captured here reopens '
                'framed the way it was shot.',
            options: [
              for (var id in deviceIds)
                ActionOption(
                  id,
                  label: id == fitDeviceId
                      ? 'Fit'
                      : Devices.all.firstWhere((d) => d.id == id).label,
                ),
            ],
          ),
          // Declared because they change the pixels, and anything that changes
          // the pixels is recorded on the artifact's address.
          const ActionParameter(
            'width',
            'Width',
            kind: ActionParameterKind.integer,
            required: false,
            defaultValue: '$_defaultWidth',
          ),
          const ActionParameter(
            'height',
            'Height',
            kind: ActionParameterKind.integer,
            required: false,
            defaultValue: '$_defaultHeight',
          ),
          const ActionParameter(
            'axes',
            'Axes',
            required: false,
            description: _axesDoc,
          ),
          ActionParameter(
            'debug',
            'Debug switches',
            required: false,
            description: _debugDoc,
            options: [
              for (var flag in debugFlags)
                ActionOption(flag.name, label: flag.description),
            ],
          ),
          const ActionParameter(
            'node',
            'Crop to',
            required: false,
            description:
                'Cut the picture down to one node, by the id `tree` gave. Cut '
                'out of the real frame rather than re-rendered alone, so the '
                'widget is still in its surroundings.',
          ),
          const ActionParameter(
            'annotate',
            'Draw the ids',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Draw a box and its node id over every widget, so a tree read '
                'and a picture of it can be laid side by side',
          ),
        ],
      ),
      PluginAction(
        'inspect',
        'Inspect',
        returns: CatalogInspectResult,
        description:
            'One rendered build, and whatever you ask about it — whether it '
            'renders, its widget tree, the nodes matching a query, what is '
            'under a point, what it printed, a picture. With no flags it '
            'answers the only question worth asking first: did it render '
            'without the framework complaining. Everything heavier is opt-in, '
            'and every flag you add is answered off the **same** frame rather '
            'than costing another compile-and-render.',
        parameters: [
          ActionParameter(
            'entry',
            'Entry',
            kind: ActionParameterKind.choice,
            description: 'The id of the entry to inspect',
            optionsFrom: 'entries',
          ),
          ActionParameter(
            'tree',
            'Widget tree',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Report the widget tree, scoped to the preview rather than the '
                'catalog around it. Off by default because a real preview is '
                'thousands of tokens of tree — try `find` first.',
          ),
          ActionParameter(
            'find',
            'Find',
            required: false,
            description:
                'Report only the nodes matching this, case-insensitively '
                "against each node's type and against the words it puts on "
                'screen — `ElevatedButton`, `Save`, `SizedBox`. What you want '
                'instead of `tree` when the question is "where is the submit '
                'button".',
          ),
          ActionParameter(
            'at',
            'At a point',
            required: false,
            description:
                'Report the widgets under this point as `x,y`, outermost '
                'first — the chain, because the thing under a cursor is '
                'usually a Text and the thing you meant is the button around '
                'it. In the same coordinates a screenshot is taken in, so a '
                'point read off one lands here without a transform.',
          ),
          ActionParameter(
            'errors',
            'What it reported',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'true',
            description:
                'Report build failures and layout overflows. On by default, '
                'and with no other flag it is the whole answer. `check` says '
                'whether an entry *compiles*, which is a different question.',
          ),
          ActionParameter(
            'logs',
            'What it printed',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Report what the preview printed while it built and painted. '
                'Attached to an open session this is everything it has printed '
                'since the person opened it, including whatever their clicking '
                'caused — output no fresh render can produce.',
          ),
          ActionParameter(
            'node',
            'Subtree',
            required: false,
            description:
                'Narrow `tree` to this node and below, and crop `screenshot` '
                'to it, by the id a previous read gave. Ids come from tree '
                'shape, so one taken in another process still names this node.',
          ),
          ActionParameter(
            'depth',
            'Depth',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'Stop `tree` this many levels below its root',
          ),
          ActionParameter(
            'screenshot',
            'Screenshot',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Write a PNG of the same frame everything else is reported '
                'from, and hand back an artifact for it — the path, and the '
                'address recording everything that changed the pixels, so two '
                'settings are two artifacts rather than one file written '
                'twice. Give `output` to choose where. **Forces a fresh '
                'render**: a picture has to come from a frame this call '
                'composited, and an attached session only offers a VM service.',
          ),
          ActionParameter(
            'output',
            'Output file',
            required: false,
            description:
                'Where to write the PNG; a build path derived from the address '
                'when omitted, the same as `screenshot` uses',
          ),
          ActionParameter(
            'annotate',
            'Annotate',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description:
                'Draw a box and its node id over every widget of the '
                'screenshot. Now genuinely the same tree as the one reported '
                'rather than a second reading that happened to agree, which '
                'was the point of having it.',
          ),
          ActionParameter(
            'device',
            'Device',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'Render as a device: its screen, its pixel ratio and its safe '
                'areas, so the preview reads the phone from `MediaQuery` rather '
                'than a rectangle. Omitted means the panel. **This is what '
                'makes "why does it look wrong on a phone" one render**: the '
                'tree, the constraints and the picture all describe the same '
                'framed build. Forces a render, like any other change to what '
                'is drawn.',
            options: [
              for (var id in deviceIds)
                ActionOption(
                  id,
                  label: id == fitDeviceId
                      ? 'Fit'
                      : Devices.all.firstWhere((d) => d.id == id).label,
                ),
            ],
          ),
          const ActionParameter(
            'width',
            'Width',
            kind: ActionParameterKind.integer,
            required: false,
            description:
                'Override the viewport width — how to ask for a size no device '
                'has, and on a device it stretches the screen rather than '
                'dropping its ratio and its notch',
          ),
          ActionParameter(
            'height',
            'Height',
            kind: ActionParameterKind.integer,
            required: false,
            description: 'See width',
          ),
          ActionParameter(
            'knobs',
            'Knobs',
            required: false,
            description:
                '$_knobsDoc A tree is of one build, and a knob can change '
                'which widgets there are.',
          ),
          ActionParameter(
            'axes',
            'Axes',
            required: false,
            description: _axesDoc,
          ),
          ActionParameter(
            'debug',
            'Debug switches',
            required: false,
            description: _debugDoc,
          ),
          ActionParameter(
            'live',
            'Read what is open',
            kind: ActionParameterKind.boolean,
            required: false,
            defaultValue: 'false',
            description: _liveDoc,
          ),
        ],
      ),
      PluginAction(
        'audit',
        'Audit every entry',
        returns: CatalogAuditResult,
        description:
            'Render the whole catalog and report everything that does not '
            'compile or does not render — one warm guest, one answer for the '
            'repo',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description: 'Which declared package; all of them when omitted',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
          const ActionParameter(
            'path',
            'Narrow to',
            required: false,
            description:
                'A directory or one file — `demo/settings`, '
                '`demo/settings/tile.dart`. Either package-relative or '
                'worktree-relative; both are accepted because an entry id is '
                'the first and a shell tab-completes the second.',
          ),
        ],
      ),
      PluginAction(
        webBuildActionId,
        'Build a web page',
        returns: CatalogWebBuildResult,
        description:
            'Compile the whole catalog into a browsable page — the previews '
            'themselves running in a browser, with their knobs, not pictures '
            'of them. Needs the package to have web enabled; says so, with the '
            'command, when it does not.',
        parameters: [
          ActionParameter(
            'package',
            'Package',
            kind: ActionParameterKind.choice,
            required: false,
            description:
                'Which declared package; the only one when there is one',
            options: [
              for (var path in packages)
                ActionOption(path, label: path == '.' ? 'root' : path),
            ],
          ),
          const ActionParameter(
            'output',
            'Write to',
            required: false,
            description:
                'Where the page goes. Package-relative unless absolute; '
                'defaults to `build/catalog/web`.',
          ),
          const ActionParameter(
            'base-href',
            'Base href',
            required: false,
            description:
                'What `flutter build web --base-href` takes, for serving the '
                'page from a subdirectory rather than the root of a host. Must '
                'begin and end with a slash — `/catalog/`.',
          ),
        ],
      ),
    ],
    view: _view,
  );

  /// Deliberately silent at rest. An entry count is not news — it cannot even
  /// be known until something asks for a scan — and a row that fills in a
  /// number the moment you look at it is worse than an empty one.
  Status get _status {
    if (packages.isEmpty) return const Status.warn('no packages declared');
    if (_failures.isNotEmpty) {
      return Status.error('${_failures.length} failed to scan');
    }
    for (var path in packages) {
      if (busyStatusFor?.call(path) case var busy?) return busy;
    }
    if (isScanning) return const Status.info('scanning…');
    if (_scans.isEmpty) return Status.none;

    // Discovery refuses on a duplicate id or an uncallable target, so the
    // catalog is not usable; staying quiet would be a lie.
    var broken = _scans.values.where((scan) => !scan.ok).length;
    if (broken > 0) {
      return Status.error(
        '$broken ${broken == 1 ? 'package' : 'packages'} failed discovery',
      );
    }
    // Names the directory rather than the fact. "no entries" sent a reader
    // looking for a setting; "no entries in demo/" *is* the setting.
    if (entries.isEmpty) {
      var only = packages.length == 1 ? packages.single : null;
      return Status.warn(
        only == null ? 'no entries' : 'no entries in ${rootFor(only)}/',
      );
    }
    var warnings = _scans.values.fold(
      0,
      (sum, scan) => sum + scan.diagnostics.length,
    );
    return warnings == 0
        ? Status.none
        : Status.warn('$warnings ${warnings == 1 ? 'warning' : 'warnings'}');
  }

  Status _packageStatus(String path) {
    if (_failures[path] case var failure?) return Status.error(failure);
    if (busyStatusFor?.call(path) case var busy?) return busy;
    if (_scanning.contains(path)) return const Status.info('scanning…');
    var scan = _scans[path];
    if (scan == null) return Status.none;
    if (!scan.ok) return const Status.error('discovery failed');
    return switch (setupFor(path)) {
      // A directory that is not there is a typo in `directory:` far more often
      // than it is an intention, so it is worth a different word from "empty".
      CatalogSetup.missing => Status.warn('no ${rootFor(path)}/ directory'),
      CatalogSetup.empty => Status.warn('no entries in ${rootFor(path)}/'),
      _ => Status.none,
    };
  }

  PluginView get _view {
    var nodes = <ViewNode>[];
    for (var path in packages) {
      if (_failures[path] case var failure?) {
        nodes.add(ViewSection(path, [ViewText(failure, tone: Tone.error)]));
        continue;
      }
      var scan = _scans[path];
      if (scan == null) {
        // Honest: nothing has asked for this package, so nothing was scanned.
        // That is not the same as "no entries".
        nodes.add(
          ViewSection(path == '.' ? 'root' : path, const [
            ViewText('not computed'),
          ]),
        );
        continue;
      }

      // The one moment the reader is certainly asking "so how do I write one" —
      // the same rule the scenarios list follows, and the same hint text.
      //
      // **The diagnostics come first, and skipping them was a real hole.** Zero
      // entries does not mean nobody wrote one: an annotation on a function with
      // a required parameter, or on a non-static member, is rejected *with a
      // diagnostic* and produces no entry. Dropping them told somebody who had
      // just written a demo that they had none, and offered to teach them how —
      // while the sidebar said "failed discovery" from the same scan.
      if (scan.entries.isEmpty) {
        nodes.add(
          ViewSection(path == '.' ? 'root' : path, [
            ViewText(
              catalogEmptyReason(
                directory: rootFor(path),
                directoryExists: setupFor(path) != CatalogSetup.missing,
                package: packages.length == 1 ? null : path,
              ),
              tone: Tone.warn,
            ),
            if (scan.diagnostics.isNotEmpty)
              ViewSection('Diagnostics', [
                for (var diagnostic in scan.diagnostics)
                  ViewText(
                    '$diagnostic',
                    tone: diagnostic.isError ? Tone.error : Tone.warn,
                  ),
              ]),
            ViewText(catalogAuthoringHint(rootFor(path))),
          ]),
        );
        continue;
      }

      var children = <ViewNode>[
        ViewItems([
          for (var entry in scan.entries.take(_projectedEntries))
            ViewItem(
              entry.group == null
                  ? entry.name
                  : '${entry.group} / ${entry.name}',
              detail: entry.id,
              // The same address the screenshot action and an artifact carry —
              // built here rather than left to a reader to reassemble from the
              // package and the id, which is how two surfaces come to disagree
              // about what an entry is called.
              address: addressFor(path, entry.id),
            ),
        ], truncated: scan.entries.length - _projectedEntries),
        if (scan.diagnostics.isNotEmpty)
          ViewSection('Diagnostics', [
            for (var diagnostic in scan.diagnostics)
              ViewText(
                '$diagnostic',
                tone: diagnostic.isError ? Tone.error : Tone.warn,
              ),
          ]),
      ];
      nodes.add(ViewSection(path == '.' ? 'root' : path, children));
    }
    return PluginView(nodes);
  }

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    switch (actionId) {
      case 'entries':
        return _entries(arguments);
      case 'new':
        return newPreview(
          package: arguments['package'] as String?,
          name: arguments['name'],
          file: arguments['file'],
        );
      case 'check':
        return _check(arguments);
      case 'describe':
        return _describe(arguments);
      case 'screenshot':
        return _screenshot(arguments);
      case 'inspect':
        return _inspect(arguments);
      case 'audit':
        return _audit(arguments);
      case webBuildActionId:
        return _buildWeb(arguments);
      default:
        return super.invoke(actionId, arguments: arguments);
    }
  }

  /// Every entry, in scan order, with the address that identifies each one.
  ///
  /// **Scans if nothing has.** A report may never start work; an action asked
  /// for by name may, and here must — `fw` and MCP open a session per request
  /// and hold nothing between them, so a query that only read the cache would
  /// answer "no entries" every time.
  ///
  /// The whole list, deliberately: the report's view stops at 20 entries and
  /// the screenshot action inlines at most 50 options, both of which are right
  /// for a projection meant to be read and wrong for the question "what can I
  /// screenshot".
  Future<CatalogEntriesResult> _entries(Map<String, Object?> arguments) async {
    var paths = _requestedPackages(arguments);

    // Always re-scans rather than answering from the cache. A scan is ~38ms
    // against a ~700ms process start, and the alternative is a `--refresh`
    // flag whose unset behaviour would be "possibly stale, no way to tell" —
    // which is not a useful thing to offer someone asking what exists.
    await Future.wait([for (var path in paths) _scan(path)]);

    return CatalogEntriesResult(
      packages: [for (var path in paths) _packageEntries(path)],
    );
  }

  /// Writes the first demo — the file, and the directory if it is not there.
  ///
  /// Public because the panel's empty state offers it as a button: somebody who
  /// is already looking at the GUI should not be sent to a terminal to get
  /// their first file. Both routes land here, so the file they get is the same
  /// file.
  Future<CatalogNewResult> newPreview({
    String? package,
    Object? name,
    Object? file,
  }) async {
    var path = _requireOnePackage(package);

    if (name is! String || name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', "required — the demo's name");
    }
    name = name.trim();

    if (file != null && file is! String) {
      throw ArgumentError.value(
        file,
        'file',
        'must be a package-relative path',
      );
    }
    var relative =
        (file as String?) ??
        '${authoringDirectoryFor(path)}/${catalogFileName(name)}';
    // Inside the package, always: the scan only looks under the declared
    // directory, so a file written outside it is a file nothing will ever find.
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      throw ArgumentError.value(
        relative,
        'file',
        'must be relative to the package and stay inside it',
      );
    }
    if (!relative.endsWith('.dart')) {
      throw ArgumentError.value(relative, 'file', 'must end in `.dart`');
    }
    // Under the scanned directory, which is the check the two above only looked
    // like. Discovery walks `rootFor(path)` and nothing else, so a file written
    // beside it compiles, is never found, and leaves this call handing back an
    // id and a `next` command for an entry that does not exist.
    var root = rootFor(path);
    if (!_isAtOrUnder(relative, root)) {
      throw ArgumentError.value(
        relative,
        'file',
        'must be under $root/, the only directory this package is scanned for '
            'demos. A file outside it would never be found. Change the '
            r'directory itself with `Previews(packages: [.new(app, '
            r"directory: '...')])` in tool/flutterware.dart.",
      );
    }

    var target = File(p.join(host.worktree.path, path, relative));
    if (target.existsSync()) {
      throw ArgumentError.value(
        relative,
        'file',
        'already exists. Add the preview to it, or name another file.',
      );
    }
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(catalogScaffold(name));

    // The scan is now stale by exactly this file — and, when this was the first
    // demo, by the whole question of whether the package has any.
    _scans.remove(path);
    _failures.remove(path);
    await _scan(path);

    var id = '$relative#${catalogSymbolName(name)}';
    return CatalogNewResult(
      package: path,
      file: relative,
      name: name,
      id: id,
      next: "fw run previews screenshot --entry='$id'",
    );
  }

  /// Compiles one package's catalog into a browsable page.
  ///
  /// Unlike every other action here this runs no daemon and no guest: a page is
  /// the previews themselves, compiled for a browser, not pictures of them. What
  /// it needs from this class is only the scan — which entries there are — and
  /// which package they belong to.
  ///
  /// [onOutput] is how a caller follows a build that takes tens of seconds; the
  /// CLI hands it straight to its own printer and the GUI to a dialog.
  Future<CatalogWebBuildResult> buildWeb({
    String? package,
    String? output,
    String? baseHref,
    void Function(String line)? onOutput,
  }) async {
    var packagePath = _requireOnePackage(package);
    await _scan(packagePath);
    if (_failures[packagePath] case var failure?) {
      throw StateError('$packagePath could not be scanned: $failure');
    }

    // One at a time per package. Two builds share a generated source directory,
    // and `WebAppGenerator.generate` deletes it recursively before writing — so
    // a second build started while the first is compiling pulls the first's
    // sources out from under it, and the first fails pointing at files that no
    // longer exist.
    if (_builds.containsKey(packagePath)) {
      throw StateError(
        'A web build is already running for $packagePath. Wait for it, or '
        'close the worktree to stop it.',
      );
    }

    var packageRoot = p.join(host.worktree.path, packagePath);
    var builder = _builds[packagePath] = WebCatalogBuilder(
      flutterExecutable: host.workspace.flutterSdk.flutter,
      packageRoot: packageRoot,
      // The package rather than the plugin: a page says what it is a catalog
      // *of*, and "Previews" on a repo with three of them says nothing.
      title: packagePath == '.' ? host.worktree.name : packagePath,
    );
    WebCatalogBuild built;
    try {
      built = await builder.build(
        entries: _scans[packagePath]?.entries ?? const [],
        output: output,
        baseHref: baseHref,
        onOutput: onOutput,
      );
    } finally {
      _builds.remove(packagePath);
    }

    return CatalogWebBuildResult(
      package: packagePath,
      output: _shortened(built.output),
      indexHtml: _shortened(built.indexHtml),
      entries: built.entryCount,
      durationMs: built.duration.inMilliseconds,
    );
  }

  Future<CatalogWebBuildResult> _buildWeb(Map<String, Object?> arguments) {
    String? text(String name) {
      var value = arguments[name];
      if (value == null) return null;
      if (value is! String) {
        throw ArgumentError.value(value, name, 'must be a string');
      }
      return value.isEmpty ? null : value;
    }

    var baseHref = text('base-href');
    // Checked here rather than left to the tool, which fails after the whole
    // compile with a message about a value this action accepted.
    if (baseHref != null &&
        (!baseHref.startsWith('/') || !baseHref.endsWith('/'))) {
      throw ArgumentError.value(
        baseHref,
        'base-href',
        'must begin and end with a slash — `/catalog/`',
      );
    }

    return buildWeb(
      package: text('package'),
      output: text('output'),
      baseHref: baseHref,
    );
  }

  /// The one package an action can act on, which is not the same question
  /// [_requestedPackages] answers.
  ///
  /// A build writes one page from one package's demos. Defaulting to "all of
  /// them" would either concatenate catalogues that are deliberately separate
  /// or silently build the first — so a repo with several is asked, once,
  /// rather than guessed at.
  String _requireOnePackage(String? requested) {
    if (requested != null) {
      if (!packages.contains(requested)) {
        throw ArgumentError.value(
          requested,
          'package',
          'not declared for this plugin. Declared: ${packages.join(', ')}',
        );
      }
      return requested;
    }
    if (packages.length == 1) return packages.single;
    if (packages.isEmpty) {
      throw StateError('No packages are declared for Previews.');
    }
    throw ArgumentError.value(
      null,
      'package',
      'this plugin has more than one package, so a build has to say which: '
          '${packages.join(', ')}',
    );
  }

  /// Worktree-relative where it is inside the worktree, so the value survives
  /// being read on another machine — the same rule [Artifact.path] follows.
  String _shortened(String path) => p.isWithin(host.worktree.path, path)
      ? p.relative(path, from: host.worktree.path)
      : path;

  /// Which packages an action was pointed at: the named one, or all declared.
  List<String> _requestedPackages(Map<String, Object?> arguments) {
    var requested = arguments['package'];
    if (requested != null && requested is! String) {
      throw ArgumentError.value(requested, 'package', 'must be a package path');
    }
    var paths = requested == null ? packages : [requested as String];
    for (var path in paths) {
      if (!packages.contains(path)) {
        throw ArgumentError.value(
          path,
          'package',
          'not declared for this plugin. Declared: ${packages.join(', ')}',
        );
      }
    }
    return paths;
  }

  CatalogPackageEntries _packageEntries(String path) {
    if (_failures[path] case var failure?) {
      return CatalogPackageEntries(
        path: path,
        directory: rootFor(path),
        error: failure,
      );
    }
    var scan = _scans[path];
    return CatalogPackageEntries(
      path: path,
      directory: rootFor(path),
      authoring: scan == null || scan.entries.isNotEmpty
          ? null
          : '${catalogEmptyReason(directory: rootFor(path), directoryExists: setupFor(path) != CatalogSetup.missing, package: path)}\n\n'
                '${catalogAuthoringHint(rootFor(path))}',
      entries: [
        for (var entry in scan?.entries ?? const <CatalogEntry>[])
          CatalogEntrySummary(
            id: entry.id,
            name: entry.name,
            group: entry.group,
            // What every other surface identifies this by — hand it straight
            // back to `screenshot`, or later to `show`.
            address: '${addressFor(path, entry.id)}',
          ),
      ],
      diagnostics: [
        for (var diagnostic in scan?.diagnostics ?? const []) '$diagnostic',
      ],
    );
  }

  /// Which entries the compiler can build, per package.
  ///
  /// The one question the scan cannot answer: it parses a file and finds an
  /// entry, but whether that entry *compiles* is a fact only the compiler
  /// holds. Until now only the panel could ask, because only the panel ran a
  /// daemon.
  ///
  /// One daemon at a time rather than all at once: each package's daemon may
  /// have to build a host binary, and two cold builds racing helps nobody. A
  /// package that cannot be checked reports why in its own row instead of
  /// sinking the others.
  Future<CatalogCheckResult> _check(Map<String, Object?> arguments) async {
    var results = <CatalogPackageCheck>[];
    for (var path in _requestedPackages(arguments)) {
      try {
        var checked = await _headlessFor(path).check();
        results.add(
          CatalogPackageCheck(
            path: path,
            ok: checked.ok,
            servable: [for (var entry in checked.servable) entry.id],
            broken: [
              for (var broken in checked.quarantined)
                CatalogBrokenEntry(id: broken.entry.id, error: broken.error),
            ],
          ),
        );
      } catch (e) {
        results.add(CatalogPackageCheck(path: path, error: '$e'));
      }
    }
    return CatalogCheckResult(packages: results);
  }

  /// Everything known about one entry.
  ///
  /// The scan half is free. The knobs are not: a demo declares them by *asking*
  /// for them while it builds, so the only way to know is to compile it and run
  /// it — which is why `knobs` is opt-in and off by default. An agent deciding
  /// what to vary before a screenshot wants it; an agent listing entries does
  /// not.
  Future<CatalogEntryDescription> _describe(
    Map<String, Object?> arguments,
  ) async {
    var entryId = arguments['entry'];
    if (entryId is! String || entryId.isEmpty) {
      throw ArgumentError.value(entryId, 'entry', 'required');
    }
    if (_scans.isEmpty && _failures.isEmpty) await computeAll();

    var packagePath = _packageHolding(entryId);
    var entry = _scans[packagePath]!.entries.firstWhere((e) => e.id == entryId);

    CatalogEntryDescription describe({
      List<CatalogKnob>? knobs,
      List<CatalogKnob>? axes,
      String? shell,
    }) => CatalogEntryDescription(
      id: entry.id,
      name: entry.name,
      group: entry.group,
      package: packagePath,
      file: entry.path,
      symbol: entry.symbol,
      annotation: entry.annotation,
      address: '${addressFor(packagePath, entryId)}',
      knobs: knobs,
      axes: axes,
      shell: shell,
    );

    var wantsKnobs = arguments['knobs'] == true;
    var wantsAxes = arguments['axes'] == true;
    if (!wantsKnobs && !wantsAxes) return describe();

    // One guest for both when both are asked for: each costs a compile and a
    // frame, and running the pipeline twice to answer two questions about the
    // same build is the cost with none of the benefit.
    var headless = _headlessFor(packagePath);
    var axisReport = wantsAxes
        ? await headless.axes(entryId: entryId)
        : AxisReport.empty;
    if (!wantsKnobs) {
      return describe(
        axes: [for (var axis in axisReport.axes) _asKnob(axis)],
        shell: axisReport.shellId,
      );
    }

    var report = await headless.knobs(entryId: entryId);
    // An entry that declares none answers with an empty list: "it has no
    // knobs" and "we did not look" are different questions, and only one of
    // them was asked. Which is why the field is nullable and this is a list.
    return describe(
      knobs: [for (var knob in report.knobs) _asKnob(knob)],
      axes: wantsAxes
          ? [for (var axis in axisReport.axes) _asKnob(axis)]
          : null,
      shell: axisReport.shellId,
    );
  }

  /// Every entry in every requested package, compiled and rendered.
  Future<CatalogAuditResult> _audit(Map<String, Object?> arguments) async {
    var paths = _requestedPackages(arguments);
    await Future.wait([for (var path in paths) _scan(path)]);

    var narrowTo = arguments['path'];
    if (narrowTo != null && narrowTo is! String) {
      throw ArgumentError.value(narrowTo, 'path', 'must be a path');
    }

    // Resolved before anything is compiled, so a typo costs no build. An empty
    // match is refused rather than audited: `checked: 0, broken: 0` is what a
    // clean run looks like, and a flag that silently matched nothing would
    // report a repo green on the strength of a misspelling.
    Map<String, List<String>>? selected;
    if (narrowTo is String) {
      selected = {for (var path in paths) path: _entryIdsUnder(path, narrowTo)};
      if (selected.values.every((ids) => ids.isEmpty)) {
        throw ArgumentError.value(
          narrowTo,
          'path',
          'matches no entry in ${paths.join(', ')}. Ask `entries` what there '
              'is; a path names a directory or a file, not an entry id.',
        );
      }
    }

    var checked = 0;
    var rows = <CatalogAuditEntry>[];
    var unreachable = <CatalogAuditFailure>[];
    // One package at a time: each may build a host binary, and two cold builds
    // racing helps nobody. The same reason `check` gives.
    for (var path in paths) {
      var only = selected?[path];
      // Nothing under this package matched, and another package's did — so
      // there is nothing to do here rather than everything.
      if (only != null && only.isEmpty) continue;
      CatalogAudit audit;
      try {
        audit = await _headlessFor(path).auditAll(entryIds: only);
      } catch (e) {
        // Per package, exactly as `check` does it: one package that cannot
        // host a daemon must not decide the answer for the others.
        unreachable.add(CatalogAuditFailure(package: path, error: '$e'));
        continue;
      }
      checked += audit.entries.length + audit.quarantined.length;

      for (var broken in audit.quarantined) {
        rows.add(
          CatalogAuditEntry(
            id: broken.entry.id,
            address: '${addressFor(path, broken.entry.id)}',
            compiles: false,
            compileError: broken.error,
          ),
        );
      }
      for (var entry in audit.entries) {
        var report = audit.rendered[entry.id];
        if (report == null || report.isEmpty) continue;
        rows.add(
          CatalogAuditEntry(
            id: entry.id,
            address: '${addressFor(path, entry.id)}',
            compiles: true,
            errors: [for (var e in report.errors) _asRenderError(e)],
          ),
        );
      }
    }

    return CatalogAuditResult(
      checked: checked,
      broken: rows.length,
      entries: rows,
      unreachable: unreachable,
    );
  }

  /// The ids in [packagePath] whose file sits at or under [narrowTo].
  ///
  /// An entry id is `<package-relative file>#<symbol>`, so narrowing to a
  /// directory or a file is a prefix test on the part before the `#`. Matched
  /// on whole segments — `demo/set` must not select `demo/settings/` — and
  /// tolerant of a worktree-relative path, since `app/demo/x.dart` is what a
  /// shell completes and `demo/x.dart` is what the id says.
  List<String> _entryIdsUnder(String packagePath, String narrowTo) {
    var wanted = p.normalize(narrowTo);
    var prefix = packagePath == '.' ? '' : '$packagePath/';
    if (prefix.isNotEmpty && wanted.startsWith(prefix)) {
      wanted = wanted.substring(prefix.length);
    }
    return [
      for (var entry in _scans[packagePath]?.entries ?? const <CatalogEntry>[])
        if (_isAtOrUnder(entry.path, wanted)) entry.id,
    ];
  }

  static bool _isAtOrUnder(String file, String directoryOrFile) {
    var target = p.normalize(directoryOrFile);
    if (target == '.' || target.isEmpty) return true;
    var normalized = p.normalize(file);
    return normalized == target || p.isWithin(target, normalized);
  }

  static CatalogRenderError _asRenderError(InspectError error) =>
      CatalogRenderError(
        exception: error.exception,
        library: error.library,
        context: error.context,
        count: error.count,
      );

  /// A declared control, flattened for the wire. Axes are [KnobDescriptor]s
  /// too — the same kind of thing with a different lifetime — so they flatten
  /// through here as well.
  static CatalogKnob _asKnob(KnobDescriptor knob) => CatalogKnob(
    name: knob.name,
    kind: knob.kind.name,
    value: knob.value,
    defaultValue: knob.defaultValue,
    min: knob.min,
    max: knob.max,
    options: knob.options,
  );

  /// Which declared package holds [entryId].
  String _packageHolding(String entryId) => packages.firstWhere(
    (path) => _scans[path]?.entries.any((e) => e.id == entryId) ?? false,
    orElse: () => throw ArgumentError.value(
      entryId,
      'entry',
      'no entry with that id. Known: '
          '${entries.map((e) => e.id).take(10).join(', ')}'
          '${entries.length > 10 ? ', …' : ''}',
    ),
  );

  /// One rendered build, and every projection of it that was asked for.
  ///
  /// **This replaced `tree`, `find`, `at` and `errors`, and the argument was
  /// never mainly about tidiness.** They had the same inputs, the same
  /// precondition — the entry must be rendered first — and each paid a full
  /// compile, guest launch and render to answer one question about a frame the
  /// others also had to produce. Three questions was three renders. For an
  /// agent in a UI edit loop that is the dominant per-iteration cost, and a
  /// sixth (`logs`) and a seventh (`semantics`) were queued up to be added to
  /// the list by reflex.
  ///
  /// The second argument is consistency, and it is the deciding one.
  /// `screenshot --annotate` read its **own** tree, so a caller that ran `tree`
  /// and then `screenshot --annotate` got two trees out of two processes: the
  /// ids on the picture matched the ids in the tree because the build is
  /// deterministic, not because they were the same object. Closing that loop
  /// was the entire point of `--annotate`. Now one render produces one tree and
  /// every projection comes off it, and the assumption is gone rather than
  /// merely reliable.
  ///
  /// **No flags is the "is it OK" answer** — render, report what the framework
  /// said, nothing else. Everything heavier is opt-in, which is what the token
  /// measurements in the prior design already concluded: summary always,
  /// details on request, `find` before `tree`.
  Future<CatalogInspectResult> _inspect(Map<String, Object?> arguments) async {
    // Read and checked before anything is scanned or compiled. A typo in a flag
    // should cost nothing, and a compile-and-render is the most expensive thing
    // here.
    var want = _InspectRequest.of(arguments);
    if (_scans.isEmpty && _failures.isEmpty) await computeAll();
    var packagePath = _packageHolding(want.entryId);

    var address = _pixelAddress(
      packagePath: packagePath,
      entryId: want.entryId,
      deviceId: want.deviceId,
      viewport: want.viewport,
      knobs: want.knobs,
      axes: want.axes,
      debug: want.debug,
      node: want.node,
      annotate: want.annotate,
    );

    var observed = await _observe(want, packagePath, address);
    return _project(want, observed.$1, live: observed.$2, address: address);
  }

  /// Reads the entry, from the session a person is driving when they asked for
  /// that and it is showing this entry, and from a guest of its own otherwise.
  Future<(CatalogObservation, bool)> _observe(
    _InspectRequest want,
    String packagePath,
    Address address,
  ) async {
    var open = await _withLiveGuest(
      packagePath,
      want.entryId,
      live: want.mayAttach,
      body: (inspect, tree) async => CatalogObservation(
        // Handed over rather than read again: `_withLiveGuest` reads it to
        // decide the session is showing this entry at all, and a second read
        // would be a second build's worth of truth.
        tree: tree,
        errors: await inspect.errors(want.entryId) ?? InspectErrors.empty,
        logs: want.logs ? await inspect.logs(want.entryId) : null,
        hits: want.at == null
            ? null
            : await inspect.hitTest(
                want.at!.$1.toDouble(),
                want.at!.$2.toDouble(),
              ),
      ),
    );
    if (open != null) return (open, true);

    return (
      await _headlessFor(packagePath).observe(
        entryId: want.entryId,
        viewport: want.viewport,
        knobs: want.knobs,
        axes: want.axes,
        debug: want.debug,
        // The tree is read whenever anything needs it — a query, a hit, a crop,
        // an annotation — and `observe` works that out for itself rather than
        // being told twice.
        wantTree: want.tree || want.query != null,
        wantLogs: want.logs,
        at: want.at == null
            ? null
            : (want.at!.$1.toDouble(), want.at!.$2.toDouble()),
        screenshot: want.picture
            ? _outputFor(want, packagePath, address)
            : null,
        annotate: want.annotate,
        cropNode: want.node,
      ),
      false,
    );
  }

  /// Where the PNG goes: what was asked for, or a path derived from the address.
  ///
  /// Derived exactly as `screenshot` derives it, so asking twice with the same
  /// flags overwrites one file and asking with different flags does not.
  String _outputFor(
    _InspectRequest want,
    String packagePath,
    Address address,
  ) => switch (want.output) {
    var given? when given.isNotEmpty =>
      p.isAbsolute(given) ? given : p.join(host.worktree.path, given),
    _ => p.join(
      host.worktree.path,
      packagePath,
      'build',
      'catalog',
      'screenshots',
      _defaultFileName(address),
    ),
  };

  /// One observation, projected into whatever was asked about it.
  CatalogInspectResult _project(
    _InspectRequest want,
    CatalogObservation observed, {
    required bool live,
    required Address address,
  }) {
    var tree = observed.tree;
    return CatalogInspectResult(
      entry: want.entryId,
      address: '$address',
      readFrom: live ? 'live' : 'render',
      ok: observed.errors.isEmpty,
      // `ok` is answered whatever else was asked, so the list that explains it
      // is too — a caller told `ok: false` with no list has been told nothing it
      // can act on. Suppressed only when explicitly switched off.
      errors: want.errors
          ? [for (var error in observed.errors.errors) _asRenderError(error)]
          : const [],
      tree: want.tree && tree != null
          ? _asNodes(_scoped(tree, want.node, want.depth, want.entryId))
          : null,
      matches: want.query == null || tree == null
          ? null
          : _asNodes(_matching(tree, want.query!)),
      // Present-and-empty when the point missed, which is an answer: there is
      // nothing of the demo's there. A caller that probed outside the viewport
      // wants to see that it missed rather than that it did not ask.
      at: observed.hits == null
          ? null
          : _asNodes([for (var id in observed.hits!) ?tree?.nodeAt(id)]),
      logs: switch (observed.logs) {
        var report? => [for (var line in report.lines) line.text],
        null => null,
      },
      logsDropped: switch (observed.logs) {
        InspectLogs(dropped: var n) when n > 0 => n,
        _ => null,
      },
      // **An artifact, not a path.** `screenshot` has always handed back one,
      // and a picture produced here is the same kind of thing: it has an
      // identity, and something downstream will want to file it. Handing back a
      // bare string would have made this the one place in the surface where a
      // PNG is less than an artifact.
      screenshot: switch (observed.screenshot) {
        var file? => Artifact(
          kind: Artifact.png,
          address: address,
          // Worktree-relative, so the value survives being read on another
          // machine and an agent whose tools are scoped to the repo can open it.
          path: p.relative(file.path, from: host.worktree.path),
        ),
        null => null,
      },
    );
  }

  /// The nodes whose type or on-screen words contain [query].
  ///
  /// [query] is folded once. The first version lowercased it twice per node,
  /// which on the largest tree here is seventeen hundred throwaway strings to
  /// answer one question.
  static List<InspectNode> _matching(InspectTree tree, String query) {
    var needle = query.toLowerCase();
    return [
      for (var node in tree.nodes)
        if (node.type.toLowerCase().contains(needle) ||
            (node.description?.toLowerCase().contains(needle) ?? false))
          node,
    ];
  }

  /// `tree` narrowed by `--node` and `--depth`.
  ///
  /// The depth is counted from the *reported* root rather than from the demo's,
  /// so `--node=0/1 --depth=1` means one level below that node — which is what
  /// anybody asking for both would mean by it.
  List<InspectNode> _scoped(
    InspectTree tree,
    String? node,
    Object? depth,
    String entryId,
  ) {
    var nodes = tree.nodes;
    var offset = 0;
    if (node != null) {
      var subtree = tree.nodeAt(node);
      if (subtree == null) {
        throw ArgumentError.value(
          node,
          'node',
          'no node with that id in $entryId. An id names a position in the '
              'tree, so one from before an edit may no longer name anything — '
              'read the tree again.',
        );
      }
      nodes = InspectTree(entryId: tree.entryId, root: subtree).nodes;
      offset = _depthOf(subtree.id);
    }
    return [
      for (var found in nodes)
        if (switch (depth) {
          int max => _depthOf(found.id) - offset <= max,
          _ => true,
        })
          found,
    ];
  }

  /// `--at=120,300`.
  ///
  /// One parameter rather than the `--x`/`--y` pair it replaced: a point is one
  /// thing, and two required integers that are only meaningful together are two
  /// ways to get it half-wrong.
  static (int, int)? _parsePoint(Object? value) {
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw ArgumentError.value(value, 'at', 'a point, written `x,y`');
    }
    var parts = value.split(',');
    var x = parts.length == 2 ? int.tryParse(parts[0].trim()) : null;
    var y = parts.length == 2 ? int.tryParse(parts[1].trim()) : null;
    if (x == null || y == null) {
      throw ArgumentError.value(
        value,
        'at',
        'a point, written `x,y` — two whole numbers in the coordinates a '
            'screenshot is taken in, as `120,300`',
      );
    }
    return (x, y);
  }

  /// Every node in the reply's shape, layout formatted for a reader.
  List<CatalogTreeNode> _asNodes(List<InspectNode> nodes) {
    // Project-relative, because an absolute URI in a terminal is mostly the
    // same forty characters over and over — and the consumer's file tools are
    // scoped to the worktree anyway.
    var worktree = host.worktree.path;
    return [
      for (var node in nodes)
        CatalogTreeNode(
          id: node.id,
          type: node.type,
          depth: _depthOf(node.id),
          description: node.description,
          source: node.source?.describe(relativeTo: worktree),
          local: node.createdByLocalProject,
          // Formatted here rather than carried as four numbers: the consumer
          // is a terminal or a model, and `12.0,40.0 200.0×48.0` is one
          // glance where four fields are four.
          rect: switch (node.layout) {
            var l? => '${_n(l.x)},${_n(l.y)} ${_n(l.width)}×${_n(l.height)}',
            null => null,
          },
          constraints: node.layout?.constraints?.describe(),
          flex: switch (node.layout?.flex) {
            var f? => [
              f.direction,
              ?f.mainAxisAlignment,
              ?f.crossAxisAlignment,
              ?f.mainAxisSize,
            ].join(', '),
            null => null,
          },
          flexChild: switch (node.layout) {
            InspectLayout(flexFactor: var factor?, :var flexFit) =>
              flexFit == null ? 'flex $factor' : 'flex $factor ($flexFit)',
            _ => null,
          },
        ),
    ];
  }

  /// A node's depth, read off its id — `0/1/2` is three below the root.
  static int _depthOf(String id) => id.isEmpty ? 0 : id.split('/').length;

  /// Layout arrives as doubles and is nearly always whole pixels, so `48` beats
  /// `48.0` and `47.5` still says so.
  static String _n(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);

  /// Whether this call may read the session a person is driving, rather than
  /// rendering its own copy.
  static bool _mayAttach({
    required Object? live,
    required Map<String, String> knobs,
    required Map<String, String> axes,
    required Map<String, String> debug,
    required bool wantsPicture,
    required bool reframed,
  }) =>
      // Opt-in. Reading a window somebody is using answers questions nothing
      // else can, and it makes the same command answer differently depending on
      // whether that window is open — which is the wrong default for CI and for
      // a caller that did not know to look.
      live == true &&
      // Everything below is a refusal even when asked, because each of these
      // would reach past this call's business and change what the person is
      // looking at: knobs and axes are pushed into whichever guest answers, a
      // debug flag changes the guest process, and a different device or size
      // reframes the window. A picture is refused for the opposite reason —
      // there is nothing to take one from, since an attached session offers a VM
      // service and no frames.
      knobs.isEmpty &&
      axes.isEmpty &&
      debug.isEmpty &&
      !wantsPicture &&
      !reframed;

  /// Runs [body] against the guest a person has open, when there is one and it
  /// is **already showing** [entryId].
  ///
  /// Null means "render your own", and every path to it is a deliberate
  /// refusal rather than a failure: [live] is off; nothing is published for
  /// this package; the published handle will not connect, in which case it is
  /// deleted on the way past; or the session is showing a different entry.
  ///
  /// **It never switches the guest**, which is the whole safety property. This
  /// reads what is on screen or it declines — it does not put something on
  /// screen. A person watching their own window sees nothing happen.
  ///
  /// The tree that decided all this is handed to [body] rather than read
  /// again: it is both the liveness check and the answer, and a second read
  /// would be a second build's worth of truth.
  Future<T?> _withLiveGuest<T>(
    String packagePath,
    String entryId, {
    required bool live,
    required Future<T> Function(InspectClient inspect, InspectTree tree) body,
  }) async {
    if (!live) return null;
    var vmService = await attachToLiveSession(
      p.join(host.worktree.path, packagePath),
    );
    if (vmService == null) return null;
    try {
      var inspect = InspectClient(vmService, patience: InspectPatience.glance);
      var tree = await inspect.tree(entryId);
      if (tree == null || tree.root == null) return null;
      return await body(inspect, tree);
    } finally {
      await vmService.close();
    }
  }

  /// The headless pipeline for one declared package.
  ///
  /// The config comes from [DaemonConfig.forPackage] so that this and the GUI's
  /// [CatalogSession] derive the same [DaemonAddress] — which is what makes
  /// `fw` and a panel two drivers of one daemon rather than two daemons.
  HeadlessCatalog _headlessFor(String packagePath) => HeadlessCatalog(
    dartExecutable: p.join(host.workspace.flutterSdk.root, 'bin', 'dart'),
    config: DaemonConfig.forPackage(
      appToolDirectory: host.workspace.appContext.appToolDirectory.path,
      packageRoot: p.join(host.worktree.path, packagePath),
      flutterSdkRoot: host.workspace.flutterSdk.root,
      roots: [rootFor(packagePath)],
      previewAnnotations: previewAnnotationsFor(packagePath),
    ),
  );

  /// Renders one entry to a PNG.
  ///
  /// Runs the whole pipeline headlessly, so the button, `fw` and an agent all
  /// reach the same artifact by the same route.
  ///
  /// Returns an [Artifact] rather than a path: a PNG that cannot say which
  /// entry it is of, at which size, is not reproducible — you cannot ask for
  /// the same picture again from the file alone. The [Address] it carries is
  /// exactly that question's answer.
  ///
  /// Scans on demand when nothing has yet: an agent naming an entry it read
  /// from a previous call should not have to know that the process it is
  /// talking to is a fresh one.
  Future<Artifact> _screenshot(Map<String, Object?> arguments) async {
    var entryId = arguments['entry'];
    if (entryId is! String || entryId.isEmpty) {
      throw ArgumentError.value(entryId, 'entry', 'required');
    }

    if (_scans.isEmpty && _failures.isEmpty) await computeAll();

    var packagePath = _packageHolding(entryId);
    var packageRoot = p.join(host.worktree.path, packagePath);
    var entry = _scans[packagePath]!.entries.firstWhere((e) => e.id == entryId);

    var (deviceId, viewport) = _framing(arguments);

    var knobs = parseKnobs(arguments['knobs']);
    var axes = parseKnobs(arguments['axes']);
    var debug = parseKnobs(arguments['debug']);
    var node = arguments['node'];
    if (node != null && node is! String) {
      throw ArgumentError.value(node, 'node', 'must be a node id');
    }
    var annotate = arguments['annotate'] == true;

    var address = _pixelAddress(
      packagePath: packagePath,
      entryId: entryId,
      deviceId: deviceId,
      viewport: viewport,
      knobs: knobs,
      axes: axes,
      debug: debug,
      node: node as String?,
      annotate: annotate,
    );

    var output =
        arguments['output'] as String? ??
        p.join(
          packageRoot,
          'build',
          'catalog',
          'screenshots',
          _defaultFileName(address),
        );

    var captured = await _headlessFor(packagePath).capture(
      entryId: entryId,
      output: output,
      viewport: viewport,
      knobs: knobs,
      axes: axes,
      debug: debug,
      node: node,
      annotate: annotate,
    );

    return Artifact(
      kind: Artifact.png,
      address: address,
      // Relative to the worktree root, so the value survives being read on
      // another machine — and so an agent whose tools are scoped to the repo
      // can open it.
      path: p.relative(captured.file.path, from: host.worktree.path),
      meta: {
        'name': entry.name,
        'group': ?entry.group,
        'package': packagePath,
        'bytes': captured.file.lengthSync(),
        // What the entry reported after the values landed. A demo may clamp
        // one, and a caller comparing this with what it asked for is the only
        // way to notice.
        if (captured.knobs.isNotEmpty)
          'knobs': {for (var knob in captured.knobs) knob.name: knob.value},
      },
    );
  }

  /// Knob values, however they arrived.
  ///
  /// A map when an agent sent JSON, a string when a shell did — `fw` has no
  /// types to pass and no repeatable flags, so `name=value,name=value` is the
  /// form that survives a command line. A JSON object in that string works
  /// too, since an agent writing one is not wrong to expect it to.
  ///
  /// Values stay strings here: only the guest knows what kind each knob is,
  /// and guessing at this end would make `count=5` an int for one demo and a
  /// string for another.
  static Map<String, String> parseKnobs(Object? value) {
    if (value == null) return const {};
    if (value is Map) {
      return {
        for (var entry in value.entries) '${entry.key}': '${entry.value}',
      };
    }
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError.value(value, 'knobs', 'expected name=value pairs');
    }

    if (value.trimLeft().startsWith('{')) {
      var decoded = jsonDecode(value.trim());
      if (decoded is! Map) {
        throw ArgumentError.value(value, 'knobs', 'expected a JSON object');
      }
      return parseKnobs(decoded);
    }

    // Names are trimmed, values never: `label= x ` sets a string knob to a
    // value with spaces in it, which is a legitimate thing to want to look at.
    // So the argument as a whole is not trimmed either — the trailing space of
    // the last pair belongs to it.
    var knobs = <String, String>{};
    for (var pair in value.split(',')) {
      var equals = pair.indexOf('=');
      if (equals <= 0 || pair.substring(0, equals).trim().isEmpty) {
        throw ArgumentError.value(
          pair,
          'knobs',
          'expected name=value, separated by commas',
        );
      }
      knobs[pair.substring(0, equals).trim()] = pair.substring(equals + 1);
    }
    return knobs;
  }

  static const _defaultWidth = 900;
  static const _defaultHeight = 700;

  /// A file name that differs whenever the address does.
  ///
  /// The axes are in it because they are part of the address: capturing the
  /// same entry at two sizes used to write both to one path, so the second
  /// silently overwrote the first and two different addresses pointed at one
  /// file. An artifact that cannot be told apart from another artifact is not
  /// reproducible, which is the whole reason it carries an address.
  static String _defaultFileName(Address address) {
    var slug = _slug(address.segments.join('_'));
    var axes = address.axes.entries
        .map((axis) => '${_slug(axis.key)}-${_slug(axis.value)}')
        .join('_');
    return axes.isEmpty ? '$slug.png' : '${slug}__$axes.png';
  }

  static String _slug(String value) =>
      value.replaceAll(RegExp('[^A-Za-z0-9]+'), '_');

  /// Accepts an `int` or the string a CLI flag arrives as.
  /// The identity of one **picture**: everything that changed the pixels.
  ///
  /// Shared by `screenshot` and `inspect`, and it has to be. They can now
  /// produce the same PNG from the same flags, and the default output path is
  /// derived from this address — so two builders means the same picture lands in
  /// two filenames. Which is not hypothetical: `inspect` was written with its
  /// own copy and it omitted one of the framing keys, so the two disagreed the
  /// moment both could take a `--device`.
  ///
  /// Recording the size the capture actually *ran* at — rather than only a size
  /// someone asked for — is what lets the same frame be requested again.
  ///
  /// Every family is prefixed. A demo may declare a knob called `width`, and a
  /// shell an axis called `width`; an address where either quietly overwrote the
  /// viewport would name a picture nobody took.
  Address _pixelAddress({
    required String packagePath,
    required String entryId,
    required String? deviceId,
    required CaptureViewport viewport,
    required Map<String, String> knobs,
    required Map<String, String> axes,
    required Map<String, String> debug,
    required String? node,
    required bool annotate,
  }) => addressFor(
    packagePath,
    entryId,
    axes: {
      // The word the GUI reads, so an address that came out of a capture reopens
      // framed the way it was shot. Without it the two surfaces describe the
      // same picture in different vocabularies and the round-trip silently
      // loses the framing.
      'device': ?deviceId,
      'width': '${viewport.width}',
      'height': '${viewport.height}',
      for (var knob in knobs.entries) 'knob.${knob.key}': knob.value,
      for (var axis in axes.entries) 'axis.${axis.key}': axis.value,
      // On the address for the same reason as the rest: a picture taken with the
      // layout guides drawn is not the same picture.
      for (var flag in debug.entries) 'debug.${flag.key}': flag.value,
      // Both change the pixels, so both belong on the identity — a crop of one
      // node and a crop of another are two artifacts, not one file written
      // twice.
      'node': ?node,
      if (annotate) 'annotate': 'true',
    },
  );

  /// How `--device`, `--width` and `--height` become a viewport.
  ///
  /// Shared by `screenshot` and `inspect` so the two cannot disagree about what
  /// `iphone15` means — which they would eventually, being two copies of a table
  /// lookup and a pair of overrides.
  ///
  /// Named rather than defaulted, and refused rather than approximated. A device
  /// this build does not know is the one failure that has to be loud: quietly
  /// framing as the panel produces a PNG that is wrong without looking wrong,
  /// and something downstream files it as evidence.
  static (String?, CaptureViewport) _framing(Map<String, Object?> arguments) {
    var deviceId = arguments['device'];
    if (deviceId != null && (deviceId is! String || !isDeviceId(deviceId))) {
      throw ArgumentError.value(
        deviceId,
        'device',
        'no such device. Accepted: ${deviceIds.join(', ')}',
      );
    }
    // Width and height still win where they are given: they are how you ask for
    // a size no device has, and on a device they stretch its screen rather than
    // dropping its ratio and its notch.
    // `fit` names the panel and resolves to no device, which is the same
    // viewport by a different route.
    var device = deviceId is String ? deviceById(deviceId) : null;
    var viewport = device == null
        ? CaptureViewport.panel
        : CaptureViewport.of(device);
    return (
      deviceId as String?,
      viewport.resized(
        width: _intArgument(arguments, 'width'),
        height: _intArgument(arguments, 'height'),
      ),
    );
  }

  static int? _intArgument(Map<String, Object?> arguments, String key) {
    var value = arguments[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

PluginCore uiCatalogCoreFactory(PluginHost host) => PreviewsCore(host);

/// What one `inspect` call asked for, read and checked once.
///
/// **Its own type because the handler had fifteen locals**, and a function that
/// parses arguments, chooses a source and projects a result in one breath is a
/// function nobody can review — which is how `--debug` came to be declared and
/// passed nowhere.
///
/// Everything here is validated in the constructor, before the caller's request
/// has cost a scan or a compile. A typo in a flag should cost nothing.
class _InspectRequest {
  _InspectRequest._({
    required this.entryId,
    required this.tree,
    required this.logs,
    required this.errors,
    required this.query,
    required this.at,
    required this.node,
    required this.depth,
    required this.picture,
    required this.annotate,
    required this.output,
    required this.deviceId,
    required this.viewport,
    required this.knobs,
    required this.axes,
    required this.debug,
    required this.mayAttach,
  });

  factory _InspectRequest.of(Map<String, Object?> arguments) {
    var entryId = arguments['entry'];
    if (entryId is! String || entryId.isEmpty) {
      throw ArgumentError.value(entryId, 'entry', 'required');
    }
    var knobs = PreviewsCore.parseKnobs(arguments['knobs']);
    var axes = PreviewsCore.parseKnobs(arguments['axes']);
    var debug = PreviewsCore.parseKnobs(arguments['debug']);
    var (deviceId, viewport) = PreviewsCore._framing(arguments);
    var picture = arguments['screenshot'] == true;

    return _InspectRequest._(
      entryId: entryId,
      tree: arguments['tree'] == true,
      logs: arguments['logs'] == true,
      errors: arguments['errors'] != false,
      query: switch (arguments['find']) {
        String q when q.isNotEmpty => q,
        null || '' => null,
        var other => throw ArgumentError.value(other, 'find', 'must be text'),
      },
      at: PreviewsCore._parsePoint(arguments['at']),
      node: switch (arguments['node']) {
        String id when id.isNotEmpty => id,
        _ => null,
      },
      depth: arguments['depth'],
      picture: picture,
      annotate: arguments['annotate'] == true,
      output: arguments['output'] as String?,
      deviceId: deviceId,
      viewport: viewport,
      knobs: knobs,
      axes: axes,
      debug: debug,
      mayAttach: PreviewsCore._mayAttach(
        live: arguments['live'],
        knobs: knobs,
        axes: axes,
        debug: debug,
        wantsPicture: picture,
        reframed: deviceId != null || viewport != CaptureViewport.panel,
      ),
    );
  }

  final String entryId;

  /// Which projections were asked for. `errors` is the one that defaults on:
  /// with no flags at all it is the whole answer.
  final bool tree;
  final bool logs;
  final bool errors;
  final bool picture;

  final String? query;
  final (int, int)? at;
  final String? node;
  final Object? depth;
  final bool annotate;

  /// Where to write the picture, as the caller wrote it. Resolving it needs the
  /// worktree and the address, so that happens on the core.
  final String? output;

  final String? deviceId;
  final CaptureViewport viewport;
  final Map<String, String> knobs;
  final Map<String, String> axes;
  final Map<String, String> debug;

  /// Whether this call may read a window somebody has open — decided here so
  /// that the reasons sit beside the flags they are about.
  final bool mayAttach;
}
