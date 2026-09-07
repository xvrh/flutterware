// What the tool writes when it makes a folder a group or starts a library:
// the two skeletons, kept apart from the readers because a reader is on the
// pure surface and a skeleton spells Flutter imports in its text.
import 'group_file.dart';
import 'scene_file.dart';
import 'tokens_library.dart';

/// The skeleton `New group` writes: nothing declared yet, a bare wrapper.
String emitGroupSkeleton() =>
    '''
$sceneGroupFileMarker
// This folder is a scene group: every `.scene.dart` below it is one of its
// scenes, and this file says what those scenes may use. The flutterware
// scene editor reads it as text and generates `$sceneArgsFileName` beside it;
// it never writes here except to attach a token library you created.
//
// - widgets: the app's widgets a scene may place, each with its arguments.
// - exports: the app's own values, named for the scenes — any type, any
//   expression; the canvas resolves them, the editor only names them.
// - libraries: the token libraries these scenes read, imported above.
// - wrap: what the canvas is mounted under — the app's theme, typically.
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

final $sceneGroupSymbol = SceneGroup(
  widgets: [],
  exports: [],
  libraries: [],
  wrap: (child) => MaterialApp(debugShowCheckedModeBanner: false, home: child),
);
''';

/// The skeleton `New library` writes: an empty library, the editor's own
/// from its first byte.
String emitTokensSkeleton(String symbol) =>
    emitTokensLibrary(const [], symbol: symbol);
