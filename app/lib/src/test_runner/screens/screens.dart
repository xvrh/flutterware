import 'package:flutter_studio/internals/test_runner.dart';
import 'package:flutter/material.dart';
import '../service.dart';
import '../ui/device_frame.dart';
import 'json.dart';

Widget? widgetForScreen(ScenarioRun run, Screen screen) {
  var bytes = screen.imageBytes;
  if (bytes != null) {
    return Image.memory(bytes);
  }
  var browser = screen.browser;
  if (browser != null) {
    //TODO(xha): return Browser preview
    return Container(color: Colors.red);
  }

  var email = screen.email;
  if (email != null) {
    throw UnimplementedError();
  }

  var pdf = screen.pdf;
  if (pdf != null) {
    throw UnimplementedError();
  }

  var json = screen.json;
  if (json != null) {
    return DeviceFrame(
      run: run,
      child: JsonBody(run, json),
    );
  }

  return null;
}
