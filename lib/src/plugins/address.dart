import 'package:collection/collection.dart';

/// Where something *is* — the one identifier the GUI, `fw`, MCP and an artifact
/// all carry.
///
/// ```
/// fw://<project>/<space>/<the space's own path…>?<axes>
/// ```
///
/// with exactly one space defined today:
///
/// ```
/// fw:///worktrees                              the collection
/// fw:///worktrees/<name>                       one worktree's home
/// fw:///worktrees/<name>/<plugin>/<segments…>  a plugin panel
/// ```
///
/// The framework parses up to and including the plugin segment. **Everything
/// after it is opaque to the framework and owned by the plugin** — the catalog
/// chooses its own entry addressing without this file knowing about it. That
/// rule is what stops the parser growing a case per plugin.
///
/// Segments are identity; query parameters are *applied axes*. A catalog entry
/// in dark mode is the same entry seen differently, so `theme` is a query
/// parameter — which is what makes an address with its axes resolved a complete
/// capture spec rather than an under-specified one.
///
/// **Only [project] is the URI authority; everything else is a path segment.**
/// That is what lets `Uri.parse` agree with this parser instead of contradicting
/// it — an authority is lowercased and a worktree name may have capitals. There
/// is a test that asserts the agreement.
///
/// One exception, recorded because it cannot be fixed: a segment consisting
/// only of dots is a relative-path operator, and Dart's `Uri` decodes before it
/// normalises, so `..` is resolved away however it is escaped. Nothing can
/// produce such a segment — git sanitises worktree names, and no plugin id or
/// entry id is only dots — so this is a note rather than a hazard.
class Address {
  static const scheme = 'fw';

  /// The only [space] there is today. The slot exists so a cross-worktree
  /// screen can be addressed without competing with a checkout for the first
  /// path segment — the same reasoning that made `Worktree.mainName` a
  /// character git cannot produce, applied one level up.
  static const worktreesSpace = 'worktrees';

  /// The one name in the [plugin] slot that is **not** a plugin:
  /// `fw:///worktrees/<worktree>/config` is the shell's own screen for the
  /// worktree's `tool/flutterware.dart` — what it resolved to, what each reload
  /// cost, and why it failed when it did.
  ///
  /// It sits in the plugin slot rather than getting a field of its own because
  /// it is addressed exactly like a plugin: one thing per worktree, mounted
  /// where a panel mounts, remembered per tab like any other place. A second
  /// field would make every reader of an address handle a case that behaves
  /// identically.
  ///
  /// A plugin cannot shadow it — `FlutterwareConfig.use` refuses this id — which
  /// is what makes the reservation a fact rather than a convention. Real plugin
  /// ids are dotted and globally unique, so nothing legitimate wanted it.
  static const shellConfig = 'config';

  /// Which project this address belongs to, or null for "the one the session
  /// reading it was launched in" — which is every address anything emits today,
  /// since a shell is opened on one repo and discovers that repo's worktrees.
  ///
  /// Reserved rather than used. It exists because a `fw://` link followed from
  /// a browser or a chat window arrives at *an* installed flutterware knowing
  /// nothing about which checkout it is for, and that is precisely the question
  /// a URI authority answers. Adding the slot later would have meant reparsing
  /// every address ever written down.
  final String? project;

  /// The top-level namespace. [worktreesSpace] is the only one today; the slot
  /// exists so a cross-worktree screen can be addressed without competing with
  /// a checkout for the first path segment.
  ///
  /// Parsed as data, never validated here — an unknown space is a *resolution*
  /// failure, reported where an unknown worktree already is, which is what
  /// keeps this file free of a registry.
  final String? space;

  /// Git's own name for the worktree (see `Worktree.name`), or null when the
  /// address names no worktree at all — which is where the shell sits before
  /// the first one opens.
  final String? worktree;

  /// The declared plugin id — `flutterware.previews`. Null addresses the
  /// worktree itself, which is what "open this worktree" needs.
  final String? plugin;

  /// The plugin's own remainder, already decoded. Empty when the address names
  /// only a plugin.
  final List<String> segments;

  /// Applied axes — `theme`, `locale`, `device`. Held sorted by key so that two
  /// addresses naming the same thing are `==` and hash alike regardless of the
  /// order they were written in.
  final Map<String, String> axes;

  /// [space] defaults to the one a worktree lives in, so the many call sites
  /// that name a worktree and a plugin read exactly as they did before the
  /// space segment existed.
  Address({
    this.project,
    String? space,
    this.worktree,
    this.plugin,
    List<String> segments = const [],
    Map<String, String> axes = const {},
  }) : space = space ?? (worktree != null ? worktreesSpace : null),
       segments = List.unmodifiable(segments),
       axes = Map.unmodifiable({
         for (var key in axes.keys.toList()..sort()) key: axes[key]!,
       }) {
    if (project != null && project!.isEmpty) {
      throw ArgumentError.value(project, 'project', 'Must not be empty.');
    }
    if (this.space != null && this.space!.isEmpty) {
      throw ArgumentError.value(space, 'space', 'Must not be empty.');
    }
    if (worktree != null && this.space != worktreesSpace) {
      throw ArgumentError.value(
        space,
        'space',
        'A worktree lives in the $worktreesSpace space; no other space has one.',
      );
    }
    if (worktree != null && worktree!.isEmpty) {
      throw ArgumentError.value(worktree, 'worktree', 'Must not be empty.');
    }
    if (worktree == null && plugin != null) {
      throw ArgumentError.value(
        plugin,
        'plugin',
        'A plugin is reached through a worktree; an address naming one must '
            'name a worktree.',
      );
    }
    if (plugin != null && plugin!.isEmpty) {
      throw ArgumentError.value(plugin, 'plugin', 'Must not be empty.');
    }
    if (plugin == null && this.segments.isNotEmpty) {
      throw ArgumentError.value(
        segments,
        'segments',
        'Segments belong to a plugin; an address with segments must name one.',
      );
    }
  }

  /// The plugin's remainder as a single slash-joined string, for plugins whose
  /// addressing is naturally a path.
  String get path => segments.join('/');

  Address copyWith({
    String? project,
    String? space,
    String? worktree,
    String? plugin,
    List<String>? segments,
    Map<String, String>? axes,
  }) => Address(
    project: project ?? this.project,
    space: space ?? this.space,
    worktree: worktree ?? this.worktree,
    plugin: plugin ?? this.plugin,
    segments: segments ?? this.segments,
    axes: axes ?? this.axes,
  );

  /// The same address one segment deeper.
  Address child(String segment) => copyWith(segments: [...segments, segment]);

  /// The same address with [axes] merged over the current ones.
  Address withAxes(Map<String, String> axes) =>
      copyWith(axes: {...this.axes, ...axes});

  /// The same address with no axes applied — the identity of the thing, which
  /// is what a tree or a list keys on.
  Address get bare => Address(
    project: project,
    space: space,
    worktree: worktree,
    plugin: plugin,
    segments: segments,
  );

  static Address parse(String source) =>
      tryParse(source) ??
      (throw FormatException('Not a flutterware address', source));

  /// Null rather than throwing, for the many places that read user input.
  static Address? tryParse(String source) {
    const prefix = '$scheme://';
    if (!source.startsWith(prefix)) return null;

    var rest = source.substring(prefix.length);

    // The fragment is not part of the grammar. Reject rather than silently drop
    // it — a plugin segment containing `#` has to arrive percent-encoded, and
    // quietly truncating there would lose half of an entry id.
    if (rest.contains('#')) return null;

    var axes = const <String, String>{};
    var queryStart = rest.indexOf('?');
    if (queryStart >= 0) {
      var query = rest.substring(queryStart + 1);
      rest = rest.substring(0, queryStart);
      var parsed = <String, String>{};
      for (var pair in query.split('&')) {
        if (pair.isEmpty) continue;
        var eq = pair.indexOf('=');
        if (eq < 0) return null;
        parsed[Uri.decodeComponent(pair.substring(0, eq))] =
            Uri.decodeComponent(pair.substring(eq + 1));
      }
      axes = parsed;
    }

    // Hand-parsed rather than `Uri.parse`, to keep the percent-encoding
    // deliberately sparse — `_encode` escapes only what would be read as
    // structure, so `team.dart%23TeamList` stays legible where `Uri` would
    // escape more. The two agree on everything they both decide, and
    // `address_test.dart` asserts it.
    var parts = rest.split('/');
    // The authority. Empty is the normal case and means "this session's
    // project"; it is not a segment and never was one.
    var project = parts.first;
    var path = parts.skip(1).toList();
    // `fw:///worktrees/wt/` and `fw:///worktrees/wt` name the same worktree.
    if (path.isNotEmpty && path.last.isEmpty) path.removeLast();
    if (path.any((s) => s.isEmpty)) return null;

    try {
      return Address(
        project: project.isEmpty ? null : Uri.decodeComponent(project),
        space: path.isEmpty ? null : Uri.decodeComponent(path.first),
        worktree: path.length < 2 ? null : Uri.decodeComponent(path[1]),
        plugin: path.length < 3 ? null : Uri.decodeComponent(path[2]),
        segments: [for (var s in path.skip(3)) Uri.decodeComponent(s)],
        axes: axes,
      );
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() {
    // `//` even when the project is empty. It is what makes the whole thing get
    // linkified when pasted, and what an OS registers to route a click back
    // here; `fw:/…` would be equally correct per RFC and recognised by nothing.
    var out = StringBuffer('$scheme://${_encode(project ?? '')}');
    // Always the leading slash, so `fw:///` names nothing and reads as an empty
    // authority rather than as a truncated address.
    out.write('/');
    if (space != null) {
      out.write(_encode(space!));
      if (worktree != null) {
        out.write('/${_encode(worktree!)}');
        if (plugin != null) {
          out.write('/${_encode(plugin!)}');
          for (var segment in segments) {
            out.write('/${_encode(segment)}');
          }
        }
      }
    }
    if (axes.isNotEmpty) {
      out.write('?');
      // `encodeComponent`, not `encodeQueryComponent`: the latter is HTML form
      // encoding, where a space becomes `+`. An address gets pasted into logs,
      // filenames and terminals, and `+` only decodes back to a space for a
      // reader who knows it is form-encoded. `%20` is unambiguous everywhere.
      out.write(
        [
          for (var entry in axes.entries)
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        ].join('&'),
      );
    }
    return out.toString();
  }

  /// Percent-encodes only what would otherwise be read as structure. A catalog
  /// entry stays legible — `team.dart%23TeamList`, not an unreadable blob.
  static String _encode(String segment) => segment
      // `%` first: it is the escape character, so escaping it after anything
      // else would escape the escapes.
      .replaceAll('%', '%25')
      .replaceAll('/', '%2F')
      .replaceAll('?', '%3F')
      .replaceAll('#', '%23')
      .replaceAll('&', '%26');

  @override
  bool operator ==(Object other) =>
      other is Address &&
      other.project == project &&
      other.space == space &&
      other.worktree == worktree &&
      other.plugin == plugin &&
      const ListEquality<String>().equals(other.segments, segments) &&
      const MapEquality<String, String>().equals(other.axes, axes);

  @override
  int get hashCode => Object.hash(
    project,
    space,
    worktree,
    plugin,
    const ListEquality<String>().hash(segments),
    const MapEquality<String, String>().hash(axes),
  );
}
