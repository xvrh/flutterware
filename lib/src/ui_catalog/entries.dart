import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Which entry the guest is showing, and how it is told to show another.
///
/// The whole catalog is already in the program. The generated entrypoint
/// imports every entry's wrapper — that is what makes one compiler safe to
/// share — so the running guest can build any of them without being sent
/// anything. That went unused until this existed: the entrypoint named one
/// entry in a getter, and switching meant regenerating the file, recompiling
/// it and hot-reloading the guest. Measured on a 100-entry catalog, that was
/// 45ms of compile and 302ms of reload and reassemble, per entry, to move an
/// integer.
///
/// So a switch is a message and a frame instead: `ext.flutterware.showEntry`
/// moves the mounted state, and the entry remounts exactly as a reload made it
/// remount — [CatalogGuest] resets the knobs, the axes, the errors and the
/// logs off the same `entryId` change either way.
///
/// A reload still wins. The entrypoint on disk names an entry, and the
/// panel switches demos by rewriting that name and reloading — so a runtime
/// switch only holds while the file has not moved under it. The rebase is a
/// plain assignment in `didUpdateWidget`, which is both the moment the new
/// name arrives and the rebuild that was going to happen anyway; an ordinary
/// source edit reloads with the same name and changes nothing here.
class CatalogEntries {
  CatalogEntries._();

  static final instance = CatalogEntries._();

  /// The entry the last frame built, or null before the first one.
  ///
  /// Public because the same argument [CatalogKnobs.entryId] makes applies
  /// here: anything reporting on the live build has to be able to say which
  /// demo it was looking at.
  String? get showing => _state?.entryId;

  /// The ids the running program holds.
  ///
  /// A thunk rather than a set, for the reason the entrypoint's own accessors
  /// are functions and getters: a hot reload does not re-run `main`, so
  /// anything captured there would describe the catalog as it was when the
  /// guest started.
  Iterable<String> Function() _ids = _none;
  static Iterable<String> _none() => const [];

  _CatalogEntrySwitchState? _state;

  /// Tells this which ids the program holds. Call once, before `runApp`.
  void install(Iterable<String> Function() ids) => _ids = ids;

  /// Shows [id] on the next frame, and reports what is on screen after the
  /// call.
  ///
  /// Neither an id this program does not hold nor a call that beat the first
  /// frame is an error to raise. The host's recovery for both is the compile
  /// and the reload it would have done anyway — which is also its recovery for
  /// a guest too old to have this at all — so answering with whatever is
  /// *actually* showing lets it tell "switched" from "could not" by comparison,
  /// with no exception path to get right on either side.
  String? show(String id) {
    var state = _state;
    if (state != null && id != state.entryId && _ids().contains(id)) {
      state.show(id);
    }
    return _state?.entryId;
  }

  /// Registers the extension. Call once, before `runApp`.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.showEntry', (_, args) async {
      var before = _state?.entryId;
      var showing = show(args['id'] ?? '');
      if (showing != before) {
        // Both halves, for the reason `imagesSettled` gives: this guest is
        // headless and draws when something asks, so marking the tree dirty is
        // not by itself a frame. Answered only once that frame is on screen —
        // a reply that came back first would have the host reading the
        // previous entry's errors under this entry's name.
        SchedulerBinding.instance.scheduleFrame();
        await SchedulerBinding.instance.endOfFrame.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'entry': showing}),
      );
    });
  }

  /// Builds whichever entry is current, rebasing on [fromFile] whenever a
  /// reload has regenerated the entrypoint under it.
  ///
  /// [builder] is the generated entrypoint's own: resolving an id to a demo
  /// needs the table of imports, which only that file has.
  Widget build({
    required String fromFile,
    required Widget Function(BuildContext context, String entryId) builder,
  }) =>
      _CatalogEntrySwitch(entries: this, fromFile: fromFile, builder: builder);
}

class _CatalogEntrySwitch extends StatefulWidget {
  const _CatalogEntrySwitch({
    required this.entries,
    required this.fromFile,
    required this.builder,
  });

  final CatalogEntries entries;

  /// What this generation of the entrypoint names.
  final String fromFile;

  final Widget Function(BuildContext context, String entryId) builder;

  @override
  State<_CatalogEntrySwitch> createState() => _CatalogEntrySwitchState();
}

class _CatalogEntrySwitchState extends State<_CatalogEntrySwitch> {
  late String entryId = widget.fromFile;

  @override
  void initState() {
    super.initState();
    widget.entries._state = this;
  }

  @override
  void didUpdateWidget(_CatalogEntrySwitch old) {
    super.didUpdateWidget(old);
    // The file moved, which only a reload can do, and a reload carrying a
    // different name *is* the panel saying "show that one". A reload caused by
    // an ordinary source edit carries the same name and leaves a runtime
    // switch where it was.
    //
    // An assignment rather than a notification: this runs inside the rebuild
    // that is already going to render it, so there is nothing to mark dirty.
    if (widget.fromFile != old.fromFile) entryId = widget.fromFile;
  }

  @override
  void dispose() {
    if (widget.entries._state == this) widget.entries._state = null;
    super.dispose();
  }

  void show(String id) => setState(() => entryId = id);

  @override
  Widget build(BuildContext context) => widget.builder(context, entryId);
}
