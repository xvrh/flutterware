import 'package:flutter/material.dart';

import '../../dev_stack/stack_block.dart';
import '../../ui/empty_state.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import 'dev_stack_core.dart';

/// The dev stack's panel: the same block the worktree home shows, plus the one
/// thing that does not belong on a home screen — what the last command printed.
class DevStackPlugin extends NativePlugin<DevStackCore> {
  DevStackPlugin(super.core);

  @override
  String? get busyWith => core.busyWith;

  @override
  Widget buildPanel(BuildContext context) => _DevStackPanel(this);
}

class _DevStackPanel extends StatelessWidget {
  const _DevStackPanel(this.plugin);

  final DevStackPlugin plugin;

  @override
  Widget build(BuildContext context) {
    var core = plugin.core;
    return AnimatedBuilder(
      animation: plugin,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(FwSpacing.xxxl),
            child: DevStackBlock(plugin),
          ),
          Expanded(child: _Output(core)),
        ],
      ),
    );
  }
}

/// What the last command printed.
///
/// Not a log viewer, and deliberately not one: the stack's own `logs` command
/// is declared right beside this and streams the real thing in a terminal that
/// can scroll, search and stay open. This is the tail of the command *this
/// panel* just ran, which is the output nobody else has.
class _Output extends StatelessWidget {
  const _Output(this.core);

  final DevStackCore core;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    if (core.lastCommand == null) {
      return EmptyState(
        title: 'Nothing has been run from here yet.',
        message:
            'The state above comes from `${core.declaredProbeCommand ?? 'no probe declared'}`, '
            'which runs on its own while this panel is open. Anything you run '
            'from the controls prints here.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.xxxl,
              vertical: FwSpacing.lg,
            ),
            child: Row(
              children: [
                Text('Output', style: type.fieldLabel),
                const Gap(FwSpacing.lg),
                Expanded(
                  child: SelectableText(
                    core.lastCommand!,
                    style: type.caption,
                    maxLines: 1,
                  ),
                ),
                if (core.busy != null) Text('running…', style: type.caption),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                FwSpacing.xxxl,
                0,
                FwSpacing.xxxl,
                FwSpacing.xxxl,
              ),
              child: SelectableText(
                core.lastOutput.isEmpty ? '(no output)' : core.lastOutput,
                style: type.caption.copyWith(
                  fontFamily: 'monospace',
                  color: colors.mut,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
