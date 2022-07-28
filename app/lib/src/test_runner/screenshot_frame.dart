import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutterware/internals/test_runner.dart';
import '../utils/raw_image_provider.dart';
import 'ui/phone_status_bar.dart';

class ScreenshotFrame extends StatelessWidget {
  final Screen screen;
  final RunArgs args;

  const ScreenshotFrame(this.screen, this.args, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget main;
    var file = screen.imageFile;
    var bytes = screen.imageBytes;
    if (file != null) {
      main = Image(
        image: RawImageProvider(
          RawImageData(File(file.path), file.width, file.height),
        ),
      );
    } else if (bytes != null) {
      main = Image.memory(bytes);
    } else {
      main = Container(
        color: Colors.black12,
        width: args.device.width * args.device.pixelRatio,
        height: args.device.height * args.device.pixelRatio,
        alignment: Alignment.center,
        child: Text(screen.name),
      );
    }

    return PhoneStatusBar(
      bottomBrightness: Brightness.values[screen.bottomBrightness ?? 0],
      topBrightness: Brightness.values[screen.topBrightness ?? 0],
      leftText: '09:42',
      viewPadding: args.device.safeArea.toEdgeInsets(),
      child: main,
    );
  }
}
