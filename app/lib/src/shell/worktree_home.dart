import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'config_load.dart';
import 'shell_controller.dart';
import 'worktree.dart';

/// The reload history section on a worktree's home screen.
const configLogKey = Key('config-log');

/// What a worktree opens on, instead of whichever plugin happened to be first.
///
/// Deliberately thin, and deliberately not a plugin list — the sidebar already
/// is one. What is here is what only the shell knows: which checkout this is,
/// and why its config did not load when it did not. Everything on it is free.
class WorktreeHome extends StatelessWidget {
  const WorktreeHome(this.shell, this.worktree, {super.key});

  final ShellController shell;
  final Worktree worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var error = shell.errorFor(worktree);

    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xxxl),
      children: [
        Text(worktree.displayName, style: context.type.pageTitle),
        const Gap(FwSpacing.sm),
        SelectableText(worktree.path, style: context.type.caption),
        const Gap(FwSpacing.xl),

        Wrap(
          spacing: FwSpacing.md,
          runSpacing: FwSpacing.md,
          children: [
            _Chip(worktree.isMain ? 'main checkout' : 'linked worktree'),
            if (worktree.branch case var branch?)
              _Chip(branch, icon: Icons.call_split)
            else if (worktree.head case var head?)
              _Chip('detached at ${_short(head)}'),
          ],
        ),

        if (error != null) ...[
          const Gap(FwSpacing.xxl),
          Container(
            padding: const EdgeInsets.all(FwSpacing.lg),
            decoration: BoxDecoration(
              border: Border.all(color: colors.red),
              borderRadius: BorderRadius.circular(context.radii.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This worktree’s config could not be read',
                  style: context.type.bodyStrong.copyWith(color: colors.red),
                ),
                const Gap(FwSpacing.sm),
                SelectableText(error.message, style: context.type.caption),
              ],
            ),
          ),
        ],

        if (shell.loadLog(worktree) case var log when log.isNotEmpty)
          Padding(
            key: configLogKey,
            padding: const EdgeInsets.only(top: FwSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Config', style: context.type.sectionLabel),
                const Gap(FwSpacing.sm),
                for (var load in log) _LoadRow(load),
              ],
            ),
          ),
      ],
    );
  }

  static String _short(String head) =>
      head.length <= 8 ? head : head.substring(0, 8);
}

/// One run of `tool/flutterware.dart`, and what it cost.
///
/// **The diff, made visible.** Without this the reconciliation is a black box
/// you have to trust: a plugin quietly disappears and reappears and nothing says
/// which config key moved. This is what answers "why did my device just die",
/// which is the question a surgical reload creates by being surgical.
class _LoadRow extends StatelessWidget {
  const _LoadRow(this.load);

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

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      // Capped: a Wrap hands its children unbounded width, so a chip carrying
      // a long branch name would run off the panel rather than wrap.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: colors.mut),
              const Gap(FwSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: context.type.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
