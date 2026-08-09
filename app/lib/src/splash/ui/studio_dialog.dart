import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../plugins/native/splash_core.dart';
import '../../ui/theme.dart';
import '../model/composition.dart';
import '../model/scan.dart';
import '../model/studio.dart';
import '../model/studio_render.dart';
import '../model/surface.dart';
import '../model/validation.dart';
import 'splash_render.dart';
import 'variant_tile.dart';

/// Cropping a source image onto the canvas a target actually wants.
///
/// The loop this replaces costs five minutes and a trip to a real device: open
/// Figma, remember the two-thirds mask, export at exactly 1152, guess, run
/// `create`, build, look at a phone, find it cropped, repeat. Every number in it
/// is in `model/studio.dart` and none of them is anywhere the person exporting
/// the PNG would see it.
///
/// **The live tile is drawn from a real encoded PNG**, written to a temp file on
/// a short debounce and loaded back through the ordinary [SplashRender]. Drawing
/// the crop with a second widget path would have been cheaper and would have
/// meant the preview and the export were two implementations that agree until
/// they do not — which is the failure this whole plugin exists to prevent. What
/// you are looking at is the file that will be written.
Future<void> showSplashStudioDialog(
  BuildContext context, {
  required SplashCore core,
  required String package,
  required SplashConfigScan config,
  SplashStudioTarget target = SplashStudioTarget.android12Icon,
  SplashTheme theme = SplashTheme.light,
}) => showDialog<void>(
  context: context,
  builder: (context) => _StudioDialog(
    core: core,
    package: package,
    config: config,
    initialTarget: target,
    initialTheme: theme,
  ),
);

class _StudioDialog extends StatefulWidget {
  const _StudioDialog({
    required this.core,
    required this.package,
    required this.config,
    required this.initialTarget,
    required this.initialTheme,
  });

  final SplashCore core;
  final String package;
  final SplashConfigScan config;
  final SplashStudioTarget initialTarget;
  final SplashTheme initialTheme;

  @override
  State<_StudioDialog> createState() => _StudioDialogState();
}

class _StudioDialogState extends State<_StudioDialog> {
  late var _target = widget.initialTarget;
  late var _theme = widget.initialTheme;

  String? _sourcePath;
  Uint8List? _sourceBytes;
  SplashSourceFacts? _facts;

  SplashCrop _crop = const SplashCrop(scale: 1);
  var _widthDp = splashDefaultImageWidthDp;

  /// The encoded preview, and the directory it lives in.
  Directory? _scratch;
  String? _previewPath;
  var _previewCount = 0;
  Timer? _debounce;

  var _applying = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    // Best effort: a preview left behind is a few hundred KB in the system temp
    // directory, and failing to remove it must not take the dialog down.
    try {
      _scratch?.deleteSync(recursive: true);
    } catch (_) {}
    super.dispose();
  }

  SplashStudioCanvas get _canvas => splashStudioCanvas(
    target: _target,
    sourceWidth: _facts?.width ?? 1,
    sourceHeight: _facts?.height ?? 1,
    hasIconBackground: widget.config.config
        .android12IconBackgroundColor(_theme)
        .isPresent,
    logicalWidth: _widthDp,
  );

  double get _overflow => _facts == null
      ? 0
      : splashCropOverflow(
          canvas: _canvas,
          crop: _crop,
          sourceWidth: _facts!.width,
          sourceHeight: _facts!.height,
        );

  double get _overhang => _facts == null
      ? 0
      : splashCornerOverhang(
          canvas: _canvas,
          crop: _crop,
          sourceWidth: _facts!.width,
          sourceHeight: _facts!.height,
        );

  Future<void> _browse() async {
    var picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'images',
          extensions: splashConvertibleFormats.toList(),
        ),
      ],
      initialDirectory: widget.core.packageRootFor(widget.package),
    );
    if (picked == null || !mounted) return;

    var bytes = await picked.readAsBytes();
    var facts = measureSplashSource(bytes);
    if (!mounted) return;
    if (facts == null) {
      setState(() => _error = 'That file could not be decoded as an image.');
      return;
    }
    setState(() {
      _error = null;
      _sourcePath = picked.path;
      _sourceBytes = bytes;
      _facts = facts;
    });
    _fit();
  }

  /// Back to the crop that puts the whole source inside the usable area.
  void _fit() {
    var facts = _facts;
    if (facts == null) return;
    setState(() {
      _crop = splashFitCrop(
        canvas: _canvas,
        sourceWidth: facts.width,
        sourceHeight: facts.height,
      );
    });
    _schedulePreview();
  }

  void _changeCrop(SplashCrop crop) {
    setState(() => _crop = crop);
    _schedulePreview();
  }

  /// Re-encodes after the drag settles.
  ///
  /// Debounced rather than throttled: a 1152² composite and PNG encode is not a
  /// frame's worth of work even on another isolate, and a preview that lags one
  /// gesture behind is worse than one that appears a moment after you let go.
  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () {
      unawaited(_renderPreview());
    });
  }

  Future<void> _renderPreview() async {
    var bytes = _sourceBytes;
    if (bytes == null) return;
    var canvas = _canvas;
    var crop = _crop;
    try {
      var png = await renderSplashPngInIsolate(
        sourceBytes: bytes,
        canvas: canvas,
        crop: crop,
      );
      if (!mounted) return;

      var scratch = _scratch ??= Directory.systemTemp.createTempSync(
        'splash_studio',
      );
      // A fresh name every time. `Image.file` caches by path, so overwriting
      // one file would show the first render forever.
      var previous = _previewPath;
      var next = p.join(scratch.path, 'preview_${_previewCount++}.png');
      await File(next).writeAsBytes(png);
      if (!mounted) return;
      setState(() => _previewPath = next);
      if (previous != null) {
        try {
          File(previous).deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _apply() async {
    var source = _sourcePath;
    if (source == null || _applying) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await widget.core.invoke(
        'prepare',
        arguments: {
          'package': widget.package,
          'source': source,
          'target': _target.name,
          'theme': _theme.name,
          if (_target == SplashStudioTarget.image) 'width': _widthDp.round(),
          // The same three numbers the CLI takes. The crop surface is a way of
          // choosing them, not a second way of applying them.
          'scale': '${_crop.scale}',
          'offsetX': '${_crop.offsetX}',
          'offsetY': '${_crop.offsetY}',
          if (widget.config.config.flavor != null)
            'flavor': widget.config.config.flavor,
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _applying = false;
        });
      }
    }
  }

  /// The cell this target shows up on, with the pending PNG standing in for
  /// whatever the config points at now.
  SplashComposition? get _previewComposition {
    var path = _previewPath;
    if (path == null) return null;
    var canvas = _canvas;
    var surface = _target.previewSurface;
    var base = widget.config.compositionFor(surface, _theme);
    var layer = SplashLayer(
      path: path,
      absolutePath: path,
      fit: _target == SplashStudioTarget.backgroundImage
          ? SplashFit.cover
          : SplashFit.none,
      alignment: SplashAlignment.center,
      naturalWidth: canvas.width / sourceDensity,
      naturalHeight: canvas.height / sourceDensity,
    );

    return switch (_target) {
      SplashStudioTarget.android12Icon ||
      SplashStudioTarget.image => base.withLayers(image: layer),
      SplashStudioTarget.android12Branding => base.withLayers(
        branding: layer,
        usesLauncherIcon: base.usesLauncherIcon,
      ),
      SplashStudioTarget.backgroundImage => base.withLayers(
        backgroundImage: layer,
        usesLauncherIcon: base.usesLauncherIcon,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;

    return AlertDialog(
      title: const Text('Prepare an image'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var target in SplashStudioTarget.values)
                    ChoiceChip(
                      label: Text(target.label),
                      selected: _target == target,
                      onSelected: _applying
                          ? null
                          : (_) {
                              setState(() => _target = target);
                              _fit();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var theme in SplashTheme.values)
                    ChoiceChip(
                      label: Text(theme.label),
                      selected: _theme == theme,
                      onSelected: _applying
                          ? null
                          : (_) {
                              setState(() => _theme = theme);
                              _fit();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _applying ? null : () => unawaited(_browse()),
                    child: Text(
                      _sourcePath == null ? 'Choose an image…' : 'Change…',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _sourcePath == null
                          ? 'Any format the generator can read. A file outside '
                                'the package is copied in.'
                          : '${p.basename(_sourcePath!)} · '
                                '${_facts?.width}×${_facts?.height}',
                      style: type.caption.copyWith(color: colors.mut),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (_facts != null) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CropSurface(
                        canvas: _canvas,
                        crop: _crop,
                        sourcePath: _sourcePath!,
                        sourceWidth: _facts!.width,
                        sourceHeight: _facts!.height,
                        onChanged: _changeCrop,
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On ${_target.previewSurface.label}',
                            style: type.caption.copyWith(color: colors.mut),
                          ),
                          const SizedBox(height: 6),
                          if (_previewComposition case var composition?)
                            SplashScreenBox(
                              composition: composition,
                              enabled: true,
                              selected: false,
                              slotHeight: 300,
                            )
                          else
                            SizedBox(
                              height: 300,
                              child: Center(
                                child: Text(
                                  'Rendering…',
                                  style: type.caption.copyWith(
                                    color: colors.mut2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Scale', style: type.caption),
                    Expanded(
                      child: Slider(
                        value: _crop.scale.clamp(0.01, _maxScale),
                        min: 0.01,
                        max: _maxScale,
                        onChanged: _applying
                            ? null
                            : (value) =>
                                  _changeCrop(_crop.copyWith(scale: value)),
                      ),
                    ),
                    TextButton(
                      onPressed: _applying ? null : _fit,
                      child: const Text('Fit'),
                    ),
                  ],
                ),
                if (_target == SplashStudioTarget.image)
                  Row(
                    children: [
                      // The question the config has no field for, because the
                      // answer is baked into the pixel size of the file.
                      Text('Width on screen', style: type.caption),
                      Expanded(
                        child: Slider(
                          value: _widthDp,
                          min: 40,
                          max: 360,
                          onChanged: _applying
                              ? null
                              : (value) {
                                  setState(() => _widthDp = value);
                                  _fit();
                                },
                        ),
                      ),
                      Text('${_widthDp.round()}dp', style: type.caption),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  '${_canvas.width}×${_canvas.height} — '
                  '${_canvas.explanation}',
                  style: type.caption.copyWith(color: colors.mut),
                ),
                if (_overflow > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${_overflow.round()}px outside the usable area — that '
                      'much is cut off.',
                      style: type.caption.copyWith(color: colors.amber),
                    ),
                  )
                else if (_overhang > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'The corners reach ${_overhang.round()}px past the '
                      'circle. Fine if they are transparent; scale down if the '
                      'artwork goes to the edge.',
                      style: type.caption.copyWith(color: colors.mut2),
                    ),
                  ),
              ],
              if (_error case var error?) ...[
                const SizedBox(height: 12),
                SelectableText(
                  error,
                  style: type.bodySmall.copyWith(color: colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sourcePath == null || _applying
              ? null
              : () => unawaited(_apply()),
          child: Text(
            _applying
                ? 'Writing…'
                : 'Write it and set ${_target.keyFor(_theme)}',
          ),
        ),
      ],
    );
  }

  /// Enough headroom to fill the canvas from a small source, and not so much
  /// that the slider's useful range is a pixel wide.
  double get _maxScale {
    var facts = _facts;
    if (facts == null || facts.width == 0) return 4;
    var fill = _canvas.width / facts.width;
    return math.max(fill * 2, 1);
  }
}

/// The canvas, the source on it, and what the device keeps.
///
/// Drag to move, and the mask is drawn over rather than under: the part outside
/// it is dimmed, so what you see bright is what ships. Showing the whole image
/// undimmed with a circle outlined on top would be showing a picture no phone
/// produces, which is the one thing a preview must not do.
class _CropSurface extends StatelessWidget {
  const _CropSurface({
    required this.canvas,
    required this.crop,
    required this.sourcePath,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.onChanged,
  });

  final SplashStudioCanvas canvas;
  final SplashCrop crop;
  final String sourcePath;
  final int sourceWidth;
  final int sourceHeight;
  final void Function(SplashCrop) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The canvas drawn at whatever scale fits the box, with every offset
        // and size below expressed in canvas pixels and scaled once here.
        var box = math.min(
          constraints.maxWidth,
          300 * canvas.width / canvas.height,
        );
        var factor = box / canvas.width;
        var height = canvas.height * factor;

        // Left-aligned inside whatever the Row gave us, rather than filling it.
        //
        // Without this the surface is a lie about its own shape: the parent
        // `Expanded` hands down a *tight* width, a `Container(width: box)` under
        // a tight constraint is stretched to fill it, and a 1152² canvas comes
        // out as a landscape rectangle — with the mask circle centred in the
        // stretched box while the source is positioned as if the box were the
        // width the arithmetic assumed. The two disagree by exactly the amount
        // the parent stretched it.
        return Align(
          alignment: Alignment.topLeft,
          child: _surface(context, box: box, height: height, factor: factor),
        );
      },
    );
  }

  Widget _surface(
    BuildContext context, {
    required double box,
    required double height,
    required double factor,
  }) {
    var colors = context.colors;
    return GestureDetector(
      onPanUpdate: (details) => onChanged(
        crop.copyWith(
          offsetX: crop.offsetX + details.delta.dx / factor,
          offsetY: crop.offsetY + details.delta.dy / factor,
        ),
      ),
      child: Container(
        width: box,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: colors.line),
          // A checker would be nicer; a flat panel colour is enough to see
          // transparency against and costs nothing.
          color: colors.panel2,
        ),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left:
                    ((canvas.width - sourceWidth * crop.scale) / 2 +
                        crop.offsetX) *
                    factor,
                top:
                    ((canvas.height - sourceHeight * crop.scale) / 2 +
                        crop.offsetY) *
                    factor,
                width: sourceWidth * crop.scale * factor,
                height: sourceHeight * crop.scale * factor,
                child: Image.file(
                  File(sourcePath),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, _, _) => const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MaskPainter(
                      canvas: canvas,
                      factor: factor,
                      line: colors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dims everything the device will not show, and outlines what it will.
class _MaskPainter extends CustomPainter {
  const _MaskPainter({
    required this.canvas,
    required this.factor,
    required this.line,
  });

  final SplashStudioCanvas canvas;
  final double factor;
  final Color line;

  @override
  void paint(Canvas target, Size size) {
    var full = Offset.zero & size;
    var usableWidth = canvas.usableWidth * factor;
    var usableHeight = canvas.usableHeight * factor;
    var centre = size.center(Offset.zero);

    Path keep;
    if (canvas.circularMask) {
      keep = Path()
        ..addOval(
          Rect.fromCircle(
            center: centre,
            radius: math.min(usableWidth, usableHeight) / 2,
          ),
        );
    } else {
      keep = Path()
        ..addRect(
          Rect.fromCenter(
            center: centre,
            width: usableWidth,
            height: usableHeight,
          ),
        );
    }

    // Everything outside what survives, greyed. This is the honest way round:
    // bright is what ships.
    var outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      keep,
    );
    target.drawPath(outside, Paint()..color = const Color(0x99000000));
    target.drawPath(
      keep,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line,
    );

    if (canvas.circularMask) {
      // The square the package's own advice fills, so a logo with transparent
      // corners can be lined up against the number in the docs.
      target.drawRect(
        Rect.fromCenter(
          center: centre,
          width: usableWidth,
          height: usableHeight,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = line.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.canvas.width != canvas.width ||
      old.canvas.usableWidth != canvas.usableWidth ||
      old.factor != factor;
}
