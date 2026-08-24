import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'table.dart';

const _eq = DeepCollectionEquality();

/// The presentation layout of a table's columns — their [order], which are
/// [hidden], and any [widths] set by resizing — independent of the data.
/// Applied to a `List<FwTableColumn>` at render time via [apply].
///
/// Forward-compatible by design: a key the layout has never seen (a column
/// added to the code after the layout was saved) appends after the known ones
/// and is visible by default, so new columns never silently disappear.
///
/// Ported from `cms/packages/admin_ui/lib/src/collection/column_layout.dart`.
@immutable
class ColumnLayout {
  /// Column keys in display order. Keys not listed here are unknown to the
  /// layout and sort after the known ones in their declared order.
  final List<String> order;

  /// Keys explicitly hidden. A key absent from both [order] and [hidden] is a
  /// new column — shown by default.
  final Set<String> hidden;

  /// Explicit pixel widths set by resizing, keyed by column key. A key absent
  /// keeps its declared sizing. Passed straight to [FwTable.columnWidths].
  final Map<String, double> widths;

  const ColumnLayout({
    this.order = const [],
    this.hidden = const {},
    this.widths = const {},
  });

  /// The default layout for [columns]: declared order, nothing hidden.
  static ColumnLayout of<T>(List<FwTableColumn<T>> columns) =>
      ColumnLayout(order: [for (var column in columns) column.key]);

  bool isVisible(String key) => !hidden.contains(key);

  /// [columns] resolved against this layout: reordered to [order] (unknown keys
  /// appended in declared order), then filtered to the visible ones.
  List<FwTableColumn<T>> apply<T>(List<FwTableColumn<T>> columns) {
    var byKey = {for (var column in columns) column.key: column};
    var seen = <String>{};
    var result = <FwTableColumn<T>>[];
    for (var key in order) {
      var column = byKey[key];
      if (column != null && seen.add(key)) result.add(column);
    }
    for (var column in columns) {
      if (seen.add(column.key)) result.add(column);
    }
    return [
      for (var column in result)
        if (isVisible(column.key)) column,
    ];
  }

  /// The full key list in display order — known keys first, then any new
  /// [columns] not yet in [order]. The canonical order a chooser would edit.
  List<String> resolvedOrder<T>(List<FwTableColumn<T>> columns) {
    var keys = [for (var column in columns) column.key];
    var known = order.where(keys.contains);
    var fresh = keys.where((key) => !order.contains(key));
    return [...known, ...fresh];
  }

  ColumnLayout withVisible(String key, bool visible) => ColumnLayout(
    order: order,
    hidden: visible
        ? (hidden.where((k) => k != key).toSet())
        : {...hidden, key},
    widths: widths,
  );

  ColumnLayout withOrder(List<String> next) =>
      ColumnLayout(order: next, hidden: hidden, widths: widths);

  ColumnLayout withWidth(String key, double width) => ColumnLayout(
    order: order,
    hidden: hidden,
    widths: {...widths, key: width},
  );

  Map<String, dynamic> toJson() => {
    'order': order,
    if (hidden.isNotEmpty) 'hidden': hidden.toList(),
    if (widths.isNotEmpty) 'widths': widths,
  };

  factory ColumnLayout.fromJson(Map<String, dynamic> json) => ColumnLayout(
    order: [
      for (var key in (json['order'] as List? ?? const [])) key as String,
    ],
    hidden: {
      for (var key in (json['hidden'] as List? ?? const [])) key as String,
    },
    widths: {
      for (var entry in (json['widths'] as Map? ?? const {}).entries)
        entry.key as String: (entry.value as num).toDouble(),
    },
  );

  @override
  bool operator ==(Object other) =>
      other is ColumnLayout &&
      _eq.equals(order, other.order) &&
      _eq.equals(hidden, other.hidden) &&
      _eq.equals(widths, other.widths);

  @override
  int get hashCode =>
      Object.hash(_eq.hash(order), _eq.hash(hidden), _eq.hash(widths));
}
