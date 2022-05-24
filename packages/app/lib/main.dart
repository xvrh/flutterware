import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';

void main() {
  Logger.root
    ..level = Level.INFO
    ..onRecord.listen(print);
  runApp(StudioApp());
}
