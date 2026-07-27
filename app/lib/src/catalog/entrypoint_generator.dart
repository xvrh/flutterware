import 'dart:io';

import 'package:path/path.dart' as p;

import 'catalog_entry.dart';

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
    wrapper.writeAsStringSync(_wrapper(entry, index));
    return [wrapper.uri];
  }

  String _wrapper(CatalogEntry entry, int index) {
    var source = p.join(projectRoot, entry.path);
    var carried = _carriedImports(source);
    return '''
// GENERATED — do not edit.
// Imports carried from the demo file: the annotation is written in *its* scope,
// so anything the annotation names has to resolve here too.
${carried.join('\n')}
// Unconditional: the getters below are typed, and a demo file is not obliged
// to import widgets itself.
import 'package:flutter/widgets.dart';
import 'package:flutterware/ui_catalog.dart';

import '${_relative(source)}' as fw$index;

// The annotation, evaluated as Dart rather than interpreted statically.
// `transform()` returns a plain Preview and drops id/figma/formFactor, so the
// annotation itself is kept alongside it.
//
// Getters, not consts. A const holding a function tear-off — every `wrapper:`
// is one — is inlined into whichever library reads it, so the entrypoint's
// constant pool ends up referring to a procedure in the demo's own file. A
// reload that carries only the entrypoint then has to re-resolve that
// reference against a library it does not contain, and the guest renders
// `Lookup failed: <wrapper> in @methods in file:...` instead of the demo.
// Behind a getter there is nothing to inline and nothing to re-resolve.
Demo get fwDemo => ${entry.annotation};

Widget Function() get fwBuilder => fw$index.${entry.symbol};
''';
  }

  /// The demo file's own import directives, with relative URIs rewritten to
  /// resolve from [outputDir].
  ///
  /// Demo files live outside `lib/` and so have no `package:` URI of their own;
  /// a carried `../utils/shell.dart` would not resolve from the generated
  /// directory without this.
  List<String> _carriedImports(String source) {
    var directive = RegExp(
      r'''^\s*(import|export)\s+(['"])([^'"]+)\2(.*)$''',
      multiLine: true,
    );
    var carried = <String>[];
    for (var match in directive.allMatches(File(source).readAsStringSync())) {
      var uri = match.group(3)!;
      // `package:flutterware/ui_catalog.dart` is emitted unconditionally below.
      if (uri == 'package:flutterware/ui_catalog.dart') continue;
      if (uri.contains(':')) {
        carried.add(match.group(0)!.trim());
      } else {
        var target = p.normalize(p.join(p.dirname(source), uri));
        carried.add(
          "${match.group(1)} '${_relative(target)}'${match.group(4)};"
              .replaceAll(';;', ';'),
        );
      }
    }
    return carried;
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
import 'package:flutterware/ui_catalog.dart';

$imports
// Getters, never top-level finals: a final is initialised once and hot reload
// does not re-run its initialiser, which would freeze the entry.
Preview get _preview => fw$activeIndex.fwDemo.transform();
Widget Function() get _builder => fw$activeIndex.fwBuilder;
String get _entryId => r'${active.id}';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Before runApp, and once: the panel may ask what knobs exist before the
  // first frame, and the extensions have to outlive every entry switch.
  CatalogParameters.instance.registerExtensions();
  // Framework errors, on stdout, always.
  //
  // A demo that throws while building paints Flutter's red ErrorWidget in the
  // guest and nothing else changes: the compile succeeded, the reload
  // succeeded, and every check that asserts on those passes while the user
  // looks at an error. This is what makes such a failure observable to
  // anything that is not a pair of eyes.
  FlutterError.onError = (details) {
    print('FW-ERROR: \${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };
  runApp(const _CatalogHost());
${emitProbe ? _probe : ''}}

class _CatalogHost extends StatelessWidget {
  const _CatalogHost();

  @override
  Widget build(BuildContext context) {
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

  String _relative(String target) =>
      p.split(p.relative(target, from: outputDir)).join('/');
}
