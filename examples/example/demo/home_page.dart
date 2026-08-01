import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware_example/main.dart';

import 'shell.dart';

/// Two demos in one file, so the catalog derives a `Home page` group for them
/// without either declaring one.

@Preview(name: 'Default', wrapper: wrapInApp)
Widget homePageDefault() => const MyHomePage(title: 'Flutter Demo Home Page');

/// The same screen at a phone's size, to show that a demo can pin its own
/// canvas rather than take whatever the panel happens to be.
@Preview(name: 'On a phone', wrapper: wrapInApp)
Widget homePageMobile() => const MyHomePage(title: 'Home');
