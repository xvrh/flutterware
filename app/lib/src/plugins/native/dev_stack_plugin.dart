import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../../dev_stack/stack_block.dart';
import '../../ui/action_button.dart';
import '../../ui/empty_state.dart';
import '../../ui/field_row.dart';
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DevStackBlock(plugin),
                if (core.commands.any((c) => c.argument != null)) ...[
                  const Gap(FwSpacing.xxl),
                  _WithArgument(core),
                ],
              ],
            ),
          ),
          Expanded(child: _Output(core)),
        ],
      ),
    );
  }
}

/// The commands that take an argument — `restart <service>`, `hit <path>`.
///
/// **This is where the block sends them, and for a while it sent them nowhere.**
/// [DevStackBlock] leaves an argument-taking command out of its row of links,
/// because a link is one click and guessing what to put in the blank is worse
/// than not offering it — but the panel it deferred to did not ask either, so
/// the command was declarable, callable from `fw` and from an agent, and
/// unreachable from the GUI entirely. Found by declaring one in the example
/// project rather than by reading the code.
///
/// Deliberately not on the worktree home, which is the compact form: a field to
/// fill in is not an answer to "is my stack up".
class _WithArgument extends StatefulWidget {
  const _WithArgument(this.core);

  final DevStackCore core;

  @override
  State<_WithArgument> createState() => _WithArgumentState();
}

class _WithArgumentState extends State<_WithArgument> {
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String id) =>
      _controllers.putIfAbsent(id, TextEditingController.new);

  /// Runs it, and swallows nothing: the future goes back to [FwActionButton],
  /// which is what turns a failure into a message rather than a green tick.
  Future<void> _run(StackCommand command) => widget.core.runCommand(
    command.id,
    argument: _controllerFor(command.id).text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var busy = widget.core.busy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var command in widget.core.commands)
          if (command.argument case var argument?)
            Padding(
              padding: const EdgeInsets.only(bottom: FwSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: FieldRow.defaultLabelWidth,
                        child: Text(command.label, style: type.bodyMuted),
                      ),
                      // Bounded rather than [Expanded]: a box for a service
                      // name or a path is a short answer, and one stretched
                      // across a wide window puts its Run button a screen away
                      // from the thing it runs.
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: _controllerFor(command.id),
                          style: type.bodySmall,
                          decoration: InputDecoration(
                            isDense: true,
                            // The argument's declared name, which is the only
                            // word anyone has for what goes in the blank.
                            hintText: argument,
                          ),
                          onSubmitted: busy
                              ? null
                              : (_) => unawaited(_run(command)),
                        ),
                      ),
                      const Gap(FwSpacing.lg),
                      FwActionButton(
                        label: 'Run',
                        onPressed: busy ? null : () => _run(command),
                      ),
                    ],
                  ),
                  if (command.description case var description?)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: FieldRow.defaultLabelWidth,
                        top: FwSpacing.xs,
                      ),
                      child: Text(description, style: type.caption),
                    ),
                  if (command.danger)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: FieldRow.defaultLabelWidth,
                        top: FwSpacing.xs,
                      ),
                      child: Text(
                        'this project marks it as destructive',
                        style: type.caption.copyWith(
                          color: context.colors.warningText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ],
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
