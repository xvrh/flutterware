import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../utils/value_stream.dart';
import 'feature_flag.dart';
import 'ui/button.dart';
import 'ui/overlay_dialog.dart';
import 'ui/panel.dart';
import 'ui/service.dart';
import 'ui/toasts_overlay.dart';

/// Wrapper around the application to add a hidden developer UI beneath it.
class Devbar extends StatefulWidget {
  final Widget child;
  final List<FutureOr<DevbarPlugin> Function(DevbarState state)> plugins;
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
  late Future<void> _loadPluginsFuture;

  static DevbarState of(BuildContext context) {
    return context.findAncestorStateOfType<DevbarState>()!;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.deferFirstFrame();
    _loadPluginsFuture = _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    for (var plugin in widget.plugins) {
      _plugins.add(await plugin(this));
    }
    WidgetsBinding.instance.allowFirstFrame();
  }

  T plugin<T extends DevbarPlugin>() {
    return _plugins.whereType<T>().first;
  }

  T? maybePlugin<T extends DevbarPlugin>() {
    return _plugins.whereType<T>().firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadPluginsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Should never appears since we are deferring the first frame
          return Container(color: Colors.red);
        }

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
                  child: AddDevbarButton(
                    button: DevbarIcon(
                      onTap: ui.open,
                      icon: Icons.bug_report,
                    ),
                  ),
                ),
                ToastsOverlay(),
              ],
            ),
          ),
        );
      },
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
