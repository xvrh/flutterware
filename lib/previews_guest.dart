/// The guest's own plumbing — for generated code, not for projects.
///
/// The generated entrypoint is written into the user's project and imports the
/// package like any other consumer, so this surface has to be importable. It is
/// a separate library so that fact does not put host-driven machinery beside
/// the published API: `previews.dart` and `ui_catalog.dart` are the semver
/// commitments, this file follows the generators.
///
/// Nothing here is expected to be called by hand. A project writing previews
/// needs `@Preview` from Flutter and, for a shell or a knob, `previews.dart`.
library;

export 'src/ui_catalog/guest.dart' show CatalogGuest, CatalogKnobs;
export 'src/ui_catalog/axes.dart' show CatalogAxes;
export 'src/ui_catalog/guest_keyboard.dart' show GuestKeyboard;
export 'src/ui_catalog/guest_text_input.dart' show GuestTextInput;
export 'src/ui_catalog/knob.dart' show KnobDescriptor, KnobKind, KnobReport;
export 'src/ui_catalog/axis.dart' show AxisReport;
export 'src/inspect/error.dart' show InspectError, InspectErrors;
export 'src/inspect/guest_errors.dart' show GuestErrors;
export 'src/inspect/guest_images.dart' show GuestImages;
export 'src/inspect/guest_logs.dart' show GuestLogs;
export 'src/inspect/log.dart' show InspectLogLine, InspectLogs;
export 'src/inspect/guest_inspect.dart' show GuestInspector;
export 'src/inspect/guest_watch.dart' show GuestWatch;
// The models come with it for the reason the layout types come with the node:
// a host can subscribe to the watch without them but cannot name what arrives.
export 'src/inspect/watch.dart' show WatchBox, WatchPush, WatchStats;
// The layout types come with the node rather than after it: a consumer can
// reach `InspectNode.layout` without them but cannot name what it got, which
// made the shorter list an export that only looked complete.
export 'src/inspect/node.dart'
    show
        InspectConstraints,
        InspectFlex,
        InspectLayout,
        InspectNode,
        InspectSource,
        InspectTree;
