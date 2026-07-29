import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'shell_controller.dart';
import 'worktree.dart';

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
                // The headline only. The compiler's own output, the reload
                // button and the history all live on the config screen, and
                // this page promises to stay thin.
                Text(
                  error.message.trimRight().split('\n').first,
                  style: context.type.caption,
                ),
                const Gap(FwSpacing.sm),
                TextButton(
                  onPressed: shell.selectConfig,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Open config',
                    style: context.type.caption.copyWith(color: colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _short(String head) =>
      head.length <= 8 ? head : head.substring(0, 8);
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
