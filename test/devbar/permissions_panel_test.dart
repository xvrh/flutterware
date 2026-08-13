import 'package:flutterware/channels.dart';
import 'package:flutterware/src/devbar/plugins/permissions.dart';
import 'package:test/test.dart';

/// A scripted app: no permission_handler anywhere, which is the point of the
/// adapter existing at all.
class _FakeApp {
  final permissions = const ['camera', 'location'];
  final asked = <String>[];
  var settingsOpened = 0;

  /// Mutable: `request` writes the granted status back into it, the way a real
  /// app's next `status` call would see the change.
  Map<String, AppPermissionStatus> statuses = {};

  /// Set to make [status] throw for one name — an adapter that does not
  /// handle a permission is a normal adapter.
  String? failFor;

  PermissionAdapter adapter({
    bool canRequest = false,
    bool canOpenSettings = false,
    bool settingsSucceeds = true,
  }) => PermissionAdapter(
    permissions: permissions,
    status: (name) async {
      if (name == failFor) throw StateError('no mapping for $name');
      return statuses[name] ?? AppPermissionStatus.undetermined;
    },
    request: canRequest
        ? (name) async {
            asked.add(name);
            return statuses[name] = AppPermissionStatus.granted;
          }
        : null,
    openSettings: canOpenSettings
        ? () async {
            settingsOpened++;
            return settingsSucceeds;
          }
        : null,
  );
}

void main() {
  late InspectorCore core;
  late Panels panels;
  late _FakeApp app;

  setUp(() {
    core = InspectorCore(identity: () => const {});
    panels = Panels(core);
    app = _FakeApp();
  });

  Panel mount(PermissionAdapter adapter) {
    var source = PermissionsPanelSource(adapter);
    addTearDown(source.dispose);
    var panel = panels.add(source.panelId, source.panelLabel);
    source.describePanel(panel);
    return panel;
  }

  group('descriptor', () {
    test('declares only what the adapter can do', () {
      var panel = mount(app.adapter());
      var descriptor = panel.descriptor;

      expect(descriptor.states.map((e) => e.id), ['status']);
      // Presence is the opt-in, the same rule DatabaseAdapter.execute follows:
      // no function, no action, invisible to every surface including an agent.
      expect(descriptor.actions, isEmpty);
    });

    test('offers request and openSettings when the app wired them', () {
      var panel = mount(app.adapter(canRequest: true, canOpenSettings: true));

      expect(panel.descriptor.actions.map((e) => e.id), [
        'request',
        'openSettings',
      ]);
    });

    test('request offers the permissions the app named', () {
      var panel = mount(app.adapter(canRequest: true));
      var request = panel.descriptor.actions.single;

      expect(request.parameters.single.options.map((e) => e.value), [
        'camera',
        'location',
      ]);
      // It provokes a real system dialog on a real device. That is a thing an
      // agent should be told to think twice about.
      expect(request.danger, isTrue);
    });
  });

  group('status', () {
    test('answers for every permission in one call', () async {
      app.statuses = {
        'camera': AppPermissionStatus.granted,
        'location': AppPermissionStatus.deniedForever,
      };
      var panel = mount(app.adapter());

      var reply = await panel.readState('status');

      expect(reply['permissions'], {
        'camera': 'granted',
        'location': 'deniedForever',
      });
    });

    test('uses the same words the host side uses', () {
      // The cockpit puts observed beside held without translating; a rename
      // here silently breaks that column rather than failing a build.
      expect(
        AppPermissionStatus.values.map((e) => e.wire),
        containsAll([
          'granted',
          'denied',
          'deniedForever',
          'undetermined',
          'unknown',
        ]),
      );
    });

    test('one permission failing does not cost the others', () async {
      app.failFor = 'location';
      app.statuses = {'camera': AppPermissionStatus.granted};
      var panel = mount(app.adapter());

      var reply = await panel.readState('status');

      expect(reply['permissions'], {
        'camera': 'granted',
        // Reported as unknown rather than dropped: a missing row would read as
        // "no column", which is the ambiguity this whole design refuses.
        'location': 'unknown',
      });
    });
  });

  group('request', () {
    test('asks the app and answers with the status after', () async {
      var panel = mount(app.adapter(canRequest: true));

      var reply = await panel.run('request', {'permission': 'camera'});

      expect(app.asked, ['camera']);
      expect(reply, {'permission': 'camera', 'status': 'granted'});
    });

    test('refuses without a permission rather than guessing one', () async {
      var panel = mount(app.adapter(canRequest: true));

      var reply = await panel.run('request', const {});

      expect(app.asked, isEmpty);
      expect('${(reply! as Map)['error']}', contains('Which permission'));
    });
  });

  group('openSettings', () {
    test('says when the platform refused', () async {
      var panel = mount(
        app.adapter(canOpenSettings: true, settingsSucceeds: false),
      );

      var reply = (await panel.run('openSettings', const {}))! as Map;

      expect(app.settingsOpened, 1);
      expect(reply['opened'], isFalse);
      expect(reply['note'], contains('refused'));
    });
  });
}
