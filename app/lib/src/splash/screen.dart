import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import 'package:flutter/services.dart';

import '../plugins/native/splash_core.dart';
import '../ui/empty_state.dart';
import '../ui/theme.dart';
import 'model/config.dart';
import 'model/scan.dart';
import 'model/surface.dart';
import 'model/validation.dart';
import 'ui/artifacts_view.dart';
import 'ui/cell_inspector.dart';
import 'ui/panel_header.dart';
import 'ui/variant_tile.dart';

/// The whole matrix at once: four surfaces, two themes, side by side — and,
/// when one is selected, an inspector beside them rather than instead of them.
///
/// Showing them together is the point. Any one of these is easy to get from a
/// device; what nobody can hold in their head is that the same eight lines of
/// YAML produce *these eight pictures*, and that two of them are usually not
/// what the author expected. Which is why selecting one no longer replaces the
/// page: the comparison used to disappear at exactly the moment you got
/// interested in one cell, and left a text link to get back.
class SplashScreen extends StatelessWidget {
  const SplashScreen(
    this.core, {
    super.key,
    required this.package,
    this.flavor,
    this.surface,
    this.theme,
    this.size,
    this.onSelectCell,
    this.onShowAll,
    this.onSelectSize,
    this.onSelectFlavor,
  });

  final SplashCore core;
  final String package;

  /// Which `flutter_native_splash-<flavor>.yaml`, from the address.
  final String? flavor;

  /// The cell the address names, if it names one. Outlined in the matrix and
  /// opened in the inspector — never shown alone, because the comparison is the
  /// feature.
  final SplashSurface? surface;
  final SplashTheme? theme;

  /// `?size=`, or null for each surface's own default.
  final SplashScreenSize? size;

  /// Writes the two axes. Supplied by the plugin, which is the half that sits
  /// inside an `AddressScope`; null in a test that mounts this screen on its
  /// own, where navigating means nothing.
  final void Function(SplashSurface, SplashTheme)? onSelectCell;

  /// Clears them again — closes the inspector.
  final VoidCallback? onShowAll;

  /// Writes `?size=`.
  final ValueChanged<SplashScreenSize?>? onSelectSize;

  /// Writes the flavor segment.
  final ValueChanged<String?>? onSelectFlavor;

  @override
  Widget build(BuildContext context) {
    var failure = core.failureFor(package);
    if (failure != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'This package could not be read',
        message: failure,
      );
    }

    var scan = core.scanFor(package);
    if (scan == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (scan.configErrors.isNotEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'The config file is not one the generator would read',
        message: scan.configErrors.join('\n\n'),
      );
    }

    if (!scan.isConfigured) {
      return const EmptyState(
        icon: Icons.image_outlined,
        title: 'No splash configured',
        message:
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

    var open = surface != null && theme != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SplashPanelHeader(
          package: package,
          configPath: config.config.path,
          fromPubspec: config.config.kind == SplashConfigKind.pubspec,
          state: _stateOf(config),
          fileCount: config.artifacts.length,
          scannedAt: core.scannedAt(package),
          flavors: scan.flavors,
          selectedFlavor: config.config.flavor,
          onFlavor: onSelectFlavor,
          size: size,
          onSize: onSelectSize,
          onReload: () =>
              unawaited(core.invoke('reload', arguments: {'package': package})),
          onGenerate: config.blocksGeneration ? null : runCreate,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(FwSpacing.xxl),
                  children: [
                    _Matrix(
                      config: config,
                      surface: surface,
                      theme: theme,
                      size: size,
                      onSelect: onSelectCell,
                    ),
                    // Config-wide only. Anything that belongs to one cell is in
                    // the inspector, beside the picture it is about — which is
                    // where somebody reading it can see what it means.
                    if (_configWide(config).isNotEmpty) ...[
                      const Gap(FwSpacing.xxxl),
                      _Problems(_configWide(config)),
                    ],
                    const Gap(FwSpacing.xxxl),
                    SplashArtifactsView(
                      artifacts: config.artifacts,
                      packageRoot: core.packageRootFor(package),
                      stale: config.stale,
                    ),
                  ],
                ),
              ),
              if (open)
                // Escape closes it. Claimed here rather than at the panel root
                // so focus is taken only while the inspector is up, and handed
                // back the moment it goes.
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        onShowAll?.call(),
                  },
                  child: Focus(
                    autofocus: true,
                    child: SplashCellInspector(
                      picture: config.pictureFor(surface!, theme!),
                      resolution: config.resolutionFor(surface!, theme!),
                      problems: config
                          .problemsFor(surface!, theme!)
                          .where((p) => p.surface != null)
                          .toList(),
                      artifacts: [
                        for (var artifact in config.artifacts)
                          if (artifact.surface == surface &&
                              artifact.theme == theme)
                            artifact,
                      ],
                      device: _deviceFor(surface!, size),
                      onClose: onShowAll,
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

/// Which of the three states the header's pill is in.
SplashGeneratedState _stateOf(SplashConfigScan config) => !config.isGenerated
    ? SplashGeneratedState.never
    : config.stale
    ? SplashGeneratedState.stale
    : SplashGeneratedState.current;

/// The problems that belong to the config rather than to one cell.
List<SplashProblem> _configWide(SplashConfigScan config) => [
  for (var problem in config.problems)
    if (problem.surface == null) problem,
];

/// The screen a surface draws at a given size.
///
/// **One axis, eight honest cells.** The axis used to be a device id, which
/// names a platform with it — so a chosen iPhone redrew the two iOS tiles and
/// left the other six alone, which is a control that lies about what it does. A
/// size class names no platform, and each surface resolves it to its own
/// hardware and its own insets. See [splashDeviceIdFor].
Device? _deviceFor(SplashSurface surface, SplashScreenSize? size) {
  var id = splashDeviceIdFor(surface, size);
  return id == null ? null : deviceById(id);
}

/// Surfaces across, themes down.
///
/// Laid out as a `Wrap` rather than a fixed grid so a narrow panel reflows
/// instead of squeezing eight phones into a column too thin to read — which is
/// also what lets the inspector take 380px out of the width without the matrix
/// breaking.
class _Matrix extends StatelessWidget {
  const _Matrix({
    required this.config,
    this.surface,
    this.theme,
    this.size,
    this.onSelect,
  });

  final SplashConfigScan config;
  final SplashSurface? surface;
  final SplashTheme? theme;
  final SplashScreenSize? size;
  final void Function(SplashSurface, SplashTheme)? onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: FwSpacing.xl,
      runSpacing: FwSpacing.xxl,
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
              device: _deviceFor(s, size),
              selected: s == surface && t == theme,
              onTap: onSelect == null ? null : () => onSelect!(s, t),
            ),
      ],
    );
  }
}

/// The problems that are about the config as a whole.
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
        const Gap(FwSpacing.md),
        for (var problem in problems)
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: FwSpacing.md),
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
                          padding: const EdgeInsets.only(top: FwSpacing.xxs),
                          child: Text(
                            [
                              if (problem.key != null) problem.key!,
                              if (problem.blocksGeneration)
                                'stops `create` from running',
                            ].join('  ·  '),
                            style: type.micro.copyWith(color: colors.mut3),
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
