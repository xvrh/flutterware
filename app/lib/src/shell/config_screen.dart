import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../plugins/manifest_loader.dart';
import '../ui/theme.dart';
import 'config_load.dart';
import 'shell_controller.dart';
import 'worktree.dart';

/// The config screen's root, so a test can scope to it.
const configScreenKey = Key('config-screen');

/// **`fw://<worktree>/config`** — the shell's own screen for
/// `tool/flutterware.dart`.
///
/// Deliberately not a plugin. Which plugins exist is this file's decision, so a
/// plugin panel that explained it could be removed by the very edit that broke
/// it — and a worktree whose config fails to load is exactly when you need this
/// screen most. It lives in the plugin *slot* of the address because it is
/// addressed like one (see [Address.shellConfig]), and nowhere else.
///
/// Three questions, in the order they get asked: **what did it resolve to**,
/// **why did it fail**, and **what did the last reload cost me**. The last one
/// is the diff made visible — without it, a surgical reload is a black box that
/// quietly rebuilds some plugins and not others.
class ConfigScreen extends StatelessWidget {
  const ConfigScreen(this.shell, this.worktree, {super.key});

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var error = shell.errorFor(worktree);
    var manifest = shell.manifestFor(worktree);
    var log = shell.loadLog(worktree);

    return ListView(
      key: configScreenKey,
      padding: const EdgeInsets.all(FwSpacing.xxxl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Config', style: context.type.pageTitle),
                  const Gap(FwSpacing.sm),
                  SelectableText(
                    '${worktree.path}/$configFilePath',
                    style: context.type.caption,
                  ),
                ],
              ),
            ),
            _ReloadAction(shell, worktree),
          ],
        ),

        const Gap(FwSpacing.lg),
        _Watch(shell, worktree),

        if (error != null) ...[
          const Gap(FwSpacing.xxl),
          _Failure(error.message),
        ],

        if (manifest != null) ...[
          const Gap(FwSpacing.xxl),
          Text('Resolved', style: context.type.sectionLabel),
          const Gap(FwSpacing.sm),
          _Resolved(shell, worktree, manifest),
        ],

        if (log.isNotEmpty) ...[
          const Gap(FwSpacing.xxl),
          Text('Reloads', style: context.type.sectionLabel),
          const Gap(FwSpacing.sm),
          for (var load in log) LoadRow(load),
        ],

        if (manifest == null && error == null) ...[
          const Gap(FwSpacing.xxl),
          Text(
            'This worktree declares no $configFilePath.',
            style: context.type.bodyMuted.copyWith(color: colors.mut),
          ),
        ],
      ],
    );
  }
}

/// Re-runs the config. The same call the band button used to make, moved to
/// where the result of making it is on screen.
class _ReloadAction extends StatelessWidget {
  const _ReloadAction(this.shell, this.worktree);

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    // A reload disposes what a close does — for the plugins it rebuilds — so it
    // answers to the same guards.
    var guards = shell.sessionFor(worktree)?.guards ?? const <Guard>[];
    var blocking = guards
        .where((g) => g.level == GuardLevel.block)
        .map((g) => g.reason)
        .toList();
    var loading = shell.isLoading(worktree);

    return Tooltip(
      message: blocking.isNotEmpty
          ? blocking.join('\n')
          : 'Re-run $configFilePath',
      child: FilledButton.icon(
        onPressed: blocking.isEmpty && !loading
            ? () => shell.reloadConfig()
            : null,
        icon: const Icon(Icons.refresh, size: 14),
        label: const Text('Reload'),
      ),
    );
  }
}

/// Whether saving the file reloads it, and what is actually being watched.
///
/// **Naming the directory is the point**, not decoration. "It did not notice my
/// edit" is the standard complaint about file watching, and the standard cause is
/// that the thing you edited was not in the watched set. Saying which directory
/// is watched turns that from a mystery into a fact — and today the answer is
/// only the config's own directory, so an edit to a file it imports really does
/// need the button until the import closure arrives with the resident compiler.
class _Watch extends StatelessWidget {
  const _Watch(this.shell, this.worktree);

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var watching = shell.watchingFor(worktree);
    var pending = shell.isReloadPending(worktree);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: shell.watchEnabled,
              onChanged: (value) => shell.watchEnabled = value,
            ),
            const Gap(FwSpacing.sm),
            Expanded(
              child: Text(switch ((shell.watchEnabled, watching)) {
                (false, _) => 'Reload on save is off',
                (true, null) =>
                  'Nothing to watch — this worktree has no $configFilePath',
                (true, var dir) => 'Reloads on save · watching $dir',
              }, style: context.type.caption.copyWith(color: colors.mut)),
            ),
          ],
        ),
        if (pending) ...[
          const Gap(FwSpacing.sm),
          Row(
            children: [
              Icon(Icons.schedule, size: 12, color: colors.amber),
              const Gap(FwSpacing.sm),
              Expanded(
                child: Text(
                  'The file changed, but a plugin is busy. It will reload as '
                  'soon as the guard clears.',
                  style: context.type.caption.copyWith(color: colors.amber),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Why the config did not load, with the compiler's own words.
///
/// The whole output, not a first line: this is the screen you came to in order
/// to read it, so there is nothing left to hide it behind.
class _Failure extends StatelessWidget {
  const _Failure(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var lines = message.trimRight().split('\n');

    return Container(
      padding: const EdgeInsets.all(FwSpacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: colors.red),
        borderRadius: BorderRadius.circular(context.radii.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lines.first,
            style: context.type.bodyStrong.copyWith(color: colors.red),
          ),
          if (lines.length > 1) ...[
            const Gap(FwSpacing.sm),
            SelectableText(
              lines.skip(1).join('\n').trim(),
              style: context.type.caption.copyWith(fontFamily: 'monospace'),
            ),
          ],
          const Gap(FwSpacing.sm),
          Text(
            'The plugins below are the ones from the last config that loaded. '
            'Nothing was torn down.',
            style: context.type.caption.copyWith(color: colors.mut),
          ),
        ],
      ),
    );
  }
}

/// What the config actually said: its packages, then its plugins.
///
/// The answer to "why isn't my plugin showing up", which is otherwise only
/// answerable by reading the file and guessing.
class _Resolved extends StatelessWidget {
  const _Resolved(this.shell, this.worktree, this.manifest);

  final ShellController shell;
  final Worktree worktree;
  final PluginManifest manifest;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var missing =
        shell.workspaceFor(worktree)?.unknownDeclarations ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var pkg in manifest.packages)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(
                  missing.contains(pkg.path)
                      ? Icons.error_outline
                      : Icons.folder_outlined,
                  size: 12,
                  color: missing.contains(pkg.path) ? colors.red : colors.mut2,
                ),
                const Gap(FwSpacing.sm),
                Text(
                  pkg.path,
                  style: context.type.caption.copyWith(
                    fontFamily: 'monospace',
                    color: missing.contains(pkg.path) ? colors.red : null,
                  ),
                ),
                if (pkg.tags.isNotEmpty) ...[
                  const Gap(FwSpacing.sm),
                  Text(
                    pkg.tags.join(' · '),
                    style: context.type.micro.copyWith(color: colors.mut2),
                  ),
                ],
                if (missing.contains(pkg.path)) ...[
                  const Gap(FwSpacing.sm),
                  Text(
                    'not on disk',
                    style: context.type.micro.copyWith(color: colors.red),
                  ),
                ],
              ],
            ),
          ),

        const Gap(FwSpacing.lg),

        for (var plugin in manifest.plugins)
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(plugin.label, style: context.type.bodyStrong),
                    const Gap(FwSpacing.sm),
                    Text(
                      plugin.id,
                      style: context.type.micro.copyWith(
                        fontFamily: 'monospace',
                        color: colors.mut2,
                      ),
                    ),
                  ],
                ),
                // The config keys, not their values: a value can be a nested
                // list of packages and this is an orientation, not a dump.
                if (plugin.config.isNotEmpty)
                  Text(
                    plugin.config.keys.join(', '),
                    style: context.type.micro.copyWith(color: colors.mut2),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One run of `tool/flutterware.dart`, and what it cost.
///
/// **The diff, made visible.** Without this the reconciliation is a black box
/// you have to trust: a plugin quietly disappears and reappears and nothing says
/// which config key moved. This is what answers "why did my device just die",
/// which is the question a surgical reload creates by being surgical.
class LoadRow extends StatelessWidget {
  const LoadRow(this.load, {super.key});

  final ConfigLoad load;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var at = load.at;
    var clock =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  clock,
                  style: context.type.caption.copyWith(color: colors.mut2),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${load.duration.inMilliseconds}ms',
                  style: context.type.caption.copyWith(color: colors.mut2),
                ),
              ),
              Expanded(
                child: Text(
                  load.summary,
                  style: context.type.caption.copyWith(
                    color: load.succeeded ? colors.ink : colors.red,
                  ),
                ),
              ),
            ],
          ),
          // Only the reasons, one per rebuilt plugin. A load that rebuilt
          // nothing has nothing to explain, which is most of them.
          for (var id in load.rebuilt)
            if (load.reasons[id] case var reason?)
              Padding(
                padding: const EdgeInsets.only(left: 132, top: 2),
                child: Text(
                  '$id — $reason',
                  style: context.type.micro.copyWith(color: colors.mut2),
                ),
              ),
          if (load.error case var error?)
            Padding(
              padding: const EdgeInsets.only(left: 132, top: 2),
              child: Text(
                error.trimRight().split('\n').first,
                style: context.type.micro.copyWith(color: colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
