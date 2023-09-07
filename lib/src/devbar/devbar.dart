import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../utils/value_stream.dart';
import 'ui/panel.dart';
import 'service/ui.dart';
import 'ui/button.dart';
import 'ui/overlay_dialog.dart';
import 'ui/toasts_overlay.dart';
import 'feature_flag.dart';

class Devbar extends StatefulWidget {
  final Widget child;
  final List<DevbarPlugin Function(DevbarState state)> plugins;
  final List<FeatureFlagValue> flags;
  final bool overlayVisible;

  Devbar({
    super.key,
    required this.child,
    required this.plugins,
    List<FeatureFlagValue>? flags,
    bool? overlayVisible,
  })  : flags = flags ?? const [],
        overlayVisible = overlayVisible ?? true;

  @override
  DevbarState createState() => DevbarState();

  static DevbarState? of(BuildContext context) {
    return context.findAncestorStateOfType<DevbarState>();
  }
}

class DevbarState extends State<Devbar> {
  final _appKey = GlobalKey();
  late final UiService ui = UiService(this);
  final _plugins = <DevbarPlugin>[];

  static DevbarState of(BuildContext context) {
    return context.findAncestorStateOfType<DevbarState>()!;
  }

  @override
  void initState() {
    super.initState();

    for (var plugin in widget.plugins) {
      _plugins.add(plugin(this));
    }
  }

  T plugin<T extends DevbarPlugin>() {
    return _plugins.whereType<T>().first;
  }

  T? maybePlugin<T extends DevbarPlugin>() {
    return _plugins.whereType<T>().firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return FeatureFlagDevbar(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ValueStreamBuilder<OpenState?>(
                stream: ui.openState,
                builder: (context, openState) {
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: openState == null ? 0 : 1,
                    child: DevbarPanel(),
                  );
                },
              ),
            ),
            DevbarAppWrapper(
              child: KeyedSubtree(
                key: _appKey,
                child: widget.child,
              ),
            ),
            Positioned.fill(child: OverlayDialog()),
            Visibility(
              visible: widget.overlayVisible,
              child: DevbarButton(
                button: DevbarIcon(onTap: ui.open, icon: Icons.bug_report),
              ),
            ),
            ToastsOverlay(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ui.dispose();
    for (var plugin in _plugins) {
      plugin.dispose();
    }
    super.dispose();
  }
}

abstract class DevbarPlugin {
  void dispose();
}

extension DevbarContextExtension on BuildContext {
  DevbarState? get devbar => Devbar.of(this);
}
