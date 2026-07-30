import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/composition.dart';
import '../model/surface.dart';

/// A [SplashComposition], drawn.
///
/// **Deliberately thin, and it must stay that way.** Every decision about where
/// something goes — which key won the cascade, what `android_gravity` means,
/// how big the Android 12 mask is — has already been made by the time a
/// composition exists. This widget maps [SplashFit] onto `BoxFit` and
/// [SplashAlignment] onto `Alignment` and does nothing else.
///
/// That is what lets the same widget be mounted in the panel and in a headless
/// guest handed the same JSON: two hosts, one renderer, nothing to drift.
class SplashRender extends StatelessWidget {
  const SplashRender(this.composition, {super.key});

  final SplashComposition composition;

  @override
  Widget build(BuildContext context) {
    var background = composition.backgroundColor;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: background == null
                ? const Color(0xFF000000)
                : Color(background),
          ),
          if (composition.backgroundImage != null)
            _Layer(composition.backgroundImage!),
          if (composition.surface == SplashSurface.android12)
            _Android12Icon(composition)
          else if (composition.image != null)
            _Layer(composition.image!),
          if (composition.branding != null) _Branding(composition),
          if (!composition.fullscreen &&
              composition.surface != SplashSurface.web)
            _StatusBar(background: background),
        ],
      ),
    );
  }
}

/// One placed image.
class _Layer extends StatelessWidget {
  const _Layer(this.layer);

  final SplashLayer layer;

  @override
  Widget build(BuildContext context) {
    if (layer.missing) return _MissingLayer(layer);

    var alignment = Alignment(layer.alignment.x, layer.alignment.y);
    var image = Image.file(
      File(layer.absolutePath!),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      // A file that vanishes between the scan and the paint is a race, not a
      // config error, so it degrades to nothing rather than to a red box.
      errorBuilder: (context, _, _) => const SizedBox.shrink(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        var natural = Size(
          layer.naturalWidth ?? constraints.maxWidth,
          layer.naturalHeight ?? constraints.maxHeight,
        );

        var size = switch (layer.fit) {
          SplashFit.none => natural,
          SplashFit.fill => constraints.biggest,
          SplashFit.fillWidth => Size(constraints.maxWidth, natural.height),
          SplashFit.fillHeight => Size(natural.width, constraints.maxHeight),
          SplashFit.contain => _scaled(
            natural,
            constraints.biggest,
            cover: false,
          ),
          SplashFit.cover => _scaled(natural, constraints.biggest, cover: true),
        };

        return Align(
          alignment: alignment,
          child: SizedBox(width: size.width, height: size.height, child: image),
        );
      },
    );
  }

  /// `contain` and `cover` differ only in which ratio wins, so they are one
  /// calculation rather than two `BoxFit`s — and doing it here means the size
  /// is known, which is what the Android 12 mask and the branding both need.
  static Size _scaled(Size source, Size target, {required bool cover}) {
    if (source.width <= 0 || source.height <= 0) return target;
    var x = target.width / source.width;
    var y = target.height / source.height;
    var scale = cover ? math.max(x, y) : math.min(x, y);
    return Size(source.width * scale, source.height * scale);
  }
}

/// The hole where a referenced file should have been.
///
/// Drawn rather than skipped: a missing image that silently renders as an empty
/// splash looks like a splash with no image, which is a different bug with a
/// different fix.
class _MissingLayer extends StatelessWidget {
  const _MissingLayer(this.layer);

  final SplashLayer layer;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(layer.alignment.x, layer.alignment.y),
      child: FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.25,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x88C23F38), width: 1),
            color: const Color(0x11C23F38),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                layer.path,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xFFC23F38),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Android 12 icon: a fixed slot, a circular mask, and an optional circle
/// behind it.
///
/// The whole point of this surface is that the icon is **not** screen-sized
/// however large the source is, and that a third of it is cut away. Drawing it
/// any other way would hide the two things people get wrong.
class _Android12Icon extends StatelessWidget {
  const _Android12Icon(this.composition);

  final SplashComposition composition;

  @override
  Widget build(BuildContext context) {
    var image = composition.image;
    if (image == null) return const SizedBox.shrink();

    var canvas = composition.iconCanvas ?? android12IconCanvasDp;
    var fraction = composition.iconMaskFraction ?? android12MaskFraction;
    var background = composition.iconBackgroundColor;

    return Center(
      child: SizedBox(
        width: canvas,
        height: canvas,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null)
              Center(
                child: SizedBox(
                  width: canvas * fraction,
                  height: canvas * fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(background),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ClipPath(
              clipper: _IconMask(fraction),
              child: image.missing
                  ? _MissingLayer(image)
                  : Image.file(
                      File(image.absolutePath!),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, _, _) => const SizedBox.shrink(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A centred circle covering [fraction] of the box — the two-thirds Android
/// keeps.
class _IconMask extends CustomClipper<Path> {
  const _IconMask(this.fraction);

  final double fraction;

  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: math.min(size.width, size.height) * fraction / 2,
      ),
    );

  @override
  bool shouldReclip(_IconMask old) => old.fraction != fraction;
}

class _Branding extends StatelessWidget {
  const _Branding(this.composition);

  final SplashComposition composition;

  @override
  Widget build(BuildContext context) {
    var branding = composition.branding!;
    return Padding(
      padding: EdgeInsets.only(
        bottom: composition.brandingBottomPadding.toDouble(),
      ),
      child: _Layer(branding),
    );
  }
}

/// A schematic status bar, shown when `fullscreen` is not set.
///
/// Deliberately a plain translucent band rather than a mock clock and battery:
/// its only job is to make `fullscreen: true` visibly do something. Inventing
/// convincing chrome would be inventing pixels the generator never produces.
class _StatusBar extends StatelessWidget {
  const _StatusBar({this.background});

  final int? background;

  @override
  Widget build(BuildContext context) {
    // Legible on both — a light band on a dark splash and vice versa.
    var dark =
        background == null || Color(background!).computeLuminance() < 0.5;

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 20,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var width in [10.0, 8.0, 14.0])
              Padding(
                padding: const EdgeInsets.only(right: 3, top: 6),
                child: Container(
                  width: width,
                  height: 5,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0x66FFFFFF)
                        : const Color(0x55000000),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
