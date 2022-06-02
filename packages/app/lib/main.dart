import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';

void main() async {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(print);
  runApp(StudioApp());
}
