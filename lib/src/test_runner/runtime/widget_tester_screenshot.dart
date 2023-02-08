import 'dart:convert';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../protocol/models.dart';
import 'run_context.dart';

extension WidgetTesterScreenshotExtension on WidgetTester {
  Future<void> screenshot({String? name, List<String>? tags}) async {
    var context = runContext;

    var index = ++context.screenIndex;
    var parentIds = context.pathTracker.id;

    var screenId = [...parentIds, index].join('-');

    var parentId = context.previousId;
    context.previousId = screenId;

    var parentRectangle = context.previousTap;
    context.previousTap = null;

    var isDuplicatedScreen = context.previousScreens.contains(screenId);

    if (isDuplicatedScreen) {
      // Early exit. In "splits", we capture the same screen. To speed-up we skip
      // the screenshot part.
      context.currentSplitName = null;
      return;
    }
    context.previousScreens.add(screenId);

    var renderView = binding.renderView;

    ui.Brightness? brightnessAt(Offset offset) {
      try {
        //ignore: invalid_use_of_protected_member
        return renderView.layer
            ?.find<SystemUiOverlayStyle>(offset)
            ?.statusBarIconBrightness;
      } catch (e) {
        return null;
      }
    }

    var widgetsApp =
        widgetList(find.byWidgetPredicate((widget) => widget is WidgetsApp))
            .firstOrNull as WidgetsApp?;
    var screen = Screen(screenId, name ?? '').rebuild((s) {
      s
        ..splitName = context.currentSplitName
        ..topBrightness = brightnessAt(Offset(0, 10))?.index
        ..bottomBrightness =
            brightnessAt(Offset(0, runContext.args.device.height - 5))?.index;
      if (widgetsApp != null) {
        s.supportedLocales.replace(widgetsApp.supportedLocales
            .map((l) => SerializableLocale(l.languageCode, l.countryCode))
            .toList());
      }
    });

    context.currentSplitName = null;

    await runAsync(() async {
      ui.Image? image;
      if (context.args.imageRatio > 0) {
        image = await _toImage(renderView, context.args);
      }
      Uint8List? pixels;
      if (image != null) {
        var byteData =
            (await image.toByteData(format: ui.ImageByteFormat.png))!;
        pixels = byteData.buffer.asUint8List();
      }
      var newScreen = NewScreen((b) {
        b
          ..screen.replace(screen)
          ..imageBase64 = pixels != null ? base64Encode(pixels) : null
          ..parent = parentId;
        if (parentRectangle != null) {
          b.parentRectangle.replace(Rectangle.fromLTRB(
              parentRectangle.left,
              parentRectangle.top,
              parentRectangle.right,
              parentRectangle.bottom));
        }
      });

      context.addScreen(newScreen);
    });
  }
}

Future<ui.Image> _toImage(RenderView renderView, RunArgs args) {
  assert(!renderView.debugNeedsPaint);
  final layer = renderView.debugLayer! as OffsetLayer;
  var bounds = renderView.paintBounds;
  return layer.toImage(bounds,
      pixelRatio: 1 / args.device.pixelRatio * args.imageRatio);
}
