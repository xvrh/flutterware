import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware_example/main.dart';

import 'shell.dart';

/// The home screen on a phone, in a file of its own so that a canvas can be
/// declared for it without catching its neighbour.
///
/// `PreviewCanvas` takes a path prefix and a file is a legal one, which is how
/// a single preview differs from the entries beside it. Its sibling in
/// `home_page.dart` deliberately has no canvas: the pair is the contrast.
@Preview(name: 'On a phone', group: 'Home page', wrapper: wrapInApp)
Widget homePageMobile() => const MyHomePage(title: 'Home');
