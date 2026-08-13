import 'package:flutter/material.dart';

import '../dev_stack/stack_block.dart';
import '../plugins/native/dev_stack_core.dart';
import '../plugins/native/dev_stack_plugin.dart';
import '../plugins/worktree_session.dart';
import '../ui/panel_header.dart';
import '../ui/theme.dart';
import 'worktree.dart';

/// What a worktree opens on, instead of whichever plugin happened to be first.
///
/// Deliberately thin, and deliberately not a plugin list — the sidebar already
/// is one. What is here is what only the shell knows: which checkout this is.
/// Everything on it is free.
///
/// It used to also carry the config failure. The band banner above it now says
/// that on every screen rather than only this one, so keeping a copy here meant
/// rendering the same sentence twice on the one screen where both are visible.
///
/// **"Everything on it is free" now has one exception, declared by the
/// project.** A worktree that declares a `DevStack` gets its state here,
/// because "which port block does this checkout hold, and is it up" is a fact
/// about *this worktree* in the strictest sense — it is allocated per worktree,
/// by name — and this is the screen that names the worktree. The cost is one
/// subprocess per [DevStack.poll] **while this screen is on**: the block starts
/// polling when it mounts and stops when it leaves, so a worktree open in a
/// background tab pays nothing, and a project with no stack declared sees
/// exactly what it saw before.
class WorktreeHome extends StatelessWidget {
  const WorktreeHome(
    this.worktree, {
    super.key,
    this.session,
    this.onOpenPlugin,
  });

  final Worktree worktree;

  /// Navigates to a plugin's panel. Null for a caller with no shell — the
  /// block then draws without its way out, rather than with a link that does
  /// nothing.
  final void Function(String pluginId)? onOpenPlugin;

  /// The open session, when there is one. Null before the config resolves, and
  /// for any caller that has only the worktree — the screen degrades to what it
  /// always was rather than refusing to draw.
  final WorktreeSession? session;

  /// The stack panel for this worktree, or null when none is declared or the
  /// session has not landed. Read through the plugin rather than the core so
  /// the block subscribes to the same notifier the sidebar does.
  DevStackPlugin? get _stack {
    var plugin = session?.pluginById(devStackPluginId);
    return plugin is DevStackPlugin ? plugin : null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: FwSpacing.xxxl),
      children: [
        FwPanelHeader(
          worktree.displayName,
          subtitle: [worktree.path],
          // A path is the thing most likely to be wanted in a terminal a moment
          // later.
          selectableSubtitle: true,
          below: Wrap(
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
        ),

        if (_stack case var stack?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              panelGutter,
              FwSpacing.lg,
              panelGutter,
              0,
            ),
            child: DevStackBlock(
              stack,
              form: DevStackForm.strip,
              onOpenPanel: onOpenPlugin == null
                  ? null
                  : () => onOpenPlugin!(devStackPluginId),
            ),
          ),
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
              Icon(icon, size: FwIconSize.xs, color: colors.mut),
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
