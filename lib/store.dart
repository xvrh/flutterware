/// Composing a store screenshot — the frame a project draws around its app's
/// own pixels.
///
/// Published API: a project subclasses [StoreFrame], so what is exported here
/// is what somebody's listing compiles against.
///
/// Separate from `lib/plugins.dart` because this half imports Flutter and that
/// half may not: `tool/flutterware.dart` runs under a plain `dart run` and
/// declares the listing, while this runs inside the renderer and draws it.
library;

export 'src/plugins/store.dart' show StoreCanvas, StoreTarget;
export 'src/store/frame.dart';
