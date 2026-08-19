import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../address/address_scope.dart';
import '../plugins/native/assets_address.dart';
import '../plugins/native/assets_core.dart';
import 'detail.dart';
import 'list.dart';
import 'model/asset_catalog.dart';
import 'model/asset_scan.dart';
import 'preview.dart';
import '../ui/error_state.dart';

/// The asset inspector, wired up.
///
/// The screen half of the split: it reads the address, reads the core's scan,
/// pulls the bytes off disk, and hands plain data to two views that know
/// nothing about any of that.
///
/// **Every piece of state that names something is in the address** — which
/// asset, which density, which frame, which backdrop. That is not tidiness: an
/// address with its axes resolved is what a preview will be captured *by* once
/// rendering moves into the guest, so a control whose value lives in a `State`
/// field is a control that cannot appear in an artifact.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen(this.core, {required this.package, super.key});

  final AssetsCore core;

  /// The package whose bundle is on screen — the plugin's first segment, and
  /// the head of every segment list written from here.
  final String package;

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  ResolvedAsset? _asset;
  AssetFile? _file;

  Uint8List? _bytes;
  Object? _error;
  Size? _dimensions;

  /// Guards against an earlier, slower read landing after a later one.
  var _reads = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AssetsScreen old) {
    super.didUpdateWidget(old);
    // The scan can arrive after the address did, and the asset this names only
    // exists once it has.
    _sync();
  }

  AssetScan? get _scan => widget.core.scanFor(widget.package);

  /// Reading the address at the grain each thing is used at, so moving the
  /// frame does not re-read the file.
  void _sync() {
    var key = assetPlace(AddressScope.segments(context))?.assetKey;
    var density = AddressScope.param(context, 'density');

    var asset = key == null ? null : _scan?.catalog.byKey[key];
    var file = asset == null ? null : _fileFor(asset, density);

    if (asset?.key == _asset?.key && file?.key == _file?.key) return;
    _asset = asset;
    _file = file;
    // Assigned rather than `setState`d: this runs from `didChangeDependencies`,
    // which is inside the build phase, and a rebuild is already coming. The
    // read below is what needs `setState`, and it only reaches one after its
    // first `await`.
    _bytes = null;
    _error = null;
    _dimensions = null;
    if (file != null) unawaited(_read(asset!, file, ++_reads));
  }

  /// The file the density axis names, falling back to the main asset — an
  /// address carrying a density the asset does not have should show the asset,
  /// not nothing.
  AssetFile _fileFor(ResolvedAsset asset, String? density) {
    var scale = density == null ? null : AssetCatalog.parseScale('$density/');
    if (scale == null) return asset.main;
    for (var file in asset.files) {
      if (file.scale == scale) return file;
    }
    return asset.main;
  }

  Future<void> _read(ResolvedAsset asset, AssetFile file, int token) async {
    try {
      var bytes = await File(file.path).readAsBytes();
      var size = assetKindOf(asset.key) == AssetKind.image
          ? await _measure(bytes)
          : null;
      if (!mounted || token != _reads) return;
      setState(() {
        _bytes = bytes;
        _dimensions = size;
      });
    } catch (e) {
      if (!mounted || token != _reads) return;
      setState(() => _error = e);
    }
  }

  /// Pixel dimensions, decoded here rather than read from the core.
  ///
  /// The core could answer this — `image` is pure Dart — and one day should, so
  /// `fw describe` can too. Until then the panel is the only surface asking,
  /// and `dart:ui` is already decoding these bytes to draw them.
  Future<Size?> _measure(Uint8List bytes) async {
    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      frame = await codec.getNextFrame();
      return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    } catch (_) {
      // A raster we cannot decode still has a preview to try and a size in
      // bytes to report; only the dimensions go missing.
      return null;
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
  }

  void _select(String key) => AddressScope.write(context).update(
    segments: assetSegments(widget.package, key),
    // Density and frame belong to the asset they were chosen for. Carrying
    // `frame=42` onto a PNG would name a state that does not exist.
    params: {'density': null, 'frame': null},
  );

  @override
  Widget build(BuildContext context) {
    if (widget.core.failureFor(widget.package) case var failure?) {
      return ErrorState(
        title: 'Could not read the assets',
        message: failure,
        // The failure names its own fix — run pub get — and this is how coming
        // back from it lands without restarting the app.
        onRetry: () => unawaited(widget.core.reload(widget.package)),
      );
    }
    var scan = _scan;
    if (scan == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 320,
          child: AssetListView(
            own: scan.own,
            fromPackages: scan.fromPackages,
            problems: scan.problems,
            selected: _asset?.key,
            onSelect: _select,
            onReload: () => unawaited(widget.core.reload(widget.package)),
            scanning: widget.core.isScanning(widget.package),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _detail(context)),
      ],
    );
  }

  Widget _detail(BuildContext context) {
    var asset = _asset;
    var file = _file;
    if (asset == null || file == null) return const AssetDetailEmpty();

    var address = AddressScope.of(context);
    return AssetDetailView(
      asset: asset,
      file: file,
      bytes: _bytes,
      error: _error,
      dimensions: _dimensions,
      background: _background(AddressScope.param(context, 'bg')),
      onBackground: (value) => address.setParam(
        'bg',
        value == PreviewBackground.checker ? null : value.name,
      ),
      zoom: double.tryParse(AddressScope.param(context, 'zoom') ?? '') ?? 1,
      onZoom: (value) =>
          address.setParam('zoom', value == 1 ? null : '${value.toInt()}'),
      onDensity: (value) => address.setParam(
        'density',
        value.scale == null ? null : '${value.scale}x',
      ),
      frame: int.tryParse(AddressScope.param(context, 'frame') ?? ''),
      onFrame: (value) => address.setParam('frame', '$value'),
    );
  }

  PreviewBackground _background(String? name) {
    for (var option in PreviewBackground.values) {
      if (option.name == name) return option;
    }
    return PreviewBackground.checker;
  }
}
