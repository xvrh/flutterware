import 'package:flutter/material.dart';

import '../../run/handle.dart';
import '../../ui/design/design.dart';
import '../../ui/empty_state.dart';
import '../../ui/theme.dart';
import '../../utils/daemon/device.dart';
import '../native_plugin.dart';
import 'run_core.dart';

export 'run_core.dart' show RunCore, runPluginId;

/// The GUI half of the run cockpit: a panel, and nothing else.
///
/// What is connected, what is busy and who holds it all lives in [RunCore], so
/// `fw` and an agent get the same answers from the same code. This class exists
/// because `buildPanel` returns a `Widget`.
class RunPlugin extends NativePlugin<RunCore> {
  RunPlugin(super.core);

  /// Starting a `flutter daemon` takes seconds, and the panel is empty for all
  /// of them. Without this a window capture photographs the empty state and
  /// reports it as the device list.
  @override
  String? get busyWith =>
      core.isLive || core.devices.isNotEmpty ? null : 'finding devices';

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
                    ? 'Plug in a phone, boot a simulator, or run on this desktop.'
                    : 'Starting a flutter daemon. This takes a few seconds.',
              )
            else
              for (var device in devices) ...[
                _DeviceRow(
                  device: device,
                  holders: [
                    for (var handle in _core.handles)
                      if (handle.device == device.id) handle,
                  ],
                  core: _core,
                ),
                const Gap(FwSpacing.sm),
              ],
          ],
        );
      },
    );
  }
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

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.holders,
    required this.core,
  });

  final DaemonDevice device;
  final List<RunHandle> holders;
  final RunCore core;

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
              child: _HolderRow(handle: handle, probe: core.probeOf(handle)),
            ),
          ],
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

/// One run holding this device — possibly from another worktree, which is the
/// case this whole row exists to make visible.
class _HolderRow extends StatelessWidget {
  const _HolderRow({required this.handle, this.probe});

  final RunHandle handle;
  final RunProbe? probe;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Row(
      children: [
        Icon(Icons.play_arrow_rounded, size: 14, color: colors.info),
        const Gap(FwSpacing.xs),
        Flexible(
          child: Text(
            handle.entrypointLabel,
            style: context.type.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Gap(FwSpacing.sm),
        _Chip(handle.worktreeName),
        const Gap(FwSpacing.sm),
        Text(
          _capability(probe),
          style: context.type.caption.copyWith(color: colors.mut2),
        ),
      ],
    );
  }

  /// The two-tier split, said plainly. An app whose launcher died keeps its
  /// tree and its screenshots and loses hot reload, and a row that only said
  /// "running" would hide exactly the difference the user is about to trip
  /// over.
  static String _capability(RunProbe? probe) => switch (probe) {
    null => 'not probed',
    _ when probe.canReload => 'reloadable',
    _ when probe.canInspect => 'no launcher',
    _ => 'starting',
  };
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
