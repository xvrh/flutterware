import 'dart:io';

import 'package:flutterware/internals/test_runner.dart';
import 'package:flutter/material.dart';
import '../../utils/raw_image_provider.dart';

Widget? widgetForScreen(ScenarioRun run, Screen screen) {
  var file = screen.imageFile;
  if (file != null) {
    return Image(
      image: RawImageProvider(
        RawImageData(File(file.path), file.width, file.height),
      ),
    );
  }
  var bytes = screen.imageBytes;
  if (bytes != null) {
    return Image.memory(bytes);
  }
  return null;
}
