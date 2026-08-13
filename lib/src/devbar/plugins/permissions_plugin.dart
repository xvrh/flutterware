/// The devbar wrapper around [PermissionsPanelSource] — the recipe's entry
/// point. All the serving logic is in `permissions.dart`, pure and tested
/// against a fake adapter; this file exists only because [DevbarPlugin] lives
/// with the Flutter imports.
library;

import '../../channels/panels.dart';
import '../devbar.dart';
import '../panel_source.dart';
import 'permissions.dart';

class PermissionsPlugin implements DevbarPlugin, DevbarPanelSource {
  PermissionsPlugin._(this._source);

  static PermissionsPlugin Function(DevbarState) init({
    required PermissionAdapter permissions,
  }) =>
      (_) => PermissionsPlugin._(PermissionsPanelSource(permissions));

  final PermissionsPanelSource _source;

  @override
  String get panelId => _source.panelId;

  @override
  String get panelLabel => _source.panelLabel;

  @override
  void describePanel(Panel panel) => _source.describePanel(panel);

  @override
  void dispose() => _source.dispose();
}
