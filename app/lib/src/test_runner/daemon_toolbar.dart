import 'package:flutter/material.dart';

import '../project.dart';
import 'model/daemon.dart';
import 'model/service.dart';

class DaemonToolbar extends StatelessWidget {
  final Project project;

  const DaemonToolbar(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<DaemonState>(
            valueListenable: project.tests.state,
            builder: (context, state, child) {
              if (state is DaemonState$Connected) {
                return _DaemonConnectedToolbar(state.daemon);
              } else if (state is DaemonState$Stopped) {
                return _DaemonStoppedToolbar(project);
              } else {
                return _DaemonStartingToolbar();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _DaemonConnectedToolbar extends StatelessWidget {
  final Daemon daemon;

  const _DaemonConnectedToolbar(this.daemon);

  @override
  Widget build(BuildContext context) {
    //TODO(xha): disable buttons when isReloading is true
    return Row(
      children: [
        IconButton(
          splashRadius: Material.defaultSplashRadius / 2,
          onPressed: () {
            daemon.reload(fullRestart: false);
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.bolt,
            color: Colors.orange,
            size: 20,
          ),
          tooltip: 'Hot reload',
        ),
        IconButton(
          onPressed: () {
            daemon.reload(fullRestart: true);
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.restart_alt,
            size: 20,
            color: Colors.green,
          ),
          tooltip: 'Hot restart',
          splashRadius: Material.defaultSplashRadius / 2,
        ),
        ////TODO(xha): open a dropdown with option to watch lib/** & test_app/**
        //Text('Auto reload'),
        //Checkbox(value: true, onChanged: (v) {}),
        //OutlinedButton(onPressed: () {}, child: Text('Auto reload')),
        Expanded(
          child: const SizedBox(),
        ),
        IconButton(
          splashRadius: Material.defaultSplashRadius / 2,
          onPressed: () {
            daemon.stop();
          },
          constraints: BoxConstraints(),
          padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          icon: Icon(
            Icons.stop,
            color: Colors.red,
            size: 20,
          ),
          tooltip: 'Stop test runner',
        ),
      ],
    );
  }
}

class _DaemonStoppedToolbar extends StatelessWidget {
  final Project project;

  const _DaemonStoppedToolbar(this.project);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          project.tests.start();
        },
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 12),
          minimumSize: Size(0, 30),
        ),
        icon: Icon(
          Icons.play_arrow,
          size: 12,
        ),
        label: Text('Start test runner'),
      ),
    );
  }
}

class _DaemonStartingToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Launching test runner...',
      style: TextStyle(
        color: Colors.black26,
        fontSize: 13,
      ),
    );
  }
}
