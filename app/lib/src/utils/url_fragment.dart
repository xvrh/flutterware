/// The page's `#fragment`, as an address a viewer keeps its place in.
///
/// An exported page has no router and needs none — one tab and one selection
/// are its whole state — but a place that is not in the URL cannot be linked
/// to, and the PR comment's job is precisely to link into the page. So the
/// viewer writes its place here and reads it back on arrival.
///
/// Everywhere but the web there is no address bar: writes vanish and the
/// change stream never fires. That is the `io` half, and it is what a widget
/// test gets.
library;

export 'url_fragment_io.dart'
    if (dart.library.js_interop) 'url_fragment_web.dart';
