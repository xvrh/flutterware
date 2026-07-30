import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../plugins/native/splash_core.dart';
import '../ui/theme.dart';
import 'model/config.dart';
import 'model/scan.dart';
import 'model/surface.dart';
import 'model/validation.dart';
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
  });

  final SplashCore core;
  final String package;

  /// Which `flutter_native_splash-<flavor>.yaml`, from the address.
  final String? flavor;

  /// The cell the address names, if it names one. Highlighted rather than shown
  /// alone — the comparison is the feature.
  final SplashSurface? surface;
  final SplashTheme? theme;

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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _Header(scan: scan, config: config, selected: flavor),
        const SizedBox(height: 20),
        _Matrix(config: config, surface: surface, theme: theme),
        if (config.problems.isNotEmpty) ...[
          const SizedBox(height: 28),
          _Problems(config.problems),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scan, required this.config, this.selected});

  final SplashScan scan;
  final SplashConfigScan config;
  final String? selected;

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
                  : 'Never generated',
              style: type.caption.copyWith(
                color: config.stale ? colors.amber : colors.mut,
              ),
            ),
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
  const _Matrix({required this.config, this.surface, this.theme});

  final SplashConfigScan config;
  final SplashSurface? surface;
  final SplashTheme? theme;

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
              composition: config.compositionFor(s, t),
              resolution: config.resolutionFor(s, t),
              problems: config
                  .problemsFor(s, t)
                  .where((p) => p.surface != null)
                  .toList(),
              selected: s == surface && t == theme,
            ),
      ],
    );
  }
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
