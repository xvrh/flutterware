import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/drive.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware/run_guest.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/drive_navigator.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-pty\nbranch refs/heads/fix/pty\n';

class _FakeCore extends PluginCore {
  _FakeCore(super.host);

  @override
  PluginReport get report => PluginReport(id: host.id, label: host.label);
}

class _Fake extends NativePlugin<_FakeCore> {
  _Fake(super.core);

  @override
  Widget buildPanel(BuildContext context) => const SizedBox();
}

class _StubLoader implements ManifestLoader {
  @override
  Future<PluginManifest?> load(String worktreePath) async =>
      PluginManifest.parse(
        '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}',
      );

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String worktreePath,
  ) async => (manifest: await load(worktreePath), error: null);

  @override
  String get dartExecutable => 'dart';

  @override
  Duration get timeout => Duration.zero;
}

ShellController _controller() => ShellController(
  appContext: AppContext(logger: LogClient.print()),
  flutterSdk: FlutterSdkPath('/tmp/flutter'),
  registry: PluginRegistry({'a.one': panelFor<_FakeCore>(_Fake.new)}),
  coreRegistry: PluginCoreRegistry({'a.one': _FakeCore.new}),
  manifestLoader: _StubLoader(),
  discovery: WorktreeDiscovery(
    runProcess: (_, _, {workingDirectory}) async =>
        ProcessResult(0, 0, _listing, ''),
  ),
);

void main() {
  tearDown(() => GuestDrive.navigator = null);

  test('a route is a go: the address moves, closed worktrees open', () async {
    var shell = _controller();
    await shell.start('/repo');
    registerDriveNavigator(shell);

    GuestDrive.navigator!('fw:///worktrees/~/a.one');
    expect(shell.address, Address(worktree: '~', plugin: 'a.one'));

    // The go semantics ride along whole: naming a closed worktree opens it.
    expect(shell.openWorktrees, hasLength(1));
    GuestDrive.navigator!('fw:///worktrees/repo-pty');
    expect(shell.address.worktree, 'repo-pty');
    expect(shell.openWorktrees, hasLength(2));
  });

  test('not the grammar: refused with the grammar and where we are', () async {
    var shell = _controller();
    await shell.start('/repo');
    registerDriveNavigator(shell);
    var before = shell.address;

    expect(
      () => GuestDrive.navigator!('run/steps'),
      throwsA(
        isA<TargetError>()
            .having((e) => e.failure, 'failure', TargetFailure.notFound)
            .having((e) => e.message, 'message', contains('fw:///worktrees/'))
            .having((e) => e.message, 'message', contains('$before')),
      ),
    );
    expect(shell.address, before);
  });

  testWidgets('the scope re-registers the handler on hot reload', (
    tester,
  ) async {
    var shell = _controller();
    await shell.start('/repo');
    await tester.pumpWidget(DriveNavigatorScope(shell: shell));
    expect(GuestDrive.navigator, isNotNull);

    // What a stale registration would look like: a reload replaced the code
    // and nothing re-ran main. Reassembly is the reload's widget-side hook.
    // Not awaited: reassembleApplication resolves at end-of-frame, which a
    // test binding only reaches by pumping.
    GuestDrive.navigator = null;
    unawaited(tester.binding.reassembleApplication());
    await tester.pump();
    expect(GuestDrive.navigator, isNotNull);

    await tester.pumpWidget(const SizedBox());
    expect(GuestDrive.navigator, isNull);
  });

  test('unknown worktree: refused with the names git reports', () async {
    var shell = _controller();
    await shell.start('/repo');
    registerDriveNavigator(shell);

    expect(
      () => GuestDrive.navigator!('fw:///worktrees/nope/a.one'),
      throwsA(
        isA<TargetError>()
            .having((e) => e.failure, 'failure', TargetFailure.notFound)
            .having((e) => e.message, 'message', contains('repo-pty')),
      ),
    );
  });
}
