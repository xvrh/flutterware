import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../../ui/theme.dart';
import '../model/color.dart';
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
    this.device,
    this.selected = false,
    this.onTap,
    this.onEditValue,
    this.width = 168,
    this.slotHeight = defaultSlotHeight,
  });

  /// The height every cell's screen is centred in, whatever its aspect. Tall
  /// enough that a portrait phone at the default [width] fills it.
  ///
  /// Fixed rather than per-aspect because the `Wrap` would otherwise size each
  /// cell to its own shape, and the one landscape cell among six portrait ones
  /// comes out a third of the height with its caption stranded halfway up the
  /// phones beside it.
  static const defaultSlotHeight = 320.0;

  final SplashComposition composition;
  final SplashResolution resolution;
  final List<SplashProblem> problems;

  /// The screen to draw as. Null falls back to the surface's own canvas, which
  /// is what a matrix with no `?device=` shows.
  final Device? device;

  final bool selected;
  final VoidCallback? onTap;

  /// Opens the editor for one caption line — the label it is under, the key
  /// that produced it, and the value it currently has.
  ///
  /// Null in a test or a capture, which is what keeps the tile drawable with no
  /// core behind it.
  final void Function(String label, String key, String value, bool isColor)?
  onEditValue;

  final double width;
  final double slotHeight;

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
            device: device,
            enabled: resolution.enabled,
            selected: selected,
            slotHeight: slotHeight,
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
      // The picture is already honest; this says the image in it is Android's
      // choice rather than the author's, which the picture cannot.
      if (composition.usesLauncherIcon)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            'No android_12 image — this is your launcher icon',
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
        if (resolved.isPresent)
          _Provenance(
            label: label,
            resolved: resolved,
            onEdit: onEditValue == null
                ? null
                : () => onEditValue!(
                    label,
                    resolved.key!,
                    resolved.value!,
                    _isColorLabel(label),
                  ),
          ),
      if (resolution.image.isPresent)
        Text(
          resolution.placementSummary,
          style: type.caption.copyWith(color: colors.mut),
        ),
    ];
  }
}

/// Whether a caption line holds a colour rather than a path.
///
/// `background` is both, depending on what resolved — the caller passes the
/// colour under that label only when no background image won, so the label is
/// enough to tell them apart at the point it is read.
bool _isColorLabel(String label) => label == 'background' || label == 'icon bg';

/// A value and the key it came from, on one line — and, when there is somewhere
/// for the edit to go, the place you click to change it.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.label, required this.resolved, this.onEdit});

  final String label;
  final Resolved<String> resolved;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;
    var value = resolved.value!;
    // A colour reads better as a swatch than as six hex digits.
    var isColor = _isColorLabel(label);

    var row = DefaultTextStyle(
      style: type.caption.copyWith(color: colors.mut),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isColor) ...[
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 2, right: 4),
              decoration: BoxDecoration(
                color: Color(parseSplashColor(value) ?? 0xFF000000),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: colors.line),
              ),
            ),
          ],
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
    );

    if (onEdit == null) {
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: row);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        // Naming the key here is the point: it is where the edit will land, and
        // it is the answer to "why did changing this not do what I expected".
        message: 'Change ${resolved.key}',
        child: InkWell(
          key: ValueKey('edit:${resolved.key}'),
          onTap: onEdit,
          borderRadius: BorderRadius.circular(3),
          child: row,
        ),
      ),
    );
  }
}

/// One splash drawn at device size and scaled to fit its slot.
///
/// Public because the single-cell view draws a *second* one of these — the
/// composition recomposed from the generated files — beside the prediction, and
/// the two must be the same widget or the comparison is between two renderers
/// rather than between two compositions.
class SplashScreenBox extends StatelessWidget {
  const SplashScreenBox({
    super.key,
    required this.composition,
    required this.enabled,
    required this.selected,
    this.device,
    this.slotHeight = SplashVariantTile.defaultSlotHeight,
    this.onTap,
  });

  final SplashComposition composition;
  final Device? device;
  final bool enabled;
  final bool selected;
  final double slotHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _Screen(
    composition: composition,
    enabled: enabled,
    selected: selected,
    device: device,
    slotHeight: slotHeight,
    onTap: onTap,
  );
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.composition,
    required this.enabled,
    required this.selected,
    required this.slotHeight,
    this.device,
    this.onTap,
  });

  final SplashComposition composition;
  final Device? device;
  final bool enabled;
  final bool selected;
  final double slotHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (width, height) = splashPreviewSize(
      composition.surface,
      width: device?.width,
      height: device?.height,
    );
    var radius = BorderRadius.circular(
      composition.surface == SplashSurface.web ? 6 : 18,
    );

    return GestureDetector(
      onTap: onTap,
      // A fixed slot, with the screen centred inside it.
      //
      // Without it the `Wrap` sizes each tile to its own aspect, and the web
      // surface — the one landscape cell among six portrait ones — comes out a
      // third of the height and hangs off the top of the row with its caption
      // stranded halfway up the phones beside it. One slot height puts every
      // caption on the same line, which is what makes eight cells scan as a
      // matrix rather than as a pile.
      child: SizedBox(
        height: slotHeight,
        child: Center(
          child: AspectRatio(
            aspectRatio: width / height,
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
                child: Opacity(
                  opacity: enabled ? 1 : 0.25,
                  // Rendered at device dimensions, then scaled — see
                  // `splashPreviewSize`. Without this a "natural size"
                  // placement would be measured against the thumbnail.
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: SplashRender(
                        composition,
                        device: device,
                        showSafeAreas: device != null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
