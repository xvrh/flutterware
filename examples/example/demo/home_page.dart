import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware_example/main.dart';

import 'shell.dart';

/// The unframed half of the `Home page` group. Its phone-canvas counterpart is
/// `home_page_mobile.dart`, which is a separate file so that the canvas
/// declared for it in `tool/flutterware.dart` does not catch this one too — the
/// group is derived from the shared `group:`, not from the file.

@Preview(name: 'Default', group: 'Home page', wrapper: wrapInApp)
Widget homePageDefault() => const MyHomePage(title: 'Flutter Demo Home Page');
