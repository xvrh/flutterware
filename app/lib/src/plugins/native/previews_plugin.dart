import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../previews/authoring.dart';
import '../../previews/catalog_devices.dart';
import '../../previews/catalog_session.dart';
import '../../previews/catalog_view.dart';
import '../../previews/compiler_daemon_client.dart';
import '../../previews/discovery.dart';
import '../../previews/new_preview_dialog.dart';
import '../../previews/web_build_dialog.dart';
import '../../previews/web_server.dart';
import '../native_plugin.dart';
import 'previews_address.dart';
import 'previews_core.dart';
import '../../ui/design/design.dart';
import '../../ui/loading_state.dart';
import 'no_packages.dart';

export 'previews_core.dart' show PreviewsCore, uiCatalogPluginId;

/// The GUI half of Previews: the live compile loop, and a panel.
///
/// Everything else — the scan, the entry list, the report, `rescan` and
/// `screenshot` — lives in [PreviewsCore], which is pure Dart, so `fw` and an
/// agent reach exactly the same behaviour. What stays here is
/// [CatalogSession]: it drives a guest engine into a texture, which is
/// Flutter-bound by nature.
///
/// The session is owned by the plugin rather than the panel so that leaving the
/// panel does not throw away a running daemon — and so the sidebar can say what
/// the compiler is doing while you are looking elsewhere. That progress reaches
/// the report through [PreviewsCore.busyStatusFor].
class PreviewsPlugin extends NativePlugin<PreviewsCore> {
  PreviewsPlugin(
    super.core, {
    this.connectToDaemon = CompilerDaemonClient.connect,
  }) {
    core.busyStatusFor = _busyStatusFor;
  }

  /// How the sessions this builds reach a compiler — see
  /// [CatalogSession.connectToDaemon], which already exists for the same
  /// reason and is simply threaded through here.
  ///
  /// Nothing in production passes it. What it buys is a test that can mount
  /// this panel: the real connect compiles a snapshot and spawns a process, so
  /// without a seam the only way to exercise the panel's own wiring is not to
  /// exercise it.
  final DaemonConnector connectToDaemon;

  final _sessions = <String, CatalogSession>{};

  /// A server per served directory, so a rebuild of the same page reuses the
  /// port a browser tab already has open — the tab reloads onto the new build
  /// rather than pointing at a server that has gone.
  final _servers = <String, CatalogWebServer>{};

  List<String> get packages => core.packages;

  /// Serves a built page and answers with the URL, starting a server only if
  /// this directory has not got one.
  ///
  /// Owned here rather than by the dialog that asks for it: the dialog is
  /// closed the moment you have the URL, and a server that died with it would
  /// leave the tab it just opened showing a connection error. The worktree is
  /// the right lifetime — see [dispose].
  Future<Uri> serveBuild(String output, {String basePath = '/'}) async {
    var directory = p.isAbsolute(output)
        ? output
        : p.join(host.worktree.path, output);
    var existing = _servers[directory];
    // Rebound when the base href changed: the same directory built for a
    // different mount point is a different page as far as a browser is
    // concerned, and the old server would answer 404 for all of it.
    if (existing != null &&
        existing.basePath == CatalogWebServer.normaliseBasePath(basePath)) {
      return existing.url;
    }
    await existing?.close();
    var server = await CatalogWebServer.serve(directory, basePath: basePath);
    _servers[directory] = server;
    return server.url;
  }

  /// The live compile loop for [path], started on first ask — which is the
  /// panel mounting.
  CatalogSession sessionFor(String path) => _sessions.putIfAbsent(path, () {
    var session = CatalogSession(
      appPackageRoot: host.workspace.appContext.appToolDirectory.path,
      flutterSdkRoot: host.workspace.flutterSdk.root,
      projectRoot: p.join(host.worktree.path, path),
      // So a `file:line` in the panel reads the same as one from `fw`, which
      // shortens against the worktree too.
      worktreeRoot: host.worktree.path,
      // The core's answer, not a second one: `roots` is part of the daemon
      // address, so a panel resolving it independently would open a different
      // daemon than `fw run previews` does for the same package.
      roots: [core.rootFor(path)],
      previewAnnotations: core.previewAnnotationsFor(path),
      // The whole list, not one resolved device: which of them applies is a
      // function of the entry on screen, and the panel is where that changes.
      canvases: core.canvasesFor(path),
      connectToDaemon: connectToDaemon,
    )..addListener(core.notifyChanged);
    unawaited(session.start());
    return session;
  });

  /// Not worth photographing while any open catalog is still working.
  ///
  /// Three conditions, and the third is the one that is easy to miss: a session
  /// can be `ready` with nothing in flight while the guest is still showing the
  /// *previous* entry, because [CatalogSession.selected] is what was asked for
  /// and `active` is what the guest managed to load. A capture taken in that
  /// window is a correct picture of the wrong demo, which is the single worst
  /// thing a screenshot tool can produce.
  ///
  /// A compile error settles rather than waits. The panel is showing the error,
  /// the error is the state, and hanging until the timeout would turn "this
  /// demo is broken" into "the tool is broken".
  @override
  String? get busyWith {
    for (var session in _sessions.values) {
      if (session.phase == CatalogSessionPhase.starting) {
        return session.busyWith ?? 'starting the catalog';
      }
      if (session.busyWith case var busy?) return busy;
      if (session.selectedError != null) continue;
      if (session.selected?.id != session.active?.id) {
        return 'loading ${session.selected?.id}';
      }
    }
    return null;
  }

  /// What the compiler is doing for [path], or null when it is idle.
  ///
  /// This is the status worth a sidebar row: a cold compile is the only thing
  /// here that takes seconds, and a word that stays put until it goes away is
  /// what lets you look elsewhere and notice when it lands. No elapsed count —
  /// a figure ticking in the corner of the eye is movement, not information.
  ///
  /// [CatalogSession.visiblyBusyWith] rather than `busyWith`, and that is the
  /// whole difference between a rail that reports and a rail that flickers: a
  /// switch the guest makes by itself is 64ms, and this row is not worth
  /// 64ms of anybody's attention. The unfloored [busyWith] is still what
  /// [PreviewsPlugin.busyWith] above answers with, because a capture must know
  /// the instant the session starts working, not a quarter-second later.
  Status? _busyStatusFor(String path) {
    if (_sessions[path]?.visiblyBusyWith case var busy?) {
      return Status.info(busy);
    }
    if (_sessions[path]?.phase == CatalogSessionPhase.error) {
      return const Status.error('failed to start');
    }
    return null;
  }

  @override
  Widget buildPanel(BuildContext context) => _CatalogPanel(this);

  /// One command, on the row for the package it would build.
  ///
  /// On the row rather than in the panel because that is what it is *of*: a
  /// page is one package's whole catalog, and the panel is always looking at
  /// one entry of it.
  @override
  List<PluginChildCommand> childCommands(
    BuildContext context,
    String childId,
  ) => [
    PluginChildCommand(
      label: 'Build a web page…',
      icon: Icons.language,
      onSelected: (context) => unawaited(
        showWebBuildDialog(
          context,
          core: core,
          package: childId,
          serve: serveBuild,
        ),
      ),
    ),
  ];

  /// Closing the worktree is what ends the compile loops and the servers —
  /// nothing shorter does, which is the whole point of the plugin owning them.
  @override
  void dispose() {
    for (var session in _sessions.values) {
      session
        ..removeListener(core.notifyChanged)
        ..dispose();
    }
    _sessions.clear();
    for (var server in _servers.values) {
      unawaited(server.close());
    }
    _servers.clear();
    super.dispose();
  }
}

/// Points the catalog at whatever the address names, and writes back where it
/// ends up.
///
/// Both directions run through [catalogSegments] and [catalogPlace], so the
/// address this writes for a given entry is byte-identical to the one it would
/// have read for it. That is what stops the two directions chasing each other:
/// the write-back for an entry the address already named produces the address
/// it already is, and the shell recognises that as no move at all.
class _CatalogPanel extends StatefulWidget {
  const _CatalogPanel(this.plugin);

  final PreviewsPlugin plugin;

  @override
  State<_CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends State<_CatalogPanel> {
  /// The plugin the binding below belongs to — **not** always the one
  /// [widget] holds.
  ///
  /// A config reload throws the whole plugin graph away and builds it again
  /// (`ShellController._apply` → `open.release()` → `_build`), so this plugin
  /// object is replaced. The shell keys the panel on the worktree and the
  /// plugin *id*, both of which survive that, so Flutter keeps this `State` —
  /// and it woke up holding a [CatalogSession] whose owner had already
  /// disposed it. The panel then went on rendering that session: the entry list
  /// and the top bar listen to it, and `addListener` on a disposed
  /// `ChangeNotifier` throws, which took the canvas out for the rest of the
  /// process. Saving `tool/flutterware.dart` was the whole of the repro.
  ///
  /// Compared by identity rather than asked about, because there is nothing to
  /// ask: a rebuilt graph is new objects all the way down, and *this is a
  /// different plugin* is the only fact that distinguishes it from the load
  /// that declared nothing new — which builds nothing and swaps nothing.
  PreviewsPlugin? _plugin;
  String? _package;
  CatalogSession? _session;
  var _writeScheduled = false;

  /// The entry this last handed to the session, so the same one is not handed
  /// over twice.
  ///
  /// [didChangeDependencies] fires for its own reasons, not only when the
  /// address moves, and the address lags a local selection by a frame — its
  /// write-back is a post-frame callback. Restating it unconditionally
  /// therefore pushes the *previous* entry back onto a session that has already
  /// moved on, and `_applyWanted` dutifully switches back to it. That is a
  /// click silently undone.
  ///
  /// This used to be harmless by accident: nothing else wrote `wantedEntryId`,
  /// so the setter's own no-op absorbed the repeat. The moment selecting also
  /// counted as wanting, the repeat became a real change and undid every click
  /// rather than merely some of them.
  String? _followed;
  var _hasFollowed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow(catalogPlace(AddressScope.segments(context)));
  }

  @override
  void didUpdateWidget(_CatalogPanel old) {
    super.didUpdateWidget(old);
    // The declared packages can change under a config reload without the
    // address moving, and the fallback below is computed from them.
    _follow(catalogPlace(AddressScope.segments(context)));
  }

  /// Mounting the panel is the demand: the scan, and the compile loop the scan
  /// deliberately leaves alone.
  void _follow(CatalogPlace? place) {
    var package = place?.package ?? widget.plugin.packages.firstOrNull;

    // A swapped plugin is as much a new session as a different package is, and
    // for a stronger reason: the old one is not merely stale, it is disposed.
    // See [_plugin].
    var sessionChanged = package != _package || widget.plugin != _plugin;
    if (sessionChanged) {
      _release();
      _plugin = widget.plugin;
      _package = package;
      if (package != null) {
        // The scan, always. The compile loop only once the scan has found
        // something to compile — see [_startSessionIfReady], which is also
        // called from `build` because the scan usually lands after this.
        widget.plugin.core.track(package);
        _startSessionIfReady(package);
      }
    }

    // A request rather than a call: on a cold start the daemon has not reported
    // anything yet, and clicking the link is what starts the compile it would
    // otherwise be waiting for.
    //
    // Applied only when the *address* has moved — see [_followed]. A fresh
    // session always gets it, since it has never been told anything.
    if (addressMoved(
      hasFollowed: _hasFollowed,
      sessionChanged: sessionChanged,
      followed: _followed,
      place: place?.entryId,
    )) {
      _hasFollowed = true;
      _followed = place?.entryId;
      _session?.wantedEntryId = place?.entryId;
    }
  }

  /// Starts the compile loop for [package], but only once the scan says there
  /// is something to compile.
  ///
  /// **This is the thirty seconds.** A package with no entries used to get a
  /// session like any other: the daemon bound its socket, scanned the same
  /// directory this one did, refused in about a millisecond, and exited before
  /// the client's first 25ms poll had connected — so the `DaemonFailed` it sent
  /// reached nobody, and the client polled a deleted socket until its
  /// 30-second deadline before reporting that the daemon "never started
  /// listening". The fastest failure in the system produced the slowest
  /// feedback, for a fact the scan already held.
  ///
  /// Idempotent, and called from both [_follow] and `build`: the scan is
  /// asynchronous, so on a cold open it is the rebuild that follows it — not
  /// the mount — that first knows the answer.
  void _startSessionIfReady(String package) {
    if (_session != null) return;
    if (widget.plugin.core.setupFor(package) != CatalogSetup.ready) return;
    _session = widget.plugin.sessionFor(package)..addListener(_settled);
    // A fresh session has never been told anything, so whatever the address
    // asked for has to be restated to it. [_follow] would otherwise only do
    // this when the address *moves*, and it has not moved since the mount.
    if (_hasFollowed) _session!.wantedEntryId = _followed;
  }

  /// Writes the first demo, then goes to it.
  ///
  /// The address move is what starts the compile loop: `newPreview` rescans, the
  /// package becomes [CatalogSetup.ready], and the rebuild that follows calls
  /// [_startSessionIfReady] — so the demo somebody just asked for is the entry
  /// their session opens on.
  Future<void> _newPreview(BuildContext context, String package) async {
    var result = await showNewPreviewDialog(
      context,
      core: widget.plugin.core,
      package: package,
    );
    if (result == null || !context.mounted) return;
    AddressScope.write(
      context,
    ).setSegments(catalogSegments(package, result.id));
  }

  /// Lets go of whatever is bound, **through the plugin it was bound to**.
  ///
  /// [widget.plugin] is already the new one by the time a swap reaches here, so
  /// untracking through it would release a package on a core that has never
  /// been asked for it and leave the old one tracked — releasing the wrong half
  /// of a swap the whole point of which is that the two halves are different
  /// objects.
  void _release() {
    _hasFollowed = false;
    _followed = null;
    if (_package case var previous?) _plugin?.core.untrack(previous);
    _session?.removeListener(_settled);
    _session = null;
    _package = null;
    _plugin = null;
  }

  /// The other direction: the catalog moved on its own — a click in its tree, a
  /// device chosen from the picker, a deleted entry, or the first demo taken
  /// because the address named none — so the address has to catch up.
  ///
  /// Deferred a frame because the session notifies from wherever its work
  /// finished, which can be inside a build; writing the address marks the shell
  /// dirty, and doing that mid-build is the crash this defers around.
  ///
  /// One write for both halves. Two would put an address on screen naming a
  /// state that never existed — the new entry still framed as the old device —
  /// and anything reading it in that gap would act on it.
  void _settled() {
    if (_writeScheduled || !mounted || _package == null) return;

    _writeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _writeScheduled = false;
      var package = _package;
      var session = _session;
      if (!mounted || package == null || session == null) return;

      // **Never over a complaint.** An address naming an entry this catalog
      // does not have is reported, not repaired — but restating wherever the
      // session actually landed would repair it anyway, quietly. The banner
      // would vanish along with what you had asked for, and a pasted link would
      // look like it had worked.
      if (session.missingEntryId != null) return;

      // **Nor before it has landed anywhere.** A session notifies while it is
      // starting — `building`, and again for every step of it — and until the
      // daemon reports there is no selection to write back. Writing one anyway
      // states the package alone, which reads as *this catalog is on no entry*
      // and is not something the session ever said; the shell then drops
      // `knob` and `inspect` along with the segment, because the write looks
      // like the end of an entry. A config reload builds a fresh session under
      // a mounted panel, so that turned saving `tool/flutterware.dart` into
      // losing whatever the demo's knobs were set to.
      if (session.selected == null) return;

      // Nothing about the device or the axes here. Neither is state to write
      // back: their controls write the address directly, and what is on screen
      // is read from the address every time it is drawn.
      var handle = AddressScope.write(context);
      var segments = catalogSegments(package, session.selected?.id);
      handle.update(
        segments: segments,
        // A knob belongs to the entry, so it cannot outlive one. Dropped here
        // because this is the write that ends the entry — a demo's knobs are
        // meaningless against the next one, and carrying them would leave an
        // address accumulating settings for demos it no longer names. Axes
        // belong to the shell and are deliberately untouched.
        //
        // `inspect` goes with it, and more sharply: a node id is a *position in
        // one tree*, so carried across a switch it would not merely be stale,
        // it would name some unrelated widget of the next demo with complete
        // confidence.
        drop: listEquals(segments, handle.segments)
            ? const {}
            : const {'knob', 'inspect'},
      );
    });
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var path = _package;
    if (path == null) {
      return const NoPackagesConfigured(icon: Icons.widgets_outlined);
    }
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        // The scan's own failure, which is the one that arrives first and
        // explains why the daemon would refuse to start.
        if (widget.plugin.core.failureFor(path) case var failure?) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                failure,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        }

        // Before the compile loop, because the compile loop is what this
        // decides. `unknown` is the scan still running — a moment, and not the
        // same claim as "there are none".
        var setup = widget.plugin.core.setupFor(path);
        if (setup == CatalogSetup.unknown) {
          return const LoadingState(title: 'Looking for demos…');
        }
        if (setup != CatalogSetup.ready) {
          return _NoPreviews(
            directory: widget.plugin.core.rootFor(path),
            directoryExists: setup != CatalogSetup.missing,
            package: widget.plugin.packages.length == 1 ? null : path,
            diagnostics: widget.plugin.core.diagnosticsFor(path),
            onNew: () => unawaited(_newPreview(context, path)),
          );
        }

        _startSessionIfReady(path);
        var session = _session!;
        return Column(
          children: [
            // Said out loud rather than repaired. The address is left naming
            // what it named, so a link to a demo that has not been written yet
            // still reads as that demo rather than turning into a different one.
            if (session.missingEntryId case var missing?)
              _Complaint('No entry "$missing" in this package.'),
            // Derived from the address, like the framing itself. Nothing
            // remembers that a bad value was seen, so nothing has to remember
            // to forget it.
            if (unknownDeviceIn(AddressScope.param(context, 'device'))
                case var device?)
              _Complaint('No device "$device". Try: ${deviceIds.join(', ')}.'),
            // The live loop. The core's own scan stays — it is what `fw` and an
            // agent read without a daemon running — but what the panel shows is
            // the compiled catalog, because only the daemon knows which entries
            // actually build.
            //
            // **Keyed on the session, not on the package.** The package was
            // enough for as long as a new session only ever arrived with one,
            // and a config reload is the case where it does not: the package
            // is the same string and the session below it is a different
            // object. Everything under here binds to a session *at mount* —
            // `InspectPanel` turns the watch and the log stream on from
            // `initState`, `CatalogView` starts its poll there — so a swap the
            // key did not notice left the new session with nobody watching it
            // and no logs, silently, until you left the plugin and came back.
            // A package change still remounts, since one session is one
            // package.
            Expanded(
              child: CatalogView(key: ObjectKey(session), session: session),
            ),
          ],
        );
      },
    );
  }
}

/// The screen a project sees before it has written a demo.
///
/// Not an error screen. This is what every project looks like on the day it
/// first opens the catalog, and it used to be thirty seconds of spinner
/// followed by a stack trace. It says where we looked, why there is nothing,
/// how to write one, and offers to write it.
class _NoPreviews extends StatelessWidget {
  const _NoPreviews({
    required this.directory,
    required this.directoryExists,
    required this.package,
    required this.diagnostics,
    required this.onNew,
  });

  final String directory;
  final bool directoryExists;
  final String? package;

  /// What the scan rejected. Empty for a project that has genuinely written
  /// nothing — and decidedly not empty for one whose first attempt was turned
  /// away, which is the case this screen used to answer with "no previews yet".
  final List<ScanDiagnostic> diagnostics;

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            catalogEmptyReason(
              directory: directory,
              directoryExists: directoryExists,
              package: package,
            ),
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
          // Above the button and the hint, because it outranks both: somebody
          // whose annotation was rejected does not need to be taught how to
          // write one, they need to be told what was wrong with theirs.
          if (diagnostics.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (var diagnostic in diagnostics)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  '$diagnostic',
                  style: TextStyle(
                    fontSize: 12,
                    color: diagnostic.isError
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add, size: FwIconSize.md),
              label: const Text('New preview'),
            ),
          ),
          const SizedBox(height: 24),
          SelectableText(
            catalogAuthoringHint(directory),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Something the address asked for that this catalog cannot give.
///
/// Shown rather than repaired, and the message names the accepted values where
/// there is a closed set of them — the reader is often an agent that guessed,
/// and the useful reply to a guess is the list it should have picked from.
class _Complaint extends StatelessWidget {
  const _Complaint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    var scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SelectableText(
        message,
        style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
      ),
    );
  }
}
