import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Rewrites the page's fragment in place, without growing the history.
///
/// [fragment] is the decoded form; `Uri` spells the escapes, so an id's own
/// `#` survives the address bar. `replaceState` rather than assigning
/// `location.hash`, because thirty row clicks must not become thirty presses
/// of the back button.
void writeUrlFragment(String fragment) {
  web.window.history.replaceState(null, '', Uri(fragment: fragment).toString());
}

/// The decoded fragment, each time the browser itself changes it — a
/// hand-edited address, or history the page did not write.
Stream<String> get urlFragmentChanges {
  late StreamController<String> controller;
  JSFunction? listener;
  controller = StreamController<String>(
    onListen: () {
      listener = ((web.Event _) => controller.add(Uri.base.fragment)).toJS;
      web.window.addEventListener('hashchange', listener);
    },
    onCancel: () {
      if (listener case var held?) {
        web.window.removeEventListener('hashchange', held);
      }
      unawaited(controller.close());
    },
  );
  return controller.stream;
}
