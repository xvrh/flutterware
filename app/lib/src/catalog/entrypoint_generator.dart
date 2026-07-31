import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog_entry.dart';
import 'catalog_wrapper.dart';

/// Writes the guest's entrypoint: one wrapper file per entry ever visited, plus
/// an accumulating `main.dart` that selects the active one.
///
/// Two rules from the spikes are structural here rather than enforced:
///
/// - **A fresh prefix per switch.** Each entry gets its own wrapper file
///   imported under its own prefix, so a prefix is never rebound to a different
///   library — which S3 measured as silently ignored.
/// - **Getters, never top-level finals.** A top-level `final` is initialised
///   once and hot reload does not re-run the initialiser, so the active entry
///   would freeze for the life of the session.
class EntrypointGenerator {
  EntrypointGenerator({
    required this.outputDir,
    required this.projectRoot,
    this.emitProbe = false,
  });

  /// Where generated sources are written. Must not be a directory anything
  /// else owns — regenerating clears the stale wrappers in it.
  final String outputDir;

  /// Resolves each entry's [CatalogEntry.path].
  final String projectRoot;

  /// Emits a periodic `FW-PROBE:` line naming the live entry and the text it is
  /// rendering, so a headless harness can assert what the guest actually shows
  /// rather than only that a reload reported success.
  final bool emitProbe;

  /// The wrapper files themselves, written the same way the web build writes
  /// them — see [CatalogWrapperWriter] for why that sharing is structural.
  late final _wrappers = CatalogWrapperWriter(
    outputDir: outputDir,
    projectRoot: projectRoot,
  );

  final _wrapperIndex = <String, int>{};

  /// Never reused, even after a [drop]. A recycled index would point a live
  /// prefix at a wrapper written for a different entry, which S3 measured as
  /// silently ignored rather than an error.
  var _nextIndex = 0;

  String get entrypointPath => p.join(outputDir, 'main.dart');

  /// The entries whose wrappers are currently imported, in import order.
  Iterable<CatalogEntry> get visited => _visited;
  final _visited = <CatalogEntry>[];

  /// What the entrypoint on disk currently renders. Null when the last [drop]
  /// removed it and no [select] has chosen a replacement.
  CatalogEntry? get active => _active;
  CatalogEntry? _active;

  /// Imports every entry up front, so that from here on the only file a
  /// [select] changes is `main.dart`.
  ///
  /// This is what makes one compiler safe to share. Deltas are relative to the
  /// compiler's baseline, not to any particular guest: if a wrapper were added
  /// on one client's first visit, a second client selecting that same entry
  /// later would get a delta with the wrapper *missing* — unchanged since the
  /// baseline — and its guest, which never had that library, would reload
  /// nothing. Registering everything at once removes the divergence rather than
  /// tracking it.
  ///
  /// The cost is that a demo that does not compile breaks the catalog's cold
  /// start rather than only its own entry.
  List<Uri> registerAll(List<CatalogEntry> entries) => [
    for (var entry in entries) ..._register(entry),
  ];

  /// Makes [active] the rendered entry, adding it to the entrypoint if this is
  /// the first visit. Returns the files a caller should invalidate.
  List<Uri> select(CatalogEntry active) {
    Directory(outputDir).createSync(recursive: true);

    _active = active;
    var invalidated = _register(active);
    var entrypoint = File(entrypointPath);
    entrypoint.writeAsStringSync(_entrypoint(active));
    invalidated.add(entrypoint.uri);
    return invalidated;
  }

  /// Stops importing [entries], so nothing they pull in is compiled.
  ///
  /// How a demo that does not compile is kept from breaking the whole catalog:
  /// the wrapper file stays on disk, but an entrypoint that does not import it
  /// makes it unreachable, and the compiler only compiles what it can reach.
  /// Returns what to invalidate.
  List<Uri> drop(Iterable<CatalogEntry> entries) {
    var removed = false;
    for (var entry in entries) {
      if (_wrapperIndex.remove(entry.id) == null) continue;
      _visited.removeWhere((e) => e.id == entry.id);
      removed = true;
    }
    if (!removed) return [];

    var active = _active;
    if (active == null || _wrapperIndex.containsKey(active.id)) {
      // Rewritten, not merely invalidated: the file on disk is what the
      // compiler reads, so leaving the import in place would keep compiling
      // exactly what was just dropped.
      return select(active ?? _visited.first);
    }
    // The active entry was itself dropped; the caller has to choose another and
    // call [select]. Until then the entrypoint on disk is stale, so say so by
    // returning nothing to invalidate.
    _active = null;
    return [];
  }

  List<Uri> _register(CatalogEntry entry) {
    if (_wrapperIndex.containsKey(entry.id)) return [];
    Directory(outputDir).createSync(recursive: true);
    var index = _nextIndex++;
    _wrapperIndex[entry.id] = index;
    _visited.add(entry);
    var wrapper = File(p.join(outputDir, 'entry_$index.dart'));
    wrapper.writeAsStringSync(_wrappers.source(entry, index));
    return [wrapper.uri];
  }

  String _entrypoint(CatalogEntry active) {
    var imports = StringBuffer();
    for (var entry in _visited) {
      var index = _wrapperIndex[entry.id]!;
      imports.writeln("import 'entry_$index.dart' as fw$index;");
    }
    var activeIndex = _wrapperIndex[active.id]!;

    return '''
// GENERATED — do not edit.
${emitProbe ? "import 'dart:async';\n" : ''}import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/ui_catalog_guest.dart';

$imports
// Getters, never top-level finals: a final is initialised once and hot reload
// does not re-run its initialiser, which would freeze the entry.
Preview get _preview => fw$activeIndex.fwDemo.transform();
Widget Function() get _builder => fw$activeIndex.fwBuilder;
String get _entryId => r'${active.id}';

// **The whole of main runs inside the log-capturing zone, binding and all.**
//
// Not a stylistic choice and not reversible: `PlatformDispatcher.onBeginFrame`
// captures `Zone.current` when it is *set*, and the binding sets it in
// `initInstances`. So a zone that started after `ensureInitialized` would have
// every build, layout and paint callback running in the zone that came before
// it — and a demo printing from `build`, which is the case this exists for,
// would print into the root zone and be captured by nothing at all.
void main() => GuestLogs.instance.install(() {
  WidgetsFlutterBinding.ensureInitialized();
  // The guest has no platform IME; typing in a demo's field is this or
  // nothing. Before runApp so the first field to focus finds it installed.
  GuestTextInput.instance.install();
  // Before runApp, and once: the panel may ask what knobs exist before the
  // first frame, and the extensions have to outlive every entry switch.
  CatalogParameters.instance.registerExtensions();
  // The axes are pushed *in* rather than read out, and the push can land
  // before the shell that reads them has built — so this has to be up before
  // anything renders, not merely before the first question.
  CatalogAxes.instance.registerExtensions();
  // Reads the demo's own subtree rather than the whole app, which is what
  // CatalogGuest.demoRoot marks. Null until the first build, and that is an
  // answer: a headless host draws nothing until a frame is asked for.
  var inspector = GuestInspector(
    rootOf: () => CatalogGuest.demoRoot,
    entryIdOf: () => CatalogParameters.instance.entryId,
  )..registerExtensions();
  // Off until something asks. The extension has to exist from the start for
  // the same reason the others do, but the per-frame work behind it costs
  // nothing until a panel turns it on.
  GuestWatch(
    inspector: inspector,
    rootOf: () => CatalogGuest.demoRoot,
    entryIdOf: () => CatalogParameters.instance.entryId,
  ).registerExtensions();
  // Framework errors, on stdout *and* kept where they can be asked for.
  //
  // A demo that throws while building paints Flutter's red ErrorWidget in the
  // guest and nothing else changes: the compile succeeded, the reload
  // succeeded, and every check that asserts on those passes while the user
  // looks at an error. The stdout line makes that visible to a human watching
  // a terminal; the buffer makes it visible to `fw`, to MCP and to a panel,
  // which read stdout for nothing but the VM service URI.
  GuestErrors.instance.install();
  GuestErrors.instance.registerExtensions();
  // Whether every image the build asked for has arrived — what a capture
  // polls so it does not photograph a layout whose pixels are still decoding.
  GuestImages.instance.registerExtensions();
  // And what the demo prints, which reached the *host's* console and nowhere
  // else: the GUI could not show it, `fw` could not return it, and an agent
  // driving a demo could not read the first thing a developer reaches for.
  GuestLogs.instance.registerExtensions();
  runApp(const _CatalogHost());
${emitProbe ? _probe : ''}});

class _CatalogHost extends StatelessWidget {
  const _CatalogHost();

  @override
  Widget build(BuildContext context) {
    // One wrapper, called the one way. A shell used to be called by name from
    // here, because its axes lived in named parameters that
    // `Widget Function(Widget)` erases; they are declared inside the shell now,
    // so there is nothing left for this file to know about it.
    var preview = _preview;
    var wrapper = preview.wrapper ?? (Widget child) => child;
    Widget child = CatalogGuest(
      entryId: _entryId,
      child: KeyedSubtree(
        // A fresh key per entry so switching remounts rather than reusing the
        // previous entry's State.
        key: ValueKey<String>(_entryId),
        child: wrapper(_builder()),
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
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );
  }
}
''';
  }

  static const _probe = r'''
  Timer.periodic(const Duration(milliseconds: 200), (_) {
    var texts = <String>[];
    void visit(Element e) {
      var widget = e.widget;
      if (widget is Text && widget.data != null) texts.add(widget.data!);
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    // The view's own numbers, not a widget's: what the host's window metrics
    // actually became is the question a device frame drawn in another process
    // cannot answer any other way.
    var view = WidgetsBinding.instance.platformDispatcher.implicitView;
    var padding = view?.padding;
    var insets = view?.viewInsets;
    print(
      'FW-PROBE: $_entryId | ${_preview.name} | ${texts.join(' / ')} '
      '| padding ${padding?.top},${padding?.bottom} '
      'insets ${insets?.top},${insets?.bottom}',
    );
  });
''';
}
