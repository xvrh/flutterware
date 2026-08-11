import 'dart:async';

import 'package:flutter/widgets.dart';

import '../inspect/guest_errors.dart';
import '../inspect/guest_images.dart';
import '../inspect/guest_inspect.dart';
import '../inspect/guest_logs.dart';
import 'guest_drive.dart';
import 'human_actions.dart';

/// Installs the run guest around a user app's `main` — what the generated
/// run entrypoint calls.
///
/// **The whole of main runs inside the log-capturing zone, binding and all** —
/// same rule as the previews entrypoint, and just as irreversible:
/// `PlatformDispatcher.onBeginFrame` captures `Zone.current` when it is set,
/// and the binding sets it in `initInstances`. A zone started after
/// `ensureInitialized` would capture nothing from build, layout or paint,
/// which is where the prints this exists for come from.
///
/// Unlike the previews guest there is no keyboard or text-input replacement
/// here: this app runs on a real platform with a real IME, and `enterText`
/// goes through `TextInput.updateEditingValue` instead.
FutureOr<void> runGuest(FutureOr<void> Function() appMain) {
  return GuestLogs.instance.install(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Framework errors, on stdout *and* kept where they can be asked for —
    // the bundle's `errors` field is the diff of this buffer.
    GuestErrors.instance.install();
    GuestErrors.instance.registerExtensions();
    GuestImages.instance.registerExtensions();
    GuestLogs.instance.registerExtensions();
    // The whole app is the subject — no catalog chrome to scope away, so the
    // root element is the root of the reported tree. Null until the first
    // build, and that is an answer.
    var inspector = GuestInspector(
      rootOf: () => WidgetsBinding.instance.rootElement,
      entryIdOf: () => null,
    )..registerExtensions();
    // The other half of co-driving: the human's taps between tool steps ride
    // the next reply and land in the journal as `actor: human`.
    var humanActions = HumanActions()..install();
    GuestDrive(
      inspector: inspector,
      humanActions: humanActions,
    ).registerExtensions();
    return appMain();
  });
}
