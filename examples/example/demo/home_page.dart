import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog.dart';
import 'package:flutterware_example/main.dart';

import 'shell.dart';

/// Two demos in one file, so the catalog derives a `Home page` group for them
/// without either declaring one.

@Demo(name: 'Default', wrapper: wrapInApp)
Widget homePageDefault() => const MyHomePage(title: 'Flutter Demo Home Page');

/// The same screen at a phone's size, to show that a demo can pin its own
/// canvas rather than take whatever the panel happens to be.
@Demo(name: 'On a phone', wrapper: wrapInApp, formFactor: FormFactor.mobile)
Widget homePageMobile() => const MyHomePage(title: 'Home');
