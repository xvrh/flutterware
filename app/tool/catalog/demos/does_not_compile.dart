// A fixture, not a demo. `headless_check.dart` asserts that this entry is
// quarantined rather than fatal, that the quarantine carries the compiler's
// error, and that repairing the file brings the entry back with no restart.
//
// It is excluded from analysis in the root `analysis_options.yaml`, because the
// whole point of it is that it does not compile.
import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog.dart';

@Demo(name: 'Does not compile')
Widget doesNotCompile() => ThisTypeDoesNotExist(missing: 1);
