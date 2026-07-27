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

  String get entrypointPath => p.join(outputDir, 'main.dart');

  /// The entries whose wrappers are currently imported, in import order.
  Iterable<CatalogEntry> get visited => _visited;
  final _visited = <CatalogEntry>[];

  /// Makes [active] the rendered entry, adding it to the entrypoint if this is
  /// the first visit. Returns the files a caller should invalidate.
  List<Uri> select(CatalogEntry active) {
    Directory(outputDir).createSync(recursive: true);

    var invalidated = <Uri>[];
    if (!_wrapperIndex.containsKey(active.id)) {
      var index = _wrapperIndex.length;
      _wrapperIndex[active.id] = index;
      _visited.add(active);
      var wrapper = File(p.join(outputDir, 'entry_$index.dart'));
      wrapper.writeAsStringSync(_wrapper(active, index));
      invalidated.add(wrapper.uri);
    }

    var entrypoint = File(entrypointPath);
    entrypoint.writeAsStringSync(_entrypoint(active));
    invalidated.add(entrypoint.uri);
    return invalidated;
  }

  String _wrapper(CatalogEntry entry, int index) {
    var source = p.join(projectRoot, entry.path);
    var carried = _carriedImports(source);
    return '''
// GENERATED — do not edit.
// Imports carried from the demo file: the annotation is written in *its* scope,
// so anything the annotation names has to resolve here too.
${carried.join('\n')}
import 'package:flutterware/ui_catalog.dart';

import '${_relative(source)}' as fw$index;

// The annotation, evaluated as Dart rather than interpreted statically.
// `transform()` returns a plain Preview and drops id/figma/formFactor, so the
// annotation itself is kept alongside it.
const fwDemo = ${entry.annotation};

const fwBuilder = fw$index.${entry.symbol};
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

$imports
// Getters, never top-level finals: a final is initialised once and hot reload
// does not re-run its initialiser, which would freeze the entry.
Preview get _preview => fw$activeIndex.fwDemo.transform();
Widget Function() get _builder => fw$activeIndex.fwBuilder;
String get _entryId => r'${active.id}';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _CatalogHost());
${emitProbe ? _probe : ''}}

class _CatalogHost extends StatelessWidget {
  const _CatalogHost();

  @override
  Widget build(BuildContext context) {
    var preview = _preview;
    var wrapper = preview.wrapper ?? (Widget child) => child;
    var size = preview.size;
    Widget child = KeyedSubtree(
      // A fresh key per entry so switching remounts rather than reusing the
      // previous entry's State.
      key: ValueKey<String>(_entryId),
      child: wrapper(_builder()),
    );
    if (size != null) {
      child = Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      );
    }
    return Directionality(textDirection: TextDirection.ltr, child: child);
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
    print('FW-PROBE: $_entryId | ${_preview.name} | ${texts.join(' / ')}');
  });
''';

  String _relative(String target) =>
      p.split(p.relative(target, from: outputDir)).join('/');
}
