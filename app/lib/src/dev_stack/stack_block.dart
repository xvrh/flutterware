import 'package:flutter/material.dart';

import '../plugins/native/dev_stack_core.dart';
import '../plugins/native/dev_stack_plugin.dart';
import '../plugins/native/dev_stack_results.dart';
import '../ui/action_button.dart';
import '../ui/theme.dart';

/// The stack, as one block: a state line, one control, and the rest as links.
///
/// **One widget, two homes.** The worktree home mounts it so "is my stack up"
/// costs no navigation, and the plugin panel mounts it above its output pane.
/// Sharing the widget is what stops the two from disagreeing — a second
/// rendering of a state machine is a second set of five states to keep right.
///
/// It owns the subscription: mounting starts polling, unmounting stops it. That
/// is why [DevStackCore.watch] is reference-counted rather than a one-way
/// `track()` — this is a subprocess every ten seconds, and a worktree nobody is
/// looking at should not pay for one.
class DevStackBlock extends StatefulWidget {
  const DevStackBlock(this.plugin, {super.key, this.compact = false});

  final DevStackPlugin plugin;

  /// Drops the working directory and the service list. What the home screen
  /// wants: the answer, not the file.
  final bool compact;

  @override
  State<DevStackBlock> createState() => _DevStackBlockState();
}

class _DevStackBlockState extends State<DevStackBlock> {
  DevStackCore get _core => widget.plugin.core;

  @override
  void initState() {
    super.initState();
    _core.watch();
  }

  @override
  void didUpdateWidget(DevStackBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin != widget.plugin) {
      oldWidget.plugin.core.unwatch();
      _core.watch();
    }
  }

  @override
  void dispose() {
    _core.unwatch();
    super.dispose();
  }

  /// Asks first, and only for a stop the project marked as destructive.
  ///
  /// The dialog says what is lost rather than "are you sure": nobody has ever
  /// answered "are you sure" with new information.
  Future<void> _stop() async {
    if (!_core.stopIsDestructive) {
      await _core.stop();
      return;
    }
    var confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tear down ${_core.label}?'),
        content: const Text(
          'This project marks its stop command as destroying data. Containers '
          'and their volumes go with it, and the next bring-up starts from '
          'empty.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Tear down',
              style: TextStyle(color: context.colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await _core.stop();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.plugin,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    var reading = _core.reading;
    var state = _shownState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_core.label, style: type.heading),
            // Who is actually in charge. Worth a permanent line when there is
            // one to give: when the stack misbehaves, this is the difference
            // between debugging the project's CLI and debugging flutterware.
            // Omitted rather than padded out when nothing was declared — "this
            // worktree" told you where you already are.
            if (_core.declaredDirectory case var directory?) ...[
              const Gap(FwSpacing.md),
              Flexible(
                child: Text(
                  'delegated to $directory',
                  style: type.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const Gap(FwSpacing.md),

        // The dot carries the tone, the words carry the fact, and the age comes
        // last because it qualifies everything before it.
        Row(
          children: [
            _StateDot(state),
            const Gap(FwSpacing.md),
            Flexible(
              child: Text(
                _stateLine(reading, state),
                style: type.body.copyWith(
                  color: state == StackState.unavailable
                      ? colors.red
                      : colors.ink2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        if (!widget.compact && reading.services.isNotEmpty) ...[
          const Gap(FwSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: FwSpacing.xl),
            child: Text(
              [
                for (var service in reading.services)
                  service.port == null
                      ? service.name
                      : '${service.name} ${service.port}',
              ].join(' · '),
              style: type.caption,
            ),
          ),
        ],

        if (_core.canControl) ...[
          const Gap(FwSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _primary(state),
              if (_note(state) case var note?) ...[
                const Gap(FwSpacing.lg),
                Flexible(
                  child: Text(
                    note,
                    style: type.caption.copyWith(color: colors.warningText),
                  ),
                ),
              ],
            ],
          ),
        ],

        if (_secondary().isNotEmpty) ...[
          const Gap(FwSpacing.lg),
          Wrap(
            spacing: FwSpacing.xl,
            runSpacing: FwSpacing.sm,
            children: _secondary(),
          ),
        ],

        if (!widget.compact) ...[
          const Gap(FwSpacing.xl),
          SelectableText(_core.workingDirectory, style: type.caption),
        ],
      ],
    );
  }

  /// What to show, which is not always what the last probe said — a transition
  /// in flight wins, because during those seconds the probe is the stale one.
  StackState _shownState() => switch (_core.busy) {
    'start' => StackState.starting,
    'stop' => StackState.stopping,
    _ => _core.reading.state,
  };

  String _stateLine(StackReading reading, StackState state) => [
    switch (state) {
      StackState.unknown => 'not checked yet',
      StackState.down => 'down',
      StackState.starting => 'bringing up…',
      StackState.up => 'up',
      StackState.stopping => 'tearing down…',
      StackState.unavailable => reading.failure ?? 'the check could not be run',
    },
    if (state == StackState.up || state == StackState.down)
      if (reading.detail case var detail?)
        if (detail.isNotEmpty) detail,
    if (!state.isMoving) ?stackAge(reading.at),
  ].join('  ·  ');

  Widget _primary(StackState state) => switch (state) {
    StackState.starting || StackState.stopping => FwActionButton(
      label: state == StackState.starting ? 'Bringing up…' : 'Tearing down…',
      onPressed: null,
    ),
    StackState.up => FwActionButton(
      label: 'Tear down',
      tooltip: _core.stopIsDestructive
          ? 'Asks first — this destroys data'
          : null,
      onPressed: _core.busy == null ? _stop : null,
    ),
    // Down, unknown and unavailable all offer the same control, deliberately:
    // after a failed probe the useful move is to try, and the command's own
    // error explains more than a disabled button does.
    _ => FwActionButton(
      label: 'Bring up',
      primary: true,
      onPressed: _core.busy == null ? () => _core.start() : null,
    ),
  };

  String? _note(StackState state) => switch (state) {
    StackState.up when _core.stopIsDestructive =>
      'wipes volumes — the next bring-up starts from empty',
    StackState.unavailable => 'the last check failed, so this may not work',
    _ => null,
  };

  /// The declared commands, plus a manual re-probe. A command that takes an
  /// argument is not offered here — it cannot be one click, and guessing the
  /// value is worse than sending you to the panel that asks for it.
  List<Widget> _secondary() => [
    for (var command in _core.commands)
      if (command.argument == null)
        _Link(
          command.label,
          enabled: _core.busy == null,
          danger: command.danger,
          onTap: () => _core.runCommand(command.id),
        ),
    _Link('Check now', enabled: _core.busy == null, onTap: _core.refresh),
  ];
}

class _StateDot extends StatelessWidget {
  const _StateDot(this.state);

  final StackState state;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: switch (state) {
          StackState.up => colors.grn,
          StackState.starting || StackState.stopping => colors.amber,
          StackState.unavailable => colors.red,
          _ => colors.mut3,
        },
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(
    this.label, {
    required this.onTap,
    this.enabled = true,
    this.danger = false,
  });

  final String label;
  final Future<void> Function() onTap;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Text(
          label,
          style: context.type.body.copyWith(
            color: !enabled
                ? colors.mut3
                : danger
                ? colors.red
                : colors.ink2,
          ),
        ),
      ),
    );
  }
}
