import 'package:flutter/material.dart';

import '../project.dart';
import '../ui/colors.dart';
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inMenuToolbarBackground,
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
      child: ValueListenableBuilder<bool>(
        valueListenable: daemon.isReloading,
        builder: (context, isReloading, child) {
          return Row(
            children: [
              _ToolbarButton(
                onPressed: isReloading ? null : () {
                  daemon.reload(fullRestart: false);
                },
                icon: Icons.bolt,
                iconColor: Colors.orange,
                tooltip: 'Hot reload',
              ),
              _ToolbarButton(
                onPressed:isReloading ? null : () {
                  daemon.reload(fullRestart: true);
                },
                icon: Icons.restart_alt,
                iconColor: Colors.green,
                tooltip: 'Hot restart',
              ),
              ////TODO(xha): open a dropdown with option to watch lib/** & test_app/**
              _ToolbarButton(
                onPressed: () {
                  daemon.stop();
                },
                icon: Icons.stop,
                iconColor: Colors.red,
                tooltip: 'Stop test runner',
              ),
            ],
          );
        }
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color iconColor;
  final String tooltip;

  const _ToolbarButton({
    required this.onPressed,
    required this.icon,
    required this.iconColor,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      splashRadius: Material.defaultSplashRadius / 2,
      onPressed: onPressed,
      constraints: BoxConstraints(),
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
      icon: Icon(
        icon,
        color: onPressed != null ? iconColor : Colors.black26,
        size: 20,
      ),
      tooltip: tooltip,
    );
  }
}

class _DaemonStoppedToolbar extends StatelessWidget {
  final Project project;

  const _DaemonStoppedToolbar(this.project);

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 10),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inMenuToolbarBackground,
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
      child: Text(
        'Launching test runner...',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black26,
          fontSize: 13,
        ),
      ),
    );
  }
}
