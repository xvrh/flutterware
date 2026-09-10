import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/demo/recording.dart';
import 'package:flutterware_app/src/launcher_icon/screen.dart';
import 'package:flutterware_app/src/plugins/native/icon_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

import 'app_theme.dart';

/// The **whole** launcher-icon panel, over the recording `tool/demo/record.dart`
/// wrote from `examples/example` — a real project's icons, every role and
/// every flavor, read from the recording rather than from a scan of the disk.
///
/// The entries in `launcher_icon.dart` show the pieces: a plate, a stage, the
/// chips. This is the panel a user sees, which until the recording existed
/// could only be looked at by running the studio on a checkout. The core
/// underneath is the live one — same cache, same report — handed a reader that
/// answers from the recording, which is the whole of the trick.
@Preview(
  name: 'Panel · recorded',
  group: 'Launcher icon',
  wrapper: wrapInAppTheme,
)
Widget recordedPanel() => const _RecordedPanel();

@Preview(
  name: 'Panel · recorded · dark',
  group: 'Launcher icon',
  wrapper: wrapInDarkTheme,
)
Widget recordedPanelDark() => const _RecordedPanel();

/// A flavor that overrides some roles and inherits the rest, which is the
/// state the panel has the most to say about.
@Preview(
  name: 'Panel · recorded · kiosk flavor',
  group: 'Launcher icon',
  wrapper: wrapInAppTheme,
)
Widget recordedPanelKiosk() => const _RecordedPanel(flavor: 'kiosk');

class _RecordedPanel extends StatefulWidget {
  const _RecordedPanel({this.flavor});

  final String? flavor;

  @override
  State<_RecordedPanel> createState() => _RecordedPanelState();
}

class _RecordedPanelState extends State<_RecordedPanel> {
  // The previews guest runs with the package as its working directory, which
  // is what makes the file end reachable from a demo.
  static final _recording = FileScenarioArtifacts(
    p.join(Directory.current.path, 'demo', 'fixture'),
  );

  late final LauncherIconCore _core = _build();

  LauncherIconCore _build() {
    var worktree = Worktree(path: '/recording');
    var core = LauncherIconCore(
      PluginHost(
        id: launcherIconPluginId,
        label: 'Launcher icon',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: const [Pkg('.')],
          discovered: const ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/recording/flutter'),
        ),
        config: const {
          'packages': [
            {'path': '.'},
          ],
        },
      ),
      scan: recordedIconScanner(_recording),
    );
    core.track('.', flavor: widget.flavor);
    return core;
  }

  @override
  void dispose() {
    _core.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _core.changes.stream,
    builder: (context, _) => LauncherIconScreen(
      _core,
      package: '.',
      flavor: widget.flavor,
      image: recordedIconImage(_recording),
    ),
  );
}
