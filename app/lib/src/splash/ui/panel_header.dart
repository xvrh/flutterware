import 'package:flutter/material.dart';
import '../../capture/capture_mode.dart';
import '../../ui/theme.dart';

/// Whether anything on disk was made from the config, said in one phrase.
///
/// Three states rather than a bool, because "never run" and "run, then the
/// config moved" want different words *and* different colours — and the panel
/// spent a while saying the second as though it were an ordinary count.
enum SplashGeneratedState {
  /// `create` has never run in this package.
  never,

  /// Generated, and the config has not moved since.
  current,

  /// Generated, then the config was edited. What ships is the old splash.
  stale;

  String label(int files) => switch (this) {
    never => 'Never generated',
    current => '$files ${files == 1 ? 'file' : 'files'} generated',
    stale => 'Generated, then edited',
  };
}

/// The top of the panel: what is being looked at, and the two things you can do
/// to it.
///
/// A view — every value arrives as data and every action leaves as a callback.
///
/// **The package is the title, not the config file.** The rail already says
/// "Splash screen", so repeating the subject here would spend the largest type
/// on the one thing the reader already knows. What varies is which package and
/// which flavor, so those are what the eye lands on; the file it was read from
/// is provenance and sits in the subtitle with the clock.
class SplashPanelHeader extends StatelessWidget {
  const SplashPanelHeader({
    super.key,
    required this.package,
    required this.configPath,
    required this.state,
    required this.fileCount,
    this.fromPubspec = false,
    this.scannedAt,
    this.flavors = const [],
    this.selectedFlavor,
    this.onFlavor,
    this.onReload,
    this.onGenerate,
  });

  final String package;
  final String configPath;
  final bool fromPubspec;

  final SplashGeneratedState state;
  final int fileCount;

  /// When the panel last read the disk. Printed as a wall clock rather than
  /// "2 minutes ago", which would need a ticker to stay true — and a staleness
  /// display that is itself stale is worse than none.
  final DateTime? scannedAt;

  final List<String> flavors;
  final String? selectedFlavor;
  final ValueChanged<String?>? onFlavor;

  final VoidCallback? onReload;

  /// Null when a problem stops `create` from running at all — offering a button
  /// that is going to exit non-zero is worse than not offering one.
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.xxl,
            FwSpacing.xl,
            FwSpacing.xxl,
            FwSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      package,
                      style: type.pageTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(FwSpacing.lg),
                  _StatusPill(state: state, files: fileCount),
                ],
              ),
              const Gap(FwSpacing.xs),
              Text(
                [
                  configPath,
                  if (fromPubspec) 'from the pubspec section',
                  if (scannedAt != null && !CaptureMode.isCapturing(context))
                    'read at ${_clock(scannedAt!)}',
                ].join('  ·  '),
                style: type.caption.copyWith(color: colors.mut2),
              ),
              if (flavors.isNotEmpty) ...[
                const Gap(FwSpacing.lg),
                _Flavors(
                  flavors: flavors,
                  selected: selectedFlavor,
                  onSelect: onFlavor,
                ),
              ],
            ],
          ),
        ),
        _Toolbar(
          onReload: onReload,
          onGenerate: onGenerate,
          generated: state != SplashGeneratedState.never,
        ),
      ],
    );
  }
}

String _two(int value) => '$value'.padLeft(2, '0');

String _clock(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

/// The generation state, as a pill rather than as text floating at the far
/// right of the title row — which is where it was, and which on a wide window
/// left it stranded a screen away from the thing it describes.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, required this.files});

  final SplashGeneratedState state;
  final int files;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (fg, bg) = switch (state) {
      SplashGeneratedState.stale => (
        colors.amber,
        colors.amber.withValues(alpha: 0.12),
      ),
      SplashGeneratedState.current => (colors.accent, colors.accentSoft),
      SplashGeneratedState.never => (colors.mut, colors.panel2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state.label(files),
        style: context.type.micro.copyWith(color: fg),
      ),
    );
  }
}

/// The controls, on their own rule below the title.
///
/// Borrowed from the asset inspector: a bordered strip and real bordered
/// buttons, rather than the accent-coloured text links this panel used to call
/// controls.
///
/// **The device picker is not here.** It was, briefly, and it was a control that
/// looked global and applied to two tiles out of eight — a device belongs to a
/// platform, so an iOS phone can only ever redraw the iOS row. It lives on the
/// inspector now, where it is attached to one cell and offers only the screens
/// that cell can be.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.generated, this.onReload, this.onGenerate});

  final bool generated;
  final VoidCallback? onReload;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.line),
          bottom: BorderSide(color: colors.line),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xxl,
        vertical: FwSpacing.sm,
      ),
      child: Row(
        children: [
          const Spacer(),
          if (onReload != null)
            SplashToolbarButton(
              label: 'Reload',
              tooltip: 'Read the config and its images again',
              onPressed: onReload!,
            ),
          if (onGenerate != null) ...[
            const Gap(FwSpacing.md),
            SplashToolbarButton(
              label: generated
                  ? 'Re-run flutter_native_splash:create'
                  : 'Run flutter_native_splash:create',
              tooltip: 'Rewrites files under android/, ios/ and web/',
              primary: true,
              onPressed: onGenerate!,
            ),
          ],
        ],
      ),
    );
  }
}

/// A bordered control, which is what this app means by a button.
///
/// Public because the inspector uses it too, and two panels drawing their own
/// idea of a button is how the splash panel ended up with accent-coloured text
/// where every sibling has a bordered pill.
class SplashToolbarButton extends StatelessWidget {
  const SplashToolbarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.primary = false,
  });

  final String label;
  final String? tooltip;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(context.radii.radius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: primary ? colors.accentSoft : null,
          borderRadius: BorderRadius.circular(context.radii.radius),
          border: Border.all(color: primary ? colors.accent : colors.line),
        ),
        child: Text(
          label,
          style: context.type.caption.copyWith(
            color: primary ? colors.accent : colors.ink,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Which `flutter_native_splash-<flavor>.yaml` is being read.
///
/// Selectable now rather than a read-only badge: a project with flavors has one
/// config per flavor and the panel could only ever show whichever the address
/// happened to name.
class _Flavors extends StatelessWidget {
  const _Flavors({required this.flavors, this.selected, this.onSelect});

  final List<String> flavors;
  final String? selected;
  final ValueChanged<String?>? onSelect;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Wrap(
      spacing: FwSpacing.sm,
      runSpacing: FwSpacing.sm,
      children: [
        for (var (label, value) in [
          ('default', null),
          for (var flavor in flavors) (flavor, flavor),
        ])
          InkWell(
            onTap: onSelect == null ? null : () => onSelect!(value),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.lg,
                vertical: FwSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: value == selected ? colors.accentSoft : null,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: value == selected ? colors.accent : colors.line,
                ),
              ),
              child: Text(
                label,
                style: context.type.caption.copyWith(
                  color: value == selected ? colors.accent : colors.mut,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
