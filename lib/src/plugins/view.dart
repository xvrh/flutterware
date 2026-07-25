import 'tone.dart';

/// A plugin's answer to "what are you showing right now?", as data.
///
/// Native plugins draw real Flutter widgets for humans. They *also* emit one of
/// these, so the same state reaches `fw`, a file projection, and an agent. That
/// is decision 2: the panel forks, the contract does not.
///
/// This is deliberately **not** a rendering kit — nothing interprets these
/// nodes to build the GUI. It is a projection: a summary faithful enough that
/// reading it tells you what is on screen.
class PluginView {
  const PluginView(this.nodes);

  static const empty = PluginView([]);

  final List<ViewNode> nodes;

  bool get isEmpty => nodes.isEmpty;

  /// Renders the projection as an indented plain-text tree — what `fw` prints
  /// and what an agent reads.
  String toText() {
    var out = StringBuffer();
    for (var node in nodes) {
      node.writeText(out, 0);
    }
    return out.toString().trimRight();
  }

  List<Map<String, Object?>> toJson() => [for (var n in nodes) n.toJson()];

  @override
  String toString() => toText();
}

sealed class ViewNode {
  const ViewNode();

  Map<String, Object?> toJson();

  void writeText(StringBuffer out, int depth);

  static String _pad(int depth) => '  ' * depth;
}

/// A titled group. The only node that nests.
class ViewSection extends ViewNode {
  const ViewSection(this.title, this.children);

  final String title;
  final List<ViewNode> children;

  @override
  Map<String, Object?> toJson() => {
    'node': 'section',
    'title': title,
    'children': [for (var c in children) c.toJson()],
  };

  @override
  void writeText(StringBuffer out, int depth) {
    out.writeln('${ViewNode._pad(depth)}$title');
    for (var child in children) {
      child.writeText(out, depth + 1);
    }
  }
}

/// A free line of prose — a summary, a hint, an error message.
class ViewText extends ViewNode {
  const ViewText(this.text, {this.tone = Tone.neutral});

  final String text;
  final Tone tone;

  @override
  Map<String, Object?> toJson() => {
    'node': 'text',
    'text': text,
    if (tone != Tone.neutral) 'tone': tone.name,
  };

  @override
  void writeText(StringBuffer out, int depth) {
    out.writeln('${ViewNode._pad(depth)}$text');
  }
}

/// A labelled value — the workhorse.
class ViewField extends ViewNode {
  const ViewField(this.label, this.value, {this.tone = Tone.neutral});

  final String label;
  final String value;
  final Tone tone;

  @override
  Map<String, Object?> toJson() => {
    'node': 'field',
    'label': label,
    'value': value,
    if (tone != Tone.neutral) 'tone': tone.name,
  };

  @override
  void writeText(StringBuffer out, int depth) {
    out.writeln('${ViewNode._pad(depth)}$label: $value');
  }
}

/// One row of a [ViewItems] list: a name plus optional trailing state.
class ViewItem {
  const ViewItem(this.label, {this.detail, this.tone = Tone.neutral});

  final String label;
  final String? detail;
  final Tone tone;

  Map<String, Object?> toJson() => {
    'label': label,
    if (detail != null) 'detail': detail,
    if (tone != Tone.neutral) 'tone': tone.name,
  };
}

/// A flat list — catalog entries, failing tests, running processes.
class ViewItems extends ViewNode {
  const ViewItems(this.items, {this.truncated = 0});

  final List<ViewItem> items;

  /// How many further items exist but were left out. Never silently drop rows:
  /// a projection that looks complete when it is not is worse than a long one.
  final int truncated;

  @override
  Map<String, Object?> toJson() => {
    'node': 'items',
    'items': [for (var i in items) i.toJson()],
    if (truncated > 0) 'truncated': truncated,
  };

  @override
  void writeText(StringBuffer out, int depth) {
    var pad = ViewNode._pad(depth);
    var width = items.fold(
      0,
      (w, i) => i.label.length > w ? i.label.length : w,
    );
    for (var item in items) {
      out.write('$pad- ${item.label}');
      if (item.detail != null) {
        out.write('${' ' * (width - item.label.length + 2)}${item.detail}');
      }
      out.writeln();
    }
    if (truncated > 0) {
      out.writeln('$pad… $truncated more');
    }
  }
}

/// A table with a header row. Columns are aligned in the text rendering.
class ViewTable extends ViewNode {
  const ViewTable(this.columns, this.rows, {this.truncated = 0});

  final List<String> columns;
  final List<List<String>> rows;

  /// Rows omitted from this projection — see [ViewItems.truncated].
  final int truncated;

  @override
  Map<String, Object?> toJson() => {
    'node': 'table',
    'columns': columns,
    'rows': rows,
    if (truncated > 0) 'truncated': truncated,
  };

  @override
  void writeText(StringBuffer out, int depth) {
    var pad = ViewNode._pad(depth);
    var widths = [
      for (var (i, column) in columns.indexed)
        rows.fold(column.length, (w, row) {
          var cell = i < row.length ? row[i] : '';
          return cell.length > w ? cell.length : w;
        }),
    ];

    void writeRow(List<String> cells) {
      var parts = [
        for (var (i, width) in widths.indexed)
          (i < cells.length ? cells[i] : '').padRight(width),
      ];
      out.writeln('$pad${parts.join('  ').trimRight()}');
    }

    writeRow(columns);
    for (var row in rows) {
      writeRow(row);
    }
    if (truncated > 0) {
      out.writeln('$pad… $truncated more');
    }
  }
}
