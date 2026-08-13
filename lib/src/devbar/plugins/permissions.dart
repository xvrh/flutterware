/// What the **app itself** believes about its permissions — the *observed*
/// third of `docs/superpowers/specs/2026-08-12-run-permissions-design.md`.
///
/// flutterware never imports `permission_handler` or any other permissions
/// package: the seam is [PermissionAdapter], two function types and a list of
/// names, and the recipe the app pastes is a dozen lines. Same rule as
/// [DatabaseAdapter], for the same reason — a tool that drags a plugin into
/// every project that installs it is a tool people uninstall.
///
/// **Why this third exists at all.** The other two are read from outside: what
/// the app *declares* comes from its manifests, what the OS *holds* comes from
/// `dumpsys` or a TCC database. Neither can see what the app thinks, and an app
/// that cached a status across a change is a real bug that nothing else can
/// show. It is also the only reading available at all on a physical iPhone and
/// on macOS, where the host has no readable store (S-P3, S-P4).
library;

import 'dart:async';

import '../../channels/panels.dart';
import '../../plugins/action.dart';
import '../panel_source.dart';

/// What an app can believe about one permission.
///
/// Deliberately the same five words the host side uses, so the cockpit can
/// put observed beside held without translating and without a table that has
/// to be kept in step. Mapping a package's own vocabulary onto these is the
/// adapter's job — that is what makes it an adapter.
enum AppPermissionStatus {
  granted,
  denied,

  /// Denied and the platform will not ask again. `permission_handler` spells
  /// this `permanentlyDenied`.
  deniedForever,

  /// Never asked. The app will prompt.
  undetermined,

  /// The app cannot say — no mapping, or a platform where the question does
  /// not apply. **Not** the same as [undetermined], which is an answer.
  unknown;

  /// The wire name, which is also the host's `HeldState` name.
  String get wire => name;
}

/// Answers what the app currently believes about [permission].
typedef PermissionStatusReader =
    Future<AppPermissionStatus> Function(String permission);

/// Provokes the real system dialog and answers with what came back.
///
/// This is half of the only honest end-to-end test there is: put the app in
/// `first-run`, call this, and let the native layer tap the button the OS
/// draws. Neither half proves much alone.
typedef PermissionRequester =
    Future<AppPermissionStatus> Function(String permission);

/// One app's own view of its permissions.
///
/// ```dart
/// PermissionAdapter(
///   permissions: ['camera', 'location', 'notifications'],
///   status: (name) async => _map(await _permissionFor(name).status),
///   request: (name) async => _map(await _permissionFor(name).request()),
///   openSettings: openAppSettings,
/// )
/// ```
class PermissionAdapter {
  PermissionAdapter({
    required this.permissions,
    required this.status,
    this.request,
    this.openSettings,
  });

  /// The capability ids this app can answer for — `camera`, `location`,
  /// `notifications`.
  ///
  /// **Use the ids the cockpit's `permissions` action reports**, because that
  /// is what joins this column to the other two. A name nothing else knows
  /// still shows up; it just sits in a row of its own.
  final List<String> permissions;

  final PermissionStatusReader status;

  /// **Presence is the opt-in**, exactly as `DatabaseAdapter.execute` is for
  /// writes. No function, no `request` action, on any surface.
  final PermissionRequester? request;

  /// Opens the OS settings page for this app. `permission_handler` calls it
  /// `openAppSettings`.
  final Future<bool> Function()? openSettings;
}

/// Serves [PermissionAdapter] onto a panel. Pure Dart; the devbar wrapper is
/// in `permissions_plugin.dart`.
class PermissionsPanelSource implements DevbarPanelSource {
  PermissionsPanelSource(this.adapter);

  final PermissionAdapter adapter;

  @override
  String get panelId => 'permissions';

  @override
  String get panelLabel => 'Permissions';

  @override
  void describePanel(Panel panel) {
    panel.state(
      'status',
      'Status',
      description:
          'What the app itself believes about each permission it was told '
          'about — granted, denied, deniedForever, undetermined or unknown. '
          'Read from inside the process, so it is the only reading available '
          'on a physical iPhone or on macOS, and the only one that can '
          'disagree with what the OS holds. That disagreement is the point: '
          'an app that cached a status across a change looks perfectly '
          'healthy from outside.',
      read: _status,
    );

    if (adapter.request != null) {
      panel.action(
        PluginAction(
          'request',
          'Request',
          danger: true,
          description:
              'Asks the OS for one permission, from inside the app — the real '
              'dialog, on the real device. Answers with what the user (or '
              'whatever answered the dialog) chose. Pair it with the native '
              'layer to answer the prompt without a person: put the app in '
              'first-run, call this, then tap the button with '
              '`act {layer: native}`.',
          parameters: [
            ActionParameter(
              'permission',
              'Permission',
              kind: ActionParameterKind.choice,
              description: 'Which one to ask for',
              options: [
                for (var permission in adapter.permissions)
                  ActionOption(permission),
              ],
            ),
          ],
        ),
        _request,
      );
    }

    if (adapter.openSettings != null) {
      panel.action(
        const PluginAction(
          'openSettings',
          'Open settings',
          description:
              "Opens this app's page in the OS settings — the only route back "
              'from denied-forever, and the one a person has to walk on a '
              'physical device.',
        ),
        _openSettings,
      );
    }
  }

  /// Every permission at once.
  ///
  /// One call rather than one per permission because this is a *column*: the
  /// cockpit wants the whole set beside the other two, and N round trips over
  /// a phone's channel to fill one column is N-1 too many.
  Future<Map<String, Object?>> _status() async {
    var statuses = <String, Object?>{};
    for (var permission in adapter.permissions) {
      // One failing permission must not cost the others. An adapter that
      // throws for a name it does not handle is a normal adapter, and the
      // honest report is `unknown` for that row rather than no column at all.
      try {
        statuses[permission] = (await adapter.status(permission)).wire;
      } on Object {
        statuses[permission] = AppPermissionStatus.unknown.wire;
      }
    }
    return {'permissions': statuses};
  }

  Future<Object?> _request(Map<String, Object?> arguments) async {
    var permission = '${arguments['permission'] ?? ''}';
    if (permission.isEmpty) {
      return {'error': 'Which permission? One of ${adapter.permissions}.'};
    }
    var status = await adapter.request!(permission);
    // The status after, read from the same place the column reads — never the
    // request echoed back.
    return {'permission': permission, 'status': status.wire};
  }

  Future<Object?> _openSettings(Map<String, Object?> arguments) async {
    var opened = await adapter.openSettings!();
    return {
      'opened': opened,
      if (!opened)
        'note': 'The platform refused to open its settings for this app.',
    };
  }

  void dispose() {}
}
