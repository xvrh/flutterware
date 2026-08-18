import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../server/vm_transport.dart';
import '../utils/value_stream.dart';
import 'bridge.dart';
import 'feature_flag.dart';
import 'ui/button.dart';
import 'ui/overlay_dialog.dart';
import 'ui/panel.dart';
import 'ui/service.dart';
import 'ui/toasts_overlay.dart';

final _devbarStates = <DevbarState>[];

/// Wrapper around the application to add a hidden developer UI beneath it.
///
/// **Two jobs, which used to be one.** It is the *plugin host* — where plugins
/// are constructed, and therefore where they are declared — and it is the
/// *in-app overlay*. Under flutterware the overlay is not wanted: the cockpit
/// is the surface, and the plugins report to it over the channels
/// ([DevbarBridge]). See [headless].
class Devbar extends StatefulWidget {
  final Widget child;
  final List<DevbarPluginFactory> plugins;
  final List<FeatureFlagValue> flags;
  final bool overlayVisible;

  /// Hold the plugins and draw nothing at all.
  ///
  /// **Not the same as `overlayVisible: false`,** which only hides the button.
  /// That leaves the overlay's `Stack`, its dialog and toast layers and
  /// [DevbarAppWrapper]'s `Container`/`FittedBox` in the tree.
  /// With the panel shut and no plugin contributing a button those paint the
  /// same pixels — measured, in `test/devbar/headless_test.dart` — but a
  /// screenshot is not the only thing the cockpit reads: every `act` reply
  /// carries the **widget tree**, and `Target` resolution walks it. An extra
  /// `Stack`, a `FittedBox` and an overlay `Navigator` between the root and
  /// the app change what `nth` counts and what a tap can land on. The moment
  /// the panel opens or a plugin adds a button, the pixels go too.
  ///
  /// So under a run the chrome must not *exist*, rather than be invisible.
  ///
  /// Defaults to whether flutterware is watching
  /// ([GuestChannels.installed]). Pass it explicitly to keep the overlay in a
  /// flutterware-launched app, or to drop it in one that is not.
  final bool? headless;

  Devbar({
    super.key,
    required this.child,
    required this.plugins,
    List<FeatureFlagValue>? flags,
    bool? overlayVisible,
    this.headless,
  }) : flags = flags ?? const [],
       overlayVisible = overlayVisible ?? true;

  bool get isHeadless => headless ?? GuestChannels.installed;

  @override
  DevbarState createState() => DevbarState();

  static DevbarState? of(BuildContext context) {
    return context.findAncestorStateOfType<DevbarState>();
  }

  static List<DevbarState> get instances => _devbarStates;
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

    _devbarStates.add(this);

    WidgetsBinding.instance.deferFirstFrame();
    _loadPluginsFuture = _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    try {
      for (var plugin in widget.plugins) {
        _plugins.add(await plugin(this));
      }
    } on Object catch (e, stack) {
      // A throwing factory must not take the app with it. Without this catch
      // the first frame stays deferred forever — a blank window with the
      // error buried in a future nobody awaits. Report it where every other
      // build-time error goes and run with the plugins that did load.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: stack,
          library: 'flutterware devbar',
          context: ErrorDescription('while loading devbar plugins'),
        ),
      );
    } finally {
      // Unconditionally, and before the bridge: nothing that can throw may
      // stand between a deferred first frame and this call.
      WidgetsBinding.instance.allowFirstFrame();
      // After construction, never in `initState`: a plugin still being built
      // has nothing to describe, and the bridge reads each one's declaration.
      DevbarBridge.mount(this, _plugins);
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
    return FutureBuilder<void>(
      future: _loadPluginsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Never painted: the first frame stays deferred until loading ends.
          return Container(color: Colors.red);
        }

        // The plugins are loaded and reporting; the overlay is what is
        // skipped. [FeatureFlagDevbar] stays either way — it is what turns a
        // declared flag into a variable, and a flag that only worked when
        // somebody could see the panel would be a trap.
        //
        // **So does the [Directionality], for a sharper reason.** It is here
        // for the overlay's own [Stack] — but the app builds under it too, so
        // a host app with a widget needing one *above* its `MaterialApp` (an
        // environment banner, a device frame, a watermark) has been inheriting
        // it. Dropped with the overlay, that app rendered nothing and said
        // `No Directionality widget found` — and only ever when flutterware
        // launched it, because [Devbar.isHeadless] is `GuestChannels.installed`
        // and so a plain `flutter run` took the branch that supplied one. The
        // author sees a failure in the one path they cannot reproduce, in a
        // widget they wrote. Skipping the overlay may only skip the overlay.
        return FeatureFlagDevbar(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: widget.isHeadless
                ? widget.child
                : Stack(
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
                        child: KeyedSubtree(key: _appKey, child: widget.child),
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
    _devbarStates.remove(this);
    DevbarBridge.unmount(this);
    ui.dispose();
    for (var plugin in _plugins) {
      plugin.dispose();
    }
    super.dispose();
  }
}

typedef DevbarPluginFactory =
    FutureOr<DevbarPlugin> Function(DevbarState state);

abstract class DevbarPlugin {
  void dispose();
}

extension DevbarContextExtension on BuildContext {
  DevbarState? get devbar => Devbar.of(this);
}
