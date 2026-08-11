import 'dart:async';

import 'package:flutter/material.dart';

import '../plugins/native/dev_stack_core.dart';
import '../plugins/native/dev_stack_plugin.dart';
import '../plugins/native/dev_stack_results.dart';
import '../ui/action_button.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';

/// The stack, as one block: a section line, an answer, and its evidence.
///
/// **One widget, two homes.** The worktree home mounts it so "is my stack up"
/// costs no navigation, and the plugin panel mounts it above its commands and
/// output. Sharing the widget is what stops the two from disagreeing — a second
/// rendering of a state machine is a second set of six states to keep right.
///
/// It owns the subscription: mounting starts polling, unmounting stops it. That
/// is why [DevStackCore.watch] is reference-counted rather than a one-way
/// `track()` — this is a subprocess every ten seconds, and a worktree nobody is
/// looking at should not pay for one.
///
/// ## The layout, and what it is answering
///
/// See `docs/superpowers/specs/2026-08-11-dev-stack-ui-study.md`. The first
/// draft set the state, the address, the pid and the reading's age on one line
/// with identical separators and identical weight, under a heading, above a
/// `Tear down` button that was the loudest control on the whole worktree
/// overview. Four rules came out of redrawing it:
///
/// - **One state, one word, one colour, one place.** The state word is the only
///   thing here rendered in a tone colour, and it is set at heading size. Ports,
///   ages and paths go neutral.
/// - **Answer, then evidence.** The answer is the state and the one fact you act
///   on — the address, or the reason, or the failure. Services, freshness and
///   provenance are evidence: smaller, muted, and skippable.
/// - **Anatomical constancy.** Every state fills the same slots in the same
///   order, so the eye lands in the same spot whether the news is good or bad.
///   A failure takes the address's slot; it does not rearrange the block.
/// - **The safe direction gets the weight.** `Bring up` is filled when we know
///   the stack is down. `Tear down` is never anything but a quiet outline.
class DevStackBlock extends StatefulWidget {
  const DevStackBlock(
    this.plugin, {
    super.key,
    this.compact = false,
    this.onOpenPanel,
  });

  final DevStackPlugin plugin;

  /// The worktree home's form: no probe provenance, and a way into the panel
  /// instead of the commands the panel carries.
  ///
  /// It no longer drops the service list. That was the old compact form's worst
  /// idea — the one screen you glance at was the one that could not say *what*
  /// was up, while the panel you have to navigate to could.
  final bool compact;

  /// Navigates to this plugin's panel. Only used when [compact].
  final VoidCallback? onOpenPanel;

  @override
  State<DevStackBlock> createState() => _DevStackBlockState();
}

/// How wide the block is allowed to get.
///
/// A card has a reading width the same way a paragraph does. Left to fill a
/// maximised window it stretched to eleven hundred pixels, which put the
/// `Tear down` button most of a screen away from the `up` it belongs to — the
/// two halves of one statement, too far apart to be read as one.
const _maxWidth = 720.0;

class _DevStackBlockState extends State<DevStackBlock> {
  DevStackCore get _core => widget.plugin.core;

  /// Redraws the elapsed seconds during a transition, and nothing else.
  ///
  /// Runs only while something is in flight: a stack sitting `up` has no
  /// second-by-second fact to report, and a timer that ticks anyway is a
  /// rebuild per second per open worktree forever.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _core.watch();
    widget.plugin.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(DevStackBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin != widget.plugin) {
      oldWidget.plugin
        ..core.unwatch()
        ..removeListener(_syncTicker);
      _core.watch();
      widget.plugin.addListener(_syncTicker);
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.plugin.removeListener(_syncTicker);
    _core.unwatch();
    super.dispose();
  }

  void _syncTicker() {
    var wanted = _core.busy != null;
    if (wanted == (_tick != null)) return;
    _tick?.cancel();
    _tick = wanted
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
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
    var state = _shownState();
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionLine(context),
            const Gap(FwSpacing.md),
            _card(context, state),
          ],
        ),
      ),
    );
  }

  /// What labels the block rather than what is inside it.
  ///
  /// The name, the directory whose CLI is in charge, and how old the reading is
  /// all moved up here. They are facts *about* the answer, and beside it they
  /// were competing with it — `just now` set in the same weight as `up` reads as
  /// though the state were in doubt.
  Widget _sectionLine(BuildContext context) {
    var type = context.type;
    var label = _core.label;
    var subject = [
      if (label != 'Dev stack') label,
      ?_core.declaredDirectory,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'DEV STACK',
          style: type.fieldLabel.copyWith(color: context.colors.mut),
        ),
        if (subject.isNotEmpty) ...[
          const Gap(FwSpacing.md),
          Flexible(
            child: Text(
              subject,
              style: type.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const Spacer(),
        const Gap(FwSpacing.md),
        Text(_freshness(), style: type.caption),
      ],
    );
  }

  String _freshness() {
    var age = stackAge(_core.reading.at);
    var every = widget.compact
        ? ''
        : ' · every ${_core.pollInterval.inSeconds}s';
    if (age == null) return _core.isProbing ? 'checking…' : 'never checked';
    return 'checked $age$every';
  }

  /// The railed container: hairline all round, and one edge carrying the tone.
  ///
  /// State is encoded twice — the rail and the dot — because a colour is the
  /// first thing read and the last thing trusted. The rail is what makes a
  /// broken stack visible from the corner of the eye on a screen you opened for
  /// something else.
  Widget _card(BuildContext context, StackState state) {
    var colors = context.colors;
    var evidence = _evidence(context, state);
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radius),
      ),
      // Clipped rather than a coloured left border: Flutter refuses a
      // borderRadius on a border whose sides differ, so the rail is a child
      // cut to the corner radius instead.
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: _railColor(colors, state)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _answerRow(context, state),
                    if (state.isMoving) ...[
                      const Gap(FwSpacing.lg),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: colors.line,
                          color: colors.amber,
                        ),
                      ),
                    ],
                    if (evidence != null) ...[
                      const Gap(FwSpacing.lg),
                      // The rule only earns its place when there is a list
                      // under it. Above a row holding nothing but the way out,
                      // it draws a compartment around an empty space.
                      Container(
                        padding: EdgeInsets.only(
                          top: _core.reading.services.isEmpty
                              ? 0
                              : FwSpacing.lg,
                        ),
                        decoration: _core.reading.services.isEmpty
                            ? null
                            : BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: colors.line),
                                ),
                              ),
                        child: evidence,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The answer on the left, what to do about it on the right.
  Widget _answerRow(BuildContext context, StackState state) {
    var colors = context.colors;
    var type = context.type;
    var detail = _detail(context, state);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _StateDot(state, muted: _isUnconfirmed),
                  const Gap(FwSpacing.md),
                  Flexible(
                    child: Text(
                      _word(state),
                      style: type.heading.copyWith(
                        fontSize: type.sizeHeadlineMedium,
                        color: _isUnconfirmed
                            ? colors.mut2
                            : _wordColor(colors, state),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (detail != null) ...[
                const Gap(FwSpacing.xs),
                Padding(
                  // Hangs under the word rather than under the dot, so the two
                  // lines read as one statement.
                  padding: const EdgeInsets.only(left: 8 + FwSpacing.md),
                  child: Text(
                    detail.$1,
                    style: type.caption.copyWith(color: detail.$2),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Gap(FwSpacing.lg),
        _controls(context, state),
      ],
    );
  }

  /// One link and one button, in that order, right-aligned.
  ///
  /// The link is `Check now` whenever the *reading* is the problem — the probe
  /// failed, or what we hold is old — because then re-reading is the next move.
  /// Otherwise the compact form offers the stack's first one-click command,
  /// which is the thing worth having beside a running stack when the panel with
  /// the rest of them is a navigation away; the panel offers `Check now`, since
  /// its commands are already on screen below.
  Widget _controls(BuildContext context, StackState state) {
    var busy = _core.busy != null;
    var shortcut = _shortcutCommand(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (shortcut != null) ...[
          _Link(shortcut.$1, enabled: !busy, onTap: shortcut.$2),
          const Gap(FwSpacing.lg),
        ],
        ?_primary(state),
      ],
    );
  }

  (String, VoidCallback)? _shortcutCommand(StackState state) {
    if (state == StackState.unavailable || _isUnconfirmed || !widget.compact) {
      return ('Check now', () => unawaited(_core.refresh()));
    }
    var command = _core.commands.where((c) => c.argument == null).firstOrNull;
    if (command == null) return ('Check now', () => unawaited(_core.refresh()));
    return (command.label, () => unawaited(_core.runCommand(command.id)));
  }

  /// The control that changes the state, or null when the project declared
  /// none — a stack this machine only observes gets a status and no buttons,
  /// which is a complete declaration rather than a degraded one.
  Widget? _primary(StackState state) {
    // A reading nobody has confirmed this session is history, and acting on
    // history is what the muted rendering is warning about. The probe lands in
    // a moment; until it does, both directions are off.
    var off = _core.busy != null || _isUnconfirmed;
    if (state.isMoving) {
      return FwActionButton(
        label: state == StackState.starting ? 'Bringing up' : 'Tearing down',
        onPressed: null,
      );
    }
    if (state == StackState.up) {
      if (!_core.canStop) return null;
      return FwActionButton(
        label: 'Tear down',
        tooltip: _core.stopIsDestructive
            ? 'Asks first — this destroys data'
            : null,
        onPressed: off ? null : _stop,
      );
    }
    if (!_core.canStart) return null;
    // Down, unknown and unavailable all offer the same control, deliberately:
    // after a failed probe the useful move is to try, and the command's own
    // error explains more than a disabled button does. Only `down` fills it —
    // when we cannot tell, an emphatic button would be promising an outcome
    // nothing has checked.
    return FwActionButton(
      label: 'Bring up',
      primary: state == StackState.down,
      onPressed: off ? null : () => _core.start(),
    );
  }

  /// Services and the way into the panel. Null when there is neither.
  Widget? _evidence(BuildContext context, StackState state) {
    var colors = context.colors;
    var type = context.type;
    var services = _core.reading.services;
    var openPanel = widget.compact && widget.onOpenPanel != null;
    if (services.isEmpty && !openPanel) return null;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: FwSpacing.xl,
            runSpacing: FwSpacing.sm,
            children: [
              for (var service in services)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StateDot(
                      service.state ?? StackState.unknown,
                      size: 6,
                      muted: _isUnconfirmed,
                    ),
                    const Gap(FwSpacing.sm),
                    Text(
                      service.port == null
                          ? service.name
                          : '${service.name} :${service.port}',
                      style: type.caption.copyWith(color: colors.mut),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (openPanel) ...[
          const Gap(FwSpacing.lg),
          _Link('Open panel →', quiet: true, onTap: widget.onOpenPanel!),
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

  /// True while what is on screen is history rather than a confirmed state: a
  /// cache read at startup, or nothing at all. Drawn muted, with controls off,
  /// for the half-second until the first probe of the session lands.
  bool get _isUnconfirmed =>
      _core.busy == null && (!_core.reading.isKnown || _core.isStale);

  String _word(StackState state) {
    var reading = _core.reading;
    return switch (state) {
      StackState.unknown => _core.isProbing ? 'checking' : 'not checked',
      StackState.down => 'down',
      StackState.starting => 'bringing up',
      StackState.up when reading.isPartial =>
        'up, ${reading.serviceCount!.$1} of ${reading.serviceCount!.$2}',
      StackState.up => 'up',
      StackState.stopping => 'tearing down',
      StackState.unavailable => "can't tell",
    };
  }

  /// The line under the word: the one fact that makes the state actionable.
  ///
  /// Every state fills it, which is the whole reason it is a slot rather than a
  /// suffix — a failure lands where the address was, and the eye does not have
  /// to go looking.
  (String, Color)? _detail(BuildContext context, StackState state) {
    var colors = context.colors;
    var reading = _core.reading;
    if (state.isMoving) {
      var seconds = _core.busyFor?.inSeconds ?? 0;
      return ('${seconds}s elapsed', colors.mut);
    }
    if (state == StackState.unavailable) {
      return (reading.failure ?? 'the check could not be run', colors.red);
    }
    if (!reading.isKnown) {
      return (
        _core.isProbing ? 'running the first check…' : 'no reading yet',
        colors.mut,
      );
    }
    if (_core.isStale) {
      var age = stackAge(reading.at);
      return (
        [
          if (age != null) 'last seen $age',
          if (_core.isProbing) 'checking now',
        ].join(' · '),
        colors.mut,
      );
    }
    var detail = reading.detail?.trim();
    if (detail == null || detail.isEmpty) return null;
    return (detail, colors.mut);
  }

  Color _wordColor(FwPalette colors, StackState state) => switch (state) {
    StackState.up => colors.grn,
    StackState.starting || StackState.stopping => colors.amber,
    StackState.unavailable => colors.red,
    _ => colors.ink2,
  };

  Color _railColor(FwPalette colors, StackState state) => switch (state) {
    StackState.up => _core.reading.isPartial ? colors.amber : colors.grn,
    StackState.starting || StackState.stopping => colors.amber,
    StackState.unavailable => colors.red,
    // Down is not a fault and does not get an edge — a checkout you are not
    // working in *should* have its stack down.
    _ => colors.line2,
  };
}

class _StateDot extends StatelessWidget {
  const _StateDot(this.state, {this.size = 8, this.muted = false});

  final StackState state;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = switch (state) {
      StackState.up => colors.grn,
      StackState.starting || StackState.stopping => colors.amber,
      StackState.unavailable => colors.red,
      StackState.down => colors.mut3,
      StackState.unknown => colors.mut3,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: muted ? colors.mut3 : color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A text control that admits to being one.
///
/// The first draft set these as plain ink at body size, which is the same
/// treatment as the sentence above them — you found out they were buttons by
/// hovering. The rule underneath is the second finding of the study: an
/// affordance you have to discover is not an affordance.
class _Link extends StatelessWidget {
  const _Link(
    this.label, {
    this.enabled = true,
    this.quiet = false,
    required this.onTap,
  });

  final String label;
  final bool enabled;

  /// Navigation rather than action — set muted, so it does not compete with the
  /// control beside it.
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = !enabled
        ? colors.mut3
        : quiet
        ? colors.mut
        : colors.ink2;
    return Tappable(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: enabled ? colors.line2 : colors.line),
            ),
          ),
          child: Text(label, style: context.type.body.copyWith(color: color)),
        ),
      ),
    );
  }
}
