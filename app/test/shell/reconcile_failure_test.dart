import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/config_load.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

class _Core extends PluginCore {
  _Core(super.host);
  @override
  PluginReport get report => PluginReport(id: host.id, label: host.label);
}

class _Fake extends NativePlugin<PluginCore> {
  _Fake(super.core);
  @override
  Widget buildPanel(BuildContext c) => const SizedBox();
}

class _Loader implements ManifestLoader {
  String m = '{"version":1,"plugins":[{"id":"a.one","label":"One"}]}';
  @override
  Future<PluginManifest?> load(String p) async => PluginManifest.parse(m);
  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(String p) async =>
      (manifest: await load(p), error: null);
  @override
  String get dartExecutable => 'dart';
}

void main() {
  test(
    'a core that throws while reconciling is reported, not thrown',
    () async {
      var loader = _Loader();
      var shell = ShellController(
        appContext: AppContext(logger: LogClient.print()),
        flutterSdk: FlutterSdkPath('/tmp/flutter'),
        registry: PluginRegistry({'a.one': _Fake.new, 'a.two': _Fake.new}),
        coreRegistry: PluginCoreRegistry({
          'a.one': _Core.new,
          'a.two': (h) => throw StateError('this core cannot be built'),
        }),
        manifestLoader: loader,
        discovery: WorktreeDiscovery(
          runProcess: (_, _, {workingDirectory}) async => ProcessResult(
            0,
            0,
            'worktree /repo\nbranch refs/heads/main\n',
            '',
          ),
        ),
      );
      await shell.start('/repo');
      var w = shell.selected!;
      expect(shell.sessionFor(w)!.plugins, hasLength(1));

      loader.m =
          '{"version":1,"plugins":[{"id":"a.one","label":"One"},'
          '{"id":"a.two","label":"Two"}]}';
      await shell.reloadConfig();

      // Same answer as a config that would not compile: nothing torn down, and
      // the reason on screen. It used to escape as an unhandled async error and
      // leave the worktree looking frozen.
      expect(shell.errorFor(w), isNotNull);
      expect(shell.errorFor(w)!.message, contains('cannot be built'));
      expect(shell.lastLoad(w)!.outcome, ConfigLoadOutcome.failed);
      expect(shell.sessionFor(w)!.plugins.map((pl) => pl.id), ['a.one']);
    },
  );
}
