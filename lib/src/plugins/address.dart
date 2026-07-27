import 'package:collection/collection.dart';

/// Where something *is* — the one identifier the GUI, `fw`, MCP and an artifact
/// all carry.
///
/// ```
/// fw://<worktree>/<plugin>/<plugin-specific segments…>?<axes>
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
class Address {
  static const scheme = 'fw';

  /// The worktree directory name, or null when the address is relative to
  /// whichever session resolves it. Git guarantees these are distinct within a
  /// repo, which is why the name is enough and a path is not needed.
  final String? worktree;

  /// The declared plugin id — `flutterware.ui_catalog`. Null addresses the
  /// worktree itself, which is what "open this worktree" needs.
  final String? plugin;

  /// The plugin's own remainder, already decoded. Empty when the address names
  /// only a plugin.
  final List<String> segments;

  /// Applied axes — `theme`, `locale`, `device`. Held sorted by key so that two
  /// addresses naming the same thing are `==` and hash alike regardless of the
  /// order they were written in.
  final Map<String, String> axes;

  Address({
    this.worktree,
    this.plugin,
    List<String> segments = const [],
    Map<String, String> axes = const {},
  }) : segments = List.unmodifiable(segments),
       axes = Map.unmodifiable({
         for (var key in axes.keys.toList()..sort()) key: axes[key]!,
       }) {
    if (worktree != null && worktree!.isEmpty) {
      throw ArgumentError.value(worktree, 'worktree', 'Must not be empty.');
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

  /// True when this address does not name a worktree and has to be resolved
  /// against the session reading it.
  bool get isRelative => worktree == null;

  /// The plugin's remainder as a single slash-joined string, for plugins whose
  /// addressing is naturally a path.
  String get path => segments.join('/');

  Address copyWith({
    String? worktree,
    String? plugin,
    List<String>? segments,
    Map<String, String>? axes,
  }) => Address(
    worktree: worktree ?? this.worktree,
    plugin: plugin ?? this.plugin,
    segments: segments ?? this.segments,
    axes: axes ?? this.axes,
  );

  /// The same address resolved against [worktree]. What a session does to a
  /// relative address the moment it reads one.
  Address resolveIn(String worktree) =>
      isRelative ? copyWith(worktree: worktree) : this;

  /// The same address one segment deeper.
  Address child(String segment) => copyWith(segments: [...segments, segment]);

  /// The same address with [axes] merged over the current ones.
  Address withAxes(Map<String, String> axes) =>
      copyWith(axes: {...this.axes, ...axes});

  /// The same address with no axes applied — the identity of the thing, which
  /// is what a tree or a list keys on.
  Address get bare =>
      Address(worktree: worktree, plugin: plugin, segments: segments);

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

    // Deliberately not `Uri.parse`: it lowercases the authority, and a worktree
    // directory may legitimately have capitals.
    var parts = rest.split('/');
    var worktree = parts.first;
    var tail = parts.skip(1).toList();
    // `fw://wt/` and `fw://wt` name the same worktree.
    if (tail.length == 1 && tail.single.isEmpty) tail = [];
    if (tail.any((s) => s.isEmpty)) return null;

    try {
      return Address(
        worktree: worktree.isEmpty ? null : Uri.decodeComponent(worktree),
        plugin: tail.isEmpty ? null : Uri.decodeComponent(tail.first),
        segments: [for (var s in tail.skip(1)) Uri.decodeComponent(s)],
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
    var out = StringBuffer('$scheme://${_encode(worktree ?? '')}');
    if (plugin != null) {
      out.write('/${_encode(plugin!)}');
      for (var segment in segments) {
        out.write('/${_encode(segment)}');
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
      .replaceAll('%', '%25')
      .replaceAll('/', '%2F')
      .replaceAll('?', '%3F')
      .replaceAll('#', '%23')
      .replaceAll('&', '%26');

  @override
  bool operator ==(Object other) =>
      other is Address &&
      other.worktree == worktree &&
      other.plugin == plugin &&
      const ListEquality<String>().equals(other.segments, segments) &&
      const MapEquality<String, String>().equals(other.axes, axes);

  @override
  int get hashCode => Object.hash(
    worktree,
    plugin,
    const ListEquality<String>().hash(segments),
    const MapEquality<String, String>().hash(axes),
  );
}
