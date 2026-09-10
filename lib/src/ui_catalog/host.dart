import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

import 'catalog_keyboard.dart';
import 'entries.dart';
import 'guest.dart';

/// One catalog entry, resolved by id: its annotation and how to build it.
typedef CatalogEntryBuilder = ({Preview preview, Widget Function() builder});

/// The guest's root: whichever entry the host has asked for, built the one
/// way, under the media query a device's safe areas become.
///
/// This is what the generated entrypoint runs, and what an in-process host
/// puts in its own tree — the same widget, so a demo is staged identically
/// whether it is drawn in an embedder process or inline.
///
/// [entryOf] resolves an id to its entry, or null for one this program does
/// not hold; [fileEntryId] is the entry the program was generated for, which
/// wins when a switch names something unknown — see [CatalogEntries].
class CatalogHost extends StatelessWidget {
  const CatalogHost({
    super.key,
    required this.fileEntryId,
    required this.entryOf,
  });

  final String fileEntryId;
  final CatalogEntryBuilder? Function(String id) entryOf;

  @override
  Widget build(BuildContext context) => CatalogEntries.instance.build(
    fromFile: fileEntryId,
    builder: _buildEntry,
  );

  Widget _buildEntry(BuildContext context, String entryId) {
    // The file's entry when a switch named something this program does not
    // hold. It cannot normally: the host only ever asks for an id the compiler
    // handshake reported, and a switch to anything else is refused in the
    // guest rather than answered. This is the reload that changed the catalog
    // under a switch already made.
    var entry = entryOf(entryId) ?? entryOf(fileEntryId)!;
    // One wrapper, called the one way. A shell used to be called by name from
    // here, because its axes lived in named parameters that
    // `Widget Function(Widget)` erases; they are declared inside the shell now,
    // so there is nothing left for this file to know about it.
    var wrapper = entry.preview.wrapper ?? (Widget child) => child;
    Widget child = CatalogGuest(
      entryId: entryId,
      child: KeyedSubtree(
        // A fresh key per entry so switching remounts rather than reusing the
        // previous entry's State.
        key: ValueKey<String>(entryId),
        child: wrapper(entry.builder()),
      ),
    );
    // No `preview.size` here. The host sizes the guest's *window* to whatever
    // device is chosen — which is how a demo reads a phone's dimensions from
    // MediaQuery — and a SizedBox in here would fight it: an entry declaring
    // desktop would run off the edge of a phone that was picked on purpose.
    // The annotation still chooses which device the picker starts on.
    //
    // The device's safe areas arrive as view *insets*, because
    // FlutterWindowMetricsEvent has no padding field — only
    // `physical_view_inset_*` — and a frame drawn in the host's process cannot
    // reach in here any other way. Turning them back into padding belongs
    // above the entry's wrapper: `View` is what builds the root MediaQuery,
    // and WidgetsApp inherits it rather than making its own, so an override
    // here is what a MaterialApp inside the wrapper will read.
    var media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.viewInsets,
        viewPadding: media.viewInsets,
        viewInsets: EdgeInsets.zero,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        // The keyboard: the insets it takes out of the screen, and the slab
        // that says where they went. Below the conversion above rather than
        // beside it — it reads the padding that produced as the device's own
        // safe areas and subtracts its own height from the bottom of them,
        // which is the arithmetic a real embedder reports.
        child: CatalogKeyboardScope(child: child),
      ),
    );
  }
}
