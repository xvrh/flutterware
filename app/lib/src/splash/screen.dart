import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../capture/capture_mode.dart';
import '../plugins/native/splash_core.dart';
import '../ui/theme.dart';
import 'model/config.dart';
import 'model/scan.dart';
import 'model/surface.dart';
import 'model/validation.dart';
import 'ui/artifacts_view.dart';
import 'ui/variant_tile.dart';

/// The whole matrix at once: four surfaces, two themes, side by side.
///
/// Showing them together is the point. Any one of these is easy to get from a
/// device; what nobody can hold in their head is that the same eight lines of
/// YAML produce *these eight pictures*, and that two of them are usually not
/// what the author expected.
class SplashScreen extends StatelessWidget {
  const SplashScreen(
    this.core, {
    super.key,
    required this.package,
    this.flavor,
    this.surface,
    this.theme,
    this.device,
    this.onSelectCell,
    this.onShowAll,
  });

  final SplashCore core;
  final String package;

  /// Which `flutter_native_splash-<flavor>.yaml`, from the address.
  final String? flavor;

  /// The cell the address names, if it names one. Highlighted rather than shown
  /// alone — the comparison is the feature.
  final SplashSurface? surface;
  final SplashTheme? theme;

  /// `?device=`, or null for each surface's own default.
  final String? device;

  /// Writes the two axes. Supplied by the plugin, which is the half that sits
  /// inside an `AddressScope`; null in a test that mounts this screen on its
  /// own, where navigating means nothing.
  final void Function(SplashSurface, SplashTheme)? onSelectCell;

  /// Clears them again — back to the matrix.
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    var failure = core.failureFor(package);
    if (failure != null) return _Message(failure, tone: Tone.error);

    var scan = core.scanFor(package);
    if (scan == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (scan.configErrors.isNotEmpty) {
      return _Message(scan.configErrors.join('\n\n'), tone: Tone.error);
    }

    if (!scan.isConfigured) {
      return const _Message(
        'No flutter_native_splash config in this package.\n\n'
        'Add a `flutter_native_splash:` section to pubspec.yaml, or a '
        'flutter_native_splash.yaml beside it.',
      );
    }

    var config = scan.forFlavor(flavor) ?? scan.main!;

    // The one thing this panel writes, and it writes nothing of its own: it
    // runs the generator. Confirmed first, because it rewrites files under
    // android/, ios/ and web/, and the count of them is the part nobody
    // expects.
    void runCreate() => unawaited(() async {
      var go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Run flutter_native_splash:create?'),
          content: Text(
            'Generates the splash from ${config.config.path} and rewrites '
            'files under android/, ios/ and web/.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Run it'),
            ),
          ],
        ),
      );
      if (go != true) return;
      await core.invoke(
        'generate',
        arguments: {
          'package': package,
          if (config.config.flavor != null) 'flavor': config.config.flavor,
        },
      );
    }());

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _Header(
          scan: scan,
          config: config,
          selected: flavor,
          scannedAt: core.scannedAt(package),
          onReload: () =>
              unawaited(core.invoke('reload', arguments: {'package': package})),
          onGenerate: config.blocksGeneration ? null : runCreate,
        ),
        const SizedBox(height: 20),
        // An address naming both axes names one cell, so show that cell rather
        // than outlining it inside seven others. It is also what makes
        // `fw capture …?surface=android12&theme=dark` produce a picture worth
        // looking at instead of a thumbnail with a blue border.
        if (surface != null && theme != null)
          _SingleCell(
            config: config,
            surface: surface!,
            theme: theme!,
            device: device,
            onShowAll: onShowAll,
          )
        else ...[
          _Matrix(
            config: config,
            surface: surface,
            theme: theme,
            device: device,
            onSelect: onSelectCell,
          ),
          if (config.problems.isNotEmpty) ...[
            const SizedBox(height: 28),
            _Problems(config.problems),
          ],
          const SizedBox(height: 28),
          SplashArtifactsView(
            artifacts: config.artifacts,
            packageRoot: core.packageRootFor(package),
            stale: config.stale,
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.scan,
    required this.config,
    this.selected,
    this.scannedAt,
    this.onReload,
    this.onGenerate,
  });

  final SplashScan scan;
  final SplashConfigScan config;
  final String? selected;

  /// When the panel last read the disk. Printed as a wall-clock time rather
  /// than "2 minutes ago", which would need a ticker to stay true — and a
  /// staleness display that is itself stale is worse than none.
  final DateTime? scannedAt;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(config.config.path, style: type.heading),
            const SizedBox(width: 8),
            if (config.config.kind == SplashConfigKind.pubspec)
              Text(
                'from the pubspec section',
                style: type.caption.copyWith(color: colors.mut),
              ),
            const Spacer(),
            Text(
              config.isGenerated
                  ? config.stale
                        ? 'Generated, then edited'
                        : '${config.artifacts.length} files generated'
                  // Not "never generated", which reads as a property of the
                  // config rather than as a thing you have not done yet.
                  : 'create has never run — this is a prediction',
              style: type.caption.copyWith(
                color: config.stale ? colors.amber : colors.mut,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // A wall clock is the textbook thing `CaptureMode` exists for: it
            // changes on every run and means nothing about the project, so a
            // committed screenshot would churn on each regeneration. The button
            // stays — it is part of what the panel *is*.
            if (scannedAt != null && !CaptureMode.isCapturing(context))
              Text(
                'Read at ${_clock(scannedAt!)}',
                style: type.micro.copyWith(color: colors.mut3),
              ),
            const SizedBox(width: 8),
            if (onReload != null) _ReloadButton(onPressed: onReload!),
            // Offered whenever anything on screen is a prediction rather than a
            // readback — which is the only state where a reader has a question
            // this button answers.
            if (onGenerate != null &&
                (!config.isGenerated || config.stale)) ...[
              const SizedBox(width: 8),
              _LinkButton(
                label: config.isGenerated
                    ? 'Re-run flutter_native_splash:create'
                    : 'Run flutter_native_splash:create',
                onPressed: onGenerate!,
              ),
            ],
          ],
        ),
        if (scan.flavors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (var entry in scan.configs)
                _FlavorChip(
                  label: entry.config.flavor ?? 'default',
                  selected: entry.config.flavor == selected,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _two(int value) => '$value'.padLeft(2, '0');

String _clock(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

/// The manual re-read.
///
/// **Permanent, not a fallback for when detection breaks.** Polling can miss an
/// edit on a network mount or a filesystem with coarse mtimes, and the failure
/// is silent — a stale preview looks exactly like a correct one. A button that
/// is always there costs one row and removes the whole class of "I don't trust
/// what this is showing me".
class _ReloadButton extends StatelessWidget {
  const _ReloadButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tooltip(
      message: 'Read the config and its images again',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            'Reload',
            style: context.type.micro.copyWith(color: colors.accent),
          ),
        ),
      ),
    );
  }
}

class _FlavorChip extends StatelessWidget {
  const _FlavorChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.panel2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? colors.accent : colors.line),
      ),
      child: Text(label, style: context.type.caption),
    );
  }
}

/// Surfaces across, themes down.
///
/// Laid out as a `Wrap` rather than a fixed grid so a narrow panel reflows
/// instead of squeezing eight phones into a column too thin to read.
class _Matrix extends StatelessWidget {
  const _Matrix({
    required this.config,
    this.surface,
    this.theme,
    this.device,
    this.onSelect,
  });

  final SplashConfigScan config;
  final SplashSurface? surface;
  final SplashTheme? theme;
  final String? device;
  final void Function(SplashSurface, SplashTheme)? onSelect;

  /// The screen a surface draws as.
  ///
  /// **Resolved per surface, not once for the matrix.** The address carries one
  /// `?device=`, but an iPhone is not a canvas for the Android tiles — asking
  /// for an iPhone SE and getting the Android row redrawn at 375×667 would be a
  /// picture of a phone that does not exist. So a chosen device applies to the
  /// surfaces of its own platform and the rest keep their defaults.
  Device? _deviceFor(SplashSurface surface) {
    var chosen = device == null ? null : deviceById(device!);
    if (chosen != null) {
      var platform = switch (surface) {
        SplashSurface.android ||
        SplashSurface.android12 => DevicePlatform.android,
        SplashSurface.ios => DevicePlatform.ios,
        SplashSurface.web => null,
      };
      if (chosen.platform == platform) return chosen;
    }
    var fallback = defaultSplashDeviceId(surface);
    return fallback == null ? null : deviceById(fallback);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 24,
      children: [
        for (var s in SplashSurface.values)
          for (var t in SplashTheme.values)
            SplashVariantTile(
              key: ValueKey('${s.name}/${t.name}'),
              picture: config.pictureFor(s, t),
              resolution: config.resolutionFor(s, t),
              problems: config
                  .problemsFor(s, t)
                  .where((p) => p.surface != null)
                  .toList(),
              device: _deviceFor(s),
              selected: s == surface && t == theme,
              onTap: onSelect == null ? null : () => onSelect!(s, t),
            ),
      ],
    );
  }
}

/// One cell, large.
///
/// **One picture, not two.** It used to show the prediction and the
/// recomposition side by side and let the reader work out which to believe;
/// that is a question a panel should answer rather than delegate, and the two
/// tiles were the source of every "why is this one black" in first contact. So
/// the generated files are the picture wherever they exist, the prediction is
/// the picture where they cannot, and a line under it says which happened.
///
/// The exception is a config edited since `create` last ran, where the two
/// pictures are different *facts* — what ships today and what would ship after
/// re-running — and showing both is the whole answer.
class _SingleCell extends StatelessWidget {
  const _SingleCell({
    required this.config,
    required this.surface,
    required this.theme,
    this.device,
    this.onShowAll,
  });

  final SplashConfigScan config;
  final SplashSurface surface;
  final SplashTheme theme;
  final String? device;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;

    var chosen = device == null ? null : deviceById(device!);
    var fallback = defaultSplashDeviceId(surface);
    var resolved = chosen ?? (fallback == null ? null : deviceById(fallback));

    var picture = config.pictureFor(surface, theme);
    // The second tile, and only when it says something the first cannot: the
    // config has moved since `create` ran, so the picture on the left is the
    // splash on the device and this is the one waiting behind it.
    var pending = picture.isGenerated && config.stale
        ? config.compositionFor(surface, theme)
        : null;
    var problems = config
        .problemsFor(surface, theme)
        .where((p) => p.surface != null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Back goes on the left, before the title, because that is where
            // every reader's eye and every other application puts it. It was on
            // the far right of the row reading "Show all eight", which is a
            // description of the destination and not an offer to leave.
            if (onShowAll != null) ...[
              _LinkButton(label: '← All eight', onPressed: onShowAll!),
              const SizedBox(width: 10),
            ],
            Text('${surface.label} · ${theme.label}', style: type.sectionLabel),
            const SizedBox(width: 10),
            if (resolved != null)
              Text(
                '${resolved.label} · '
                '${resolved.width.round()}×${resolved.height.round()}',
                style: type.caption.copyWith(color: colors.mut),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 20,
          children: [
            SplashVariantTile(
              picture: picture,
              resolution: config.resolutionFor(surface, theme),
              problems: problems,
              device: resolved,
              width: 260,
              slotHeight: 480,
            ),
            if (pending != null)
              SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SplashScreenBox(
                      composition: pending,
                      enabled: true,
                      selected: false,
                      device: resolved,
                      slotHeight: 480,
                    ),
                    const SizedBox(height: 8),
                    Text('After you re-run create', style: type.bodyStrong),
                    const SizedBox(height: 4),
                    Text(
                      'The config has changed since the splash was generated. '
                      'This is what the new config predicts; the picture on the '
                      'left is what devices show until create runs again.',
                      style: type.caption.copyWith(color: colors.amber),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (picture.reason case var reason?) ...[
          const SizedBox(height: 10),
          Text(reason, style: type.caption.copyWith(color: colors.mut)),
        ],
        if (problems.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Problems(problems),
        ],
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        label,
        style: context.type.caption.copyWith(color: context.colors.accent),
      ),
    ),
  );
}

class _Problems extends StatelessWidget {
  const _Problems(this.problems);

  final List<SplashProblem> problems;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;

    Color colorFor(Tone tone) => switch (tone) {
      Tone.error => colors.red,
      Tone.warn => colors.amber,
      _ => colors.mut,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Problems', style: type.sectionLabel),
        const SizedBox(height: 8),
        for (var problem in problems)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 8),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorFor(problem.tone),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(problem.message, style: type.body),
                      if (problem.key != null || problem.blocksGeneration)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if (problem.key != null) problem.key!,
                              if (problem.blocksGeneration)
                                'stops `create` from running',
                            ].join(' · '),
                            style: type.micro.copyWith(color: colors.mut2),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.tone = Tone.neutral});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.type.bodyMuted.copyWith(
            color: tone == Tone.error ? context.colors.red : null,
          ),
        ),
      ),
    );
  }
}
