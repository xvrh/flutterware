/// The project the studio opens when it is showing a recording rather than a
/// checkout: its own catalog demos of whole panels, its own scenario tests,
/// and the web demo.
///
/// Everything the shell would learn from the machine is answered here instead
/// — the worktree list git would report, the manifest `tool/flutterware.dart`
/// would produce, the facts the explorer would probe — and every plugin's core
/// is either the live core over a recorded reader (launcher icon) or a quiet
/// [RecordedCore] whose panel says so. Nothing below runs a process, opens a
/// socket or walks a directory; the one filesystem touch left, the facts
/// store, points at a path that is not there and is built to shrug.
///
/// The recorded project is **`examples/example` as if it were its own
/// repository** — one package at `.`, which is what a reader's project usually
/// is and what keeps the workspace free of anything the disk would have to
/// confirm. See `tool/demo/record.dart` for how the recording is made.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';

import '../context.dart';
import '../plugins/manifest_loader.dart';
import '../plugins/native/icon_plugin.dart';
import '../plugins/native_plugin.dart';
import '../plugins/plugin_core.dart';
import '../plugins/registry.dart';
import '../shell/shell_controller.dart';
import '../shell/worktree_discovery.dart';
import '../ui/empty_state.dart';
import '../utils/flutter_sdk.dart';
import '../worktrees/facts.dart';
import '../worktrees/facts_controller.dart';
import '../worktrees/facts_probe.dart';
import '../worktrees/facts_store.dart';
import '../worktrees/providers/agent.dart';
import '../worktrees/providers/forge.dart';
import '../worktrees/providers/git.dart';
import '../worktrees/providers/stack.dart';
import '../worktrees/watchers.dart';
import '../plugins/native/dev_stack_results.dart';
import 'recording.dart';

/// Where the recorded project pretends to be. Never read from disk; it is what
/// the address bar shows and what the facts store is keyed by.
const recordedProjectRoot = '/recording';

/// What the recorded project's `tool/flutterware.dart` would declare.
///
/// Written with the same classes a project writes its config with, so the
/// recording's rail is a rail a real config could produce. Only the launcher
/// icon has a recording behind it today; the rest are declared so the rail
/// reads as a project rather than as one plugin, and their panels say what
/// they are.
PluginManifest recordedManifest() {
  const root = Pkg('.');
  var fw = FlutterwareConfig();
  fw.use(Dependencies(packages: const [DependenciesPackage(root)]));
  fw.use(Assets(packages: const [AssetsPackage(root)]));
  fw.use(Previews(packages: const [PreviewsPackage(root)]));
  fw.use(Scenarios(packages: const [ScenariosPackage(root)]));
  fw.use(LauncherIcon(packages: const [LauncherIconPackage(root)]));
  fw.use(NativeSplash(packages: const [NativeSplashPackage(root)]));
  return fw.toManifest();
}

/// A shell over [recording], started on nothing but memory.
///
/// [appContext] and [flutterSdk] default to values nothing here dereferences:
/// the recorded cores never build a daemon or spawn a tool, so the SDK path is
/// a label and the app-tool directory is never listed.
ShellController recordedShell({
  required Recording recording,
  AppContext? appContext,
  FlutterSdkPath? flutterSdk,
  PluginManifest? manifest,
}) {
  var context =
      appContext ??
      AppContext(
        logger: LogClient.print(),
        appToolDirectory: Directory(recordedProjectRoot),
      );
  var declared = manifest ?? recordedManifest();
  return ShellController(
    appContext: context,
    flutterSdk: flutterSdk ?? FlutterSdkPath('$recordedProjectRoot/flutter'),
    registry: PluginRegistry({
      for (var plugin in declared.plugins)
        plugin.id: plugin.id == launcherIconPluginId
            ? panelFor<LauncherIconCore>(
                (core) => LauncherIconPlugin(
                  core,
                  image: recordedIconImage(recording),
                ),
              )
            : panelFor<RecordedCore>(NotRecordedPlugin.new),
    }),
    coreRegistry: PluginCoreRegistry({
      for (var plugin in declared.plugins)
        plugin.id: plugin.id == launcherIconPluginId
            ? (host) =>
                  LauncherIconCore(host, scan: recordedIconScanner(recording))
            : RecordedCore.new,
    }),
    manifestLoader: RecordedManifestLoader(declared),
    discovery: WorktreeDiscovery(runProcess: _recordedGit),
    worktreeFacts: (root) => WorktreeFactsController(
      repoRoot: root,
      probe: WorktreeFactsProbe(
        repoRoot: root,
        // A path that is not there: the store reads an empty cache from it and
        // swallows the write, which is the one filesystem touch left here.
        store: WorktreeFactsStore.open(root, at: File('$root/facts.json')),
        git: GitProbe(runProcess: _recordedGit),
        agent: const _NoAgents(),
        forge: const _NoForge(),
        stack: const _NoStacks(),
      ),
      settle: context.settle,
    ),
    worktreeWatcher: (root) => WorktreeWatcher(
      repoRoot: root,
      watch: (path, {required recursive}) => const Stream.empty(),
    ),
    watchEvents: (_) => const Stream.empty(),
  );
}

/// The one git answer a recording has: it is a repository with one worktree
/// on `main`. Anything else git is asked fails, quietly.
Future<ProcessResult> _recordedGit(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  if (arguments.take(2).join(' ') == 'worktree list') {
    return ProcessResult(
      0,
      0,
      'worktree $recordedProjectRoot\nbranch refs/heads/main\n',
      '',
    );
  }
  return ProcessResult(0, 1, '', 'not available in a recording');
}

/// The manifest, without running anything.
class RecordedManifestLoader implements ManifestLoader {
  const RecordedManifestLoader(this.manifest);

  final PluginManifest manifest;

  @override
  Future<PluginManifest?> load(String path) async => manifest;

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String path,
  ) async => (manifest: manifest, error: null);

  @override
  String get dartExecutable => 'dart';

  @override
  String? get flutterRoot => null;

  @override
  Duration get timeout => Duration.zero;
}

/// A plugin the recording declares but has nothing recorded for.
///
/// Quiet, with a row per declared package so the rail shows the project's
/// shape. [NotRecordedPlugin] is its panel.
class RecordedCore extends PluginCore {
  RecordedCore(super.host);

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: Status.none,
    children: [
      for (var path in host.packagePaths)
        PluginChild(id: path, label: path == '.' ? 'root' : path),
    ],
  );
}

class NotRecordedPlugin extends NativePlugin<RecordedCore> {
  NotRecordedPlugin(super.core);

  @override
  Widget buildPanel(BuildContext context) => EmptyState(
    icon: Icons.radio_button_unchecked,
    title: 'Not in this recording',
    message:
        '${host.label} reads a live project. This studio is showing a '
        'recording, and nothing has been recorded for it yet.',
  );
}

class _NoAgents implements AgentProbe {
  const _NoAgents();

  @override
  Future<AgentFacts?> probe(String worktreePath) async => null;
}

class _NoForge implements ForgeProbe {
  const _NoForge();

  @override
  Future<ForgeReport> probe(String repoRoot) async =>
      const ForgeReport.unavailable('This is a recording.');
}

class _NoStacks implements StackProbe {
  const _NoStacks();

  @override
  Future<StackReading?> probe(String worktreePath) async => null;
}
