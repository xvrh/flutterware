import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../../ui/theme.dart';
import '../model/composition.dart';
import '../model/config.dart';
import '../model/surface.dart';
import '../model/validation.dart';
import 'splash_render.dart';

/// One cell of the matrix: a splash at device scale, and why it looks like that.
///
/// The caption is not decoration. A cell that says `#101418 · from
/// color_dark_android` answers the question the picture provokes; without it,
/// eight pictures side by side leave you knowing something is wrong and not
/// where to change it.
class SplashVariantTile extends StatelessWidget {
  const SplashVariantTile({
    super.key,
    required this.composition,
    required this.resolution,
    required this.problems,
    this.selected = false,
    this.onTap,
    this.width = 168,
  });

  final SplashComposition composition;
  final SplashResolution resolution;
  final List<SplashProblem> problems;
  final bool selected;
  final VoidCallback? onTap;
  final double width;

  Tone? get _worst {
    Tone? worst;
    for (var problem in problems) {
      if (problem.tone == Tone.error) return Tone.error;
      if (problem.tone == Tone.warn) worst = Tone.warn;
    }
    return worst;
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var tone = _worst;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Screen(
            composition: composition,
            enabled: resolution.enabled,
            selected: selected,
            onTap: onTap,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${composition.surface.label} · ${composition.theme.label}',
                  style: context.type.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (tone != null)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone == Tone.error ? colors.red : colors.amber,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ..._captions(context),
        ],
      ),
    );
  }

  List<Widget> _captions(BuildContext context) {
    var type = context.type;
    var colors = context.colors;

    if (!resolution.enabled) {
      return [
        Text(
          'Disabled in config',
          style: type.caption.copyWith(color: colors.mut),
        ),
      ];
    }

    return [
      if (resolution.fallsBackToLight)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            'No dark config — the OS shows the light splash',
            style: type.caption.copyWith(color: colors.amber),
          ),
        ),
      for (var (label, resolved) in [
        (
          'background',
          resolution.backgroundImage.isPresent
              ? resolution.backgroundImage
              : resolution.color,
        ),
        ('image', resolution.image),
        ('icon bg', resolution.iconBackgroundColor),
        ('branding', resolution.branding),
      ])
        if (resolved.isPresent) _Provenance(label: label, resolved: resolved),
      if (resolution.image.isPresent)
        Text(
          resolution.placementSummary,
          style: type.caption.copyWith(color: colors.mut),
        ),
    ];
  }
}

/// A value and the key it came from, on one line.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.label, required this.resolved});

  final String label;
  final Resolved<String> resolved;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;
    var value = resolved.value!;
    // A colour reads better as a swatch than as six hex digits.
    var isColor = label == 'background' || label == 'icon bg';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DefaultTextStyle(
        style: type.caption.copyWith(color: colors.mut),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                isColor ? '#$value' : value.split('/').last,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                resolved.key ?? '',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: type.micro.copyWith(color: colors.mut3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The splash itself, rendered at real device size and scaled to fit.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.composition,
    required this.enabled,
    required this.selected,
    this.onTap,
  });

  final SplashComposition composition;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (width, height) = splashPreviewSize(composition.surface);
    var radius = BorderRadius.circular(
      composition.surface == SplashSurface.web ? 6 : 18,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected ? colors.accent : colors.line,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: width / height,
            child: Opacity(
              opacity: enabled ? 1 : 0.25,
              // Rendered at device dimensions, then scaled — see
              // `splashPreviewSize`. Without this a "natural size" placement
              // would be measured against the thumbnail.
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: SplashRender(composition),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
