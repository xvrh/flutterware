import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../../run/entrypoints.dart';
import '../../run/handle.dart';
import '../../run/launch.dart';
import '../../ui/design/design.dart';
import '../../ui/empty_state.dart';
import '../../ui/theme.dart';
import '../../utils/daemon/device.dart';
import '../native_plugin.dart';
import 'run_core.dart';

export 'run_core.dart' show RunCore, runPluginId;

/// The GUI half of the run cockpit: a panel, and nothing else.
///
/// What is connected, what is busy, who holds it and what launching does all
/// live in [RunCore], so `fw` and an agent get the same answers from the same
/// code. This class exists because `buildPanel` returns a `Widget`.
class RunPlugin extends NativePlugin<RunCore> {
  RunPlugin(super.core);

  /// Starting a `flutter daemon` takes seconds and a cold build takes minutes,
  /// and the panel is worth photographing for neither. Without this a window
  /// capture catches the empty state and reports it as the device list.
  @override
  String? get busyWith {
    if (!core.isLive && core.devices.isEmpty) return 'finding devices';
    if (core.isStarting) return 'building';
    return null;
  }

  @override
  Widget buildPanel(BuildContext context) => _RunPanel(this);
}

/// Mounting starts the daemon and the probe loop; unmounting leaves the daemon
/// alone, because it is shared with every other worktree in this window.
class _RunPanel extends StatefulWidget {
  const _RunPanel(this.plugin);

  final RunPlugin plugin;

  @override
  State<_RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<_RunPanel> {
  RunCore get _core => widget.plugin.core;

  /// Set while a launch is being spawned, so the button cannot be pressed
  /// twice into two `flutter run`s racing for one device.
  final _launching = <String>{};

  @override
  void initState() {
    super.initState();
    _core.track();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var devices = _core.devices;
        return ListView(
          padding: const EdgeInsets.all(FwSpacing.xl),
          children: [
            _Header(core: _core),
            const Gap(FwSpacing.lg),
            if (devices.isEmpty)
              EmptyState(
                icon: Icons.phonelink_outlined,
                title: _core.isLive
                    ? 'Nothing connected'
                    : 'Looking for devices',
                message: _core.isLive
                    ? 'Plug in a phone, boot a simulator, or run on this '
                          'desktop.'
                    : 'Starting a flutter daemon. This takes a few seconds.',
              )
            else
              for (var device in devices) ...[
                _DeviceCard(
                  device: device,
                  core: _core,
                  holders: [
                    for (var handle in _core.handles)
                      if (handle.device == device.id) handle,
                  ],
                  launching: _launching.contains(device.id),
                  onLaunch: (entry) => _launch(device, entry),
                  onControl: _control,
                ),
                const Gap(FwSpacing.sm),
              ],
          ],
        );
      },
    );
  }

  Future<void> _launch(DaemonDevice device, _Launchable launchable) async {
    var knobs = <String, String>{};
    if (launchable.entry.knobs.isNotEmpty) {
      var chosen = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _KnobDialog(
          core: _core,
          entry: launchable.entry,
          device: device.displayName,
        ),
      );
      if (chosen == null) return;
      knobs = chosen;
    }
    if (!mounted) return;
    setState(() => _launching.add(device.id));
    try {
      await _core.launch(
        device: device.id,
        package: launchable.package,
        entry: launchable.entry,
        knobs: knobs,
      );
    } on Object catch (e) {
      if (mounted) _say('Could not launch: $e');
    } finally {
      if (mounted) setState(() => _launching.remove(device.id));
    }
  }

  Future<void> _control(String action, RunHandle handle) async {
    try {
      await _core.control(action, handle);
    } on Object catch (e) {
      if (mounted) _say('$e');
    }
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _Header extends StatelessWidget {
  const _Header({required this.core});

  final RunCore core;

  @override
  Widget build(BuildContext context) {
    var busy = core.handles.map((h) => h.device).toSet().length;
    return Row(
      children: [
        Text('Devices', style: context.type.heading),
        const Gap(FwSpacing.md),
        Text(
          busy == 0 ? 'all free' : '$busy busy',
          style: context.type.bodyMuted,
        ),
        const Spacer(),
        // Said out loud rather than hidden: a list nobody is refreshing is a
        // list that can be wrong about a phone that was unplugged.
        Text(
          core.isLive ? 'live' : 'cached',
          style: context.type.caption.copyWith(color: context.colors.mut2),
        ),
      ],
    );
  }
}

/// One entry point, and the package it belongs to.
class _Launchable {
  const _Launchable(this.package, this.entry);

  final String package;
  final EntrypointRef entry;
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.core,
    required this.holders,
    required this.launching,
    required this.onLaunch,
    required this.onControl,
  });

  final DaemonDevice device;
  final RunCore core;
  final List<RunHandle> holders;
  final bool launching;
  final void Function(_Launchable) onLaunch;
  final void Function(String action, RunHandle handle) onControl;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(FwSpacing.lg),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(device), size: 18, color: colors.mut),
              const Gap(FwSpacing.md),
              Expanded(
                child: Text(
                  device.displayName,
                  style: context.type.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (device.isWireless) const _Chip('wireless'),
              if (!device.isConnected) const _Chip('not connected'),
              const Gap(FwSpacing.sm),
              Text(
                holders.isEmpty ? 'free' : 'busy',
                style: context.type.caption.copyWith(
                  color: holders.isEmpty ? colors.mut2 : colors.info,
                ),
              ),
            ],
          ),
          if (_subtitle(device).isNotEmpty) ...[
            const Gap(FwSpacing.xxs),
            Padding(
              padding: const EdgeInsets.only(left: 18 + FwSpacing.md),
              child: Text(_subtitle(device), style: context.type.bodyMuted),
            ),
          ],
          for (var handle in holders) ...[
            const Gap(FwSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(left: 18 + FwSpacing.md),
              child: _RunRow(
                handle: handle,
                probe: core.probeOf(handle),
                log: core.logOf(handle),
                mine: handle.worktreeName == core.host.worktree.name,
                onControl: onControl,
              ),
            ),
          ],
          const Gap(FwSpacing.md),
          Padding(
            padding: const EdgeInsets.only(left: 18 + FwSpacing.md),
            child: _LaunchBar(
              core: core,
              enabled: device.isConnected && !launching,
              launching: launching,
              onLaunch: onLaunch,
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(DaemonDevice device) => [
    ?device.platformType,
    ?device.sdk,
    if (device.emulator) 'emulator',
  ].join(' · ');

  static IconData _iconFor(DaemonDevice device) =>
      switch (device.platformType) {
        'ios' || 'android' => Icons.smartphone_outlined,
        'web' => Icons.language_outlined,
        _ => Icons.desktop_windows_outlined,
      };
}

/// The entry points this device can be given, one button each.
///
/// A row of buttons rather than a picker plus a Run button: with two or three
/// entry points — which is what a project has — naming the one you want *is*
/// the gesture, and a picker makes it two.
class _LaunchBar extends StatelessWidget {
  const _LaunchBar({
    required this.core,
    required this.enabled,
    required this.launching,
    required this.onLaunch,
  });

  final RunCore core;
  final bool enabled;
  final bool launching;
  final void Function(_Launchable) onLaunch;

  @override
  Widget build(BuildContext context) {
    var launchables = [
      for (var package in core.packages)
        for (var entry in core.entrypointsFor(package))
          _Launchable(package, entry),
    ];
    if (launchables.isEmpty) {
      return Text(
        'No entry points. Declare them in tool/flutterware.dart, or put a '
        'main() in the package’s lib/.',
        style: context.type.caption.copyWith(color: context.colors.mut2),
      );
    }
    if (launching) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.mut2,
            ),
          ),
          const Gap(FwSpacing.sm),
          Text('Starting…', style: context.type.caption),
        ],
      );
    }
    return Wrap(
      spacing: FwSpacing.sm,
      runSpacing: FwSpacing.xs,
      children: [
        for (var launchable in launchables)
          OutlinedButton.icon(
            onPressed: enabled ? () => onLaunch(launchable) : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(launchable.entry.name),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: context.type.caption,
            ),
          ),
      ],
    );
  }
}

/// One run on this device — possibly from another worktree, which is the case
/// this row exists to make visible.
class _RunRow extends StatelessWidget {
  const _RunRow({
    required this.handle,
    required this.mine,
    required this.onControl,
    this.probe,
    this.log,
  });

  final RunHandle handle;
  final RunProbe? probe;
  final LaunchLog? log;
  final bool mine;
  final void Function(String action, RunHandle handle) onControl;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var canReload = mine && (probe?.canReload ?? false);
    return Row(
      children: [
        Icon(Icons.play_arrow_rounded, size: 14, color: colors.info),
        const Gap(FwSpacing.xs),
        // `flex: 0` on both: a plain `Flexible` takes a *share* of the free
        // space like the `Spacer` does, which leaves the buttons stranded two
        // thirds of the way across instead of against the right edge. Loose
        // and unflexed means "your own size, and shrink if you must".
        Flexible(
          flex: 0,
          child: Text(
            handle.entrypointLabel,
            style: context.type.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Gap(FwSpacing.sm),
        if (!mine) ...[_Chip(handle.worktreeName), const Gap(FwSpacing.sm)],
        Flexible(
          flex: 0,
          child: Text(
            _state(),
            style: context.type.caption.copyWith(color: colors.mut2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        if (mine) ...[
          _Action(
            'Reload',
            Icons.bolt_outlined,
            enabled: canReload,
            onPressed: () => onControl('reload', handle),
          ),
          _Action(
            'Restart',
            Icons.refresh_rounded,
            enabled: canReload,
            onPressed: () => onControl('restart', handle),
          ),
          _Action(
            'Stop',
            Icons.stop_rounded,
            enabled: true,
            onPressed: () => onControl('stop', handle),
          ),
        ],
      ],
    );
  }

  /// The two-tier split, said plainly. An app whose launcher died keeps its
  /// tree and its screenshots and loses hot reload, and a row that only said
  /// "running" would hide exactly the difference the buttons are about to.
  String _state() {
    if (probe == null) return log?.summary ?? 'not probed';
    if (probe!.canReload) return 'reloadable';
    if (probe!.canInspect) return 'no launcher';
    return log?.summary ?? 'starting';
  }
}

class _Action extends StatelessWidget {
  const _Action(
    this.label,
    this.icon, {
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      icon: Icon(icon, size: 16),
      onPressed: enabled ? onPressed : null,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
    ),
  );
}

/// What to bake in before building.
///
/// Every knob is a text field, because a `--dart-define` is a string; the
/// difference the tool makes is the list under it. `from: KnobSource.servers`
/// fills that list with the base URLs of the servers running right now, and
/// `hostAddresses` with this machine's LAN addresses — so "point the app at my
/// dev server" is a click rather than a trip to `ifconfig`.
class _KnobDialog extends StatefulWidget {
  const _KnobDialog({
    required this.core,
    required this.entry,
    required this.device,
  });

  final RunCore core;
  final EntrypointRef entry;
  final String device;

  @override
  State<_KnobDialog> createState() => _KnobDialogState();
}

class _KnobDialogState extends State<_KnobDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (var knob in widget.entry.knobs)
      knob.define: TextEditingController(text: knob.defaultValue ?? ''),
  };

  @override
  void dispose() {
    for (var field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Run ${widget.entry.name} on ${widget.device}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These are compiled in, so changing one later costs a rebuild.',
              style: context.type.bodyMuted,
            ),
            const Gap(FwSpacing.lg),
            for (var knob in widget.entry.knobs) ...[
              _KnobField(
                knob: knob,
                options: widget.core.optionsFor(knob),
                controller: _fields[knob.define]!,
              ),
              const Gap(FwSpacing.md),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            for (var entry in _fields.entries)
              if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
          }),
          child: const Text('Run'),
        ),
      ],
    );
  }
}

class _KnobField extends StatelessWidget {
  const _KnobField({
    required this.knob,
    required this.options,
    required this.controller,
  });

  final LaunchKnob knob;
  final List<String> options;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(knob.label ?? knob.define, style: context.type.fieldLabel),
        if (knob.description != null)
          Text(knob.description!, style: context.type.caption),
        const Gap(FwSpacing.xxs),
        TextField(controller: controller),
        if (options.isNotEmpty) ...[
          const Gap(FwSpacing.xs),
          Wrap(
            spacing: FwSpacing.xs,
            runSpacing: FwSpacing.xxs,
            children: [
              for (var option in options)
                ActionChip(
                  label: Text(option, style: context.type.micro),
                  onPressed: () => controller.text = option,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: Text(label, style: context.type.micro.copyWith(color: colors.mut)),
    );
  }
}
