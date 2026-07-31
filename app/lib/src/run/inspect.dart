import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';

// The node types the catalog already carries between processes. Reused rather
// than re-invented so that a tree read off a phone and a tree read out of a
// headless guest are the same shape to whatever consumes them.
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import 'connection.dart';

final _logger = Logger('run_inspect');

/// Reads a running app through the framework's own inspector.
///
/// **Nothing here needs code in the user's app.** `WidgetInspectorService` is
/// registered by `package:flutter` in debug mode, so this works against any
/// Flutter app the cockpit can reach a VM service for — including one that has
/// never depended on flutterware. That is the reason the guest runtime came off
/// slice 3's critical path; see
/// `docs/superpowers/specs/2026-07-31-sl3-inspect-surface-findings.md`.
///
/// It is also app-side rather than tool-side, which puts it on the surviving
/// half of the S-L1 split: an app whose `flutter run` has died keeps its tree
/// and its screenshots and loses only hot reload.
class RunInspector {
  RunInspector(this.connection);

  final RunConnection connection;

  VmService get _service => connection.service;

  /// Object group names are per-connection and refcounted by the inspector, so
  /// two overlapping reads must not share one — disposing the first would
  /// invalidate the ids the second is still holding.
  static var _groups = 0;

  /// The widget tree, as of the app's last build.
  ///
  /// Summary by default, and that default is not a nicety: the full tree
  /// measured 6.1 MB across 517 nodes at depth 224 for a one-screen demo, where
  /// the summary was 25 nodes and 25 KB. Summary means "the widgets the
  /// framework attributes to the user's code", which is what anyone reading a
  /// tree is asking about.
  Future<InspectTree> tree({bool summary = true}) =>
      _inGroup((group) async => _readTree(group, summary: summary));

  /// A PNG of the whole app, as it is on the screen right now.
  ///
  /// **`ext.flutter.inspector.screenshot`, not `_flutter.screenshot`.** The
  /// rasterizer screenshot fails under Impeller — measured on macOS and the iOS
  /// simulator alike, and `_flutter.screenshotSkp` says so in its error — which
  /// rules it out on every target, since macOS, iOS and Android are all
  /// Impeller. This one renders the render tree into an offscreen layer through
  /// `toImage`, which Impeller does support.
  ///
  /// Verified to be live rather than cached: flipping `debugPaint` from outside
  /// changes the next picture.
  ///
  /// Platform views — native maps, webviews, video — will not appear. They are
  /// composited by the OS, not by Flutter's layer tree, so nothing rendering
  /// that tree can photograph them.
  Future<Uint8List> screenshot({double maxPixelRatio = 2, int? maxSide}) =>
      _inGroup((group) async {
        var root = await _rootId(group);
        if (root == null) {
          throw StateError(
            'The app has no widget tree yet, so there is nothing to '
            'photograph. It may still be starting up.',
          );
        }
        // The RPC fits the render into this box, so the box decides how big the
        // picture comes back. Asking the root how big it actually is costs one
        // call and is the difference between a phone-shaped photograph and an
        // arbitrarily letterboxed one.
        var size =
            await _sizeOf(group, root) ?? const (width: 2000.0, height: 2000.0);
        var (:width, :height) = size;
        if (maxSide != null) {
          var longest = width > height ? width : height;
          if (longest > maxSide) {
            var scale = maxSide / longest;
            width *= scale;
            height *= scale;
          }
        }
        var response = await _service.callServiceExtension(
          'ext.flutter.inspector.screenshot',
          isolateId: connection.isolateId,
          args: {
            'id': root,
            'width': '$width',
            'height': '$height',
            'margin': '0',
            'maxPixelRatio': '$maxPixelRatio',
            'debugPaint': 'false',
          },
        );
        var encoded = response.json?['result'];
        if (encoded is! String) {
          throw StateError(
            'The app answered a screenshot request without a picture in it. '
            'It reported: ${response.json}',
          );
        }
        return base64Decode(encoded);
      });

  /// Runs [body] against a fresh inspector object group and always disposes it.
  ///
  /// A group that outlives its read pins every `Element` in it, and this runs
  /// against a live app rather than a stopped one.
  Future<T> _inGroup<T>(Future<T> Function(String group) body) async {
    var group = 'flutterware.run.${_groups++}';
    try {
      return await body(group);
    } finally {
      try {
        await _service.callServiceExtension(
          'ext.flutter.inspector.disposeGroup',
          isolateId: connection.isolateId,
          args: {'objectGroup': group},
        );
      } on Object catch (e) {
        // Best effort. An app that died mid-read cannot free anything, and
        // failing the read over its failure to tidy up would report the wrong
        // problem.
        _logger.fine('Could not dispose inspector group $group: $e');
      }
    }
  }

  Future<InspectTree> _readTree(String group, {required bool summary}) async {
    var response = await _service.callServiceExtension(
      'ext.flutter.inspector.getRootWidgetTree',
      isolateId: connection.isolateId,
      args: {
        'groupName': group,
        'isSummaryTree': '$summary',
        'withPreviews': 'true',
        if (!summary) 'fullDetails': 'true',
      },
    );
    var result = response.json?['result'];
    if (result is! Map) return InspectTree.empty;
    return InspectTree(
      entryId: null,
      root: convertNode(result.cast<String, Object?>(), ''),
    );
  }

  /// The inspector's own id for the root, alive only while [group] is.
  Future<String?> _rootId(String group) async {
    var response = await _service.callServiceExtension(
      'ext.flutter.inspector.getRootWidgetTree',
      isolateId: connection.isolateId,
      args: {
        'groupName': group,
        'isSummaryTree': 'true',
        'withPreviews': 'false',
      },
    );
    return switch (response.json?['result']) {
      Map result => result['valueId'] as String?,
      _ => null,
    };
  }

  /// How big [id]'s box is, in logical pixels.
  ///
  /// The one piece of geometry the VM service will part with. There is no
  /// *position* anywhere in the inspector surface — `parentData` reads `<none>`
  /// and `getDetailsSubtree` errors — which is why [InspectNode.layout] is left
  /// null on this path and why cropping and annotating need the guest runtime.
  Future<({double width, double height})?> _sizeOf(
    String group,
    String id,
  ) async {
    try {
      var response = await _service.callServiceExtension(
        'ext.flutter.inspector.getLayoutExplorerNode',
        isolateId: connection.isolateId,
        args: {'groupName': group, 'id': id, 'subtreeDepth': '1'},
      );
      var result = response.json?['result'];
      if (result is! Map) return null;
      // The root is a `RenderView` rather than a `RenderBox` and need not
      // report one, so the first child that does is the app's own bounds.
      return _size(result) ??
          switch (result['children']) {
            [Map first, ...] => _size(first),
            _ => null,
          };
    } on Object catch (e) {
      _logger.fine('Could not read a size for $id: $e');
      return null;
    }
  }

  static ({double width, double height})? _size(Map<Object?, Object?> node) {
    // Reported as strings, both of them.
    if (node['size'] case Map size) {
      var width = double.tryParse('${size['width']}');
      var height = double.tryParse('${size['height']}');
      if (width != null && height != null && width > 0 && height > 0) {
        return (width: width, height: height);
      }
    }
    return null;
  }

  /// The inspector's JSON as an [InspectNode].
  ///
  /// **The field rules here must stay in step with `GuestInspector._convert`**
  /// (`lib/src/inspect/guest_inspect.dart`), because an agent can be handed a
  /// tree from either and must not have to tell which. They are separate rather
  /// than shared because only one of them can answer the two questions that
  /// need a live `Element`: what a node's box is, and which render object it
  /// belongs to.
  ///
  /// The id is the child-index path, exactly as [InspectNode.id] specifies —
  /// derived from shape, never the inspector's own `valueId`, which is minted
  /// per object group and dies with it. What this path *can* offer that the
  /// guest could not is [InspectNode.source] on every node: the creation
  /// location is unreachable in-process, because `_HasCreationLocation` is
  /// private and Dart mangles private names per library, but the service
  /// extension hands it out. So a node here is identified twice over — by
  /// position, and by `main.dart:66:11`.
  @visibleForTesting
  static InspectNode convertNode(Map<String, Object?> json, String path) {
    var description = json['description'] as String?;
    var type = json['widgetRuntimeType'] as String? ?? description ?? '';
    var preview = json['textPreview'] as String?;
    return InspectNode(
      id: path,
      type: type,
      // Only when it says more than the type does — `Text("Save")` earns its
      // place, a `Padding` described as "Padding" is the type twice.
      description: preview != null
          ? '$type("$preview")'
          : description == type
          ? null
          : description,
      createdByLocalProject: json['createdByLocalProject'] as bool? ?? false,
      source: switch (json['creationLocation']) {
        Map location => InspectSource.fromJson(
          location.cast<String, Object?>(),
        ),
        _ => null,
      },
      children: [
        for (var (index, child)
            in (json['children'] as List? ?? const []).indexed)
          if (child is Map)
            convertNode(
              child.cast<String, Object?>(),
              path.isEmpty ? '$index' : '$path/$index',
            ),
      ],
    );
  }
}
