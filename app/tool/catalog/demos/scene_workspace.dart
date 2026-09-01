import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/measure.dart';
import 'package:flutterware_app/src/scene/playback.dart';
import 'package:flutterware_app/src/scene/ui/canvas.dart';
import 'package:flutterware_app/src/scene/ui/inspector.dart';
import 'package:flutterware_app/src/scene/ui/shortcuts.dart';
import 'package:flutterware_app/src/scene/ui/timeline.dart';
import 'package:flutterware_app/src/scene/ui/transport.dart';
import 'package:flutterware_app/src/scene/ui/tree_panel.dart';
import 'package:flutterware_app/src/ui/design/design.dart';
import 'package:flutterware_app/src/ui/tappable.dart';

import 'command_palette.dart' show wrapInAppTheme;

/// The scene workspace, three ways — the open question from the graduation
/// plan (*"whether the pair is one surface with a docked timeline, two modes
/// over one document, or a timeline panel you open"*), built rather than
/// argued. Same panels, same stage-set editor, only the composition differs.
///
/// The renderer here is `SceneView` over the coffee banner fixture with stub
/// externals, so the canvas has real measured rects without a guest: what a
/// demo needs is the geometry, not the app's theme.

@Preview(
  name: 'Docked timeline',
  group: 'Scene workspace',
  wrapper: wrapInAppTheme,
)
Widget docked() => const _Workspace(_Arrangement.docked);

@Preview(
  name: 'Design / Animate modes — Design',
  group: 'Scene workspace',
  wrapper: wrapInAppTheme,
)
Widget modes() => const _Workspace(_Arrangement.modes);

@Preview(
  name: 'Design / Animate modes — Animate',
  group: 'Scene workspace',
  wrapper: wrapInAppTheme,
)
Widget modesAnimate() => const _Workspace(_Arrangement.modes, animate: true);

@Preview(
  name: 'Timeline drawer',
  group: 'Scene workspace',
  wrapper: wrapInAppTheme,
)
Widget drawer() => const _Workspace(_Arrangement.drawer);

enum _Arrangement { docked, modes, drawer }

class _Workspace extends StatefulWidget {
  const _Workspace(this.arrangement, {this.animate = false});

  final _Arrangement arrangement;

  /// Modes: start in Animate.
  final bool animate;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace>
    with SingleTickerProviderStateMixin {
  late final SceneDocument _doc = coffeeBannerDraft();
  late final SceneEditor _editor = SceneEditor(
    _doc,
    motions: {'BannerIntro': coffeeIntroDraft()},
  );
  late final ScenePlayback _playback = ScenePlayback(
    _editor,
    'BannerIntro',
    vsync: this,
  );

  /// Modes: which one; drawer: whether the timeline is out.
  late var _animate = widget.animate;
  var _drawerOpen = true;

  @override
  void initState() {
    super.initState();
    _editor.select(_doc.nodeNamed('headline'));
    _playback.seek(const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  Widget _content() => SceneView(
    _doc,
    externals: _externals,
    onMeasured: (rects) => applyMeasuredRects(_doc, rects),
  );

  @override
  Widget build(BuildContext context) => switch (widget.arrangement) {
    _Arrangement.docked => _docked(context),
    _Arrangement.modes => _modes(context),
    _Arrangement.drawer => _drawer(context),
  };

  Widget _rule(BuildContext context, {bool vertical = true}) => Container(
    width: vertical ? 1 : null,
    height: vertical ? null : 1,
    color: context.colors.line,
  );

  /// One surface: the timeline is always under the canvas, transport in its
  /// gutter, and the tree stays — the node you pick in either is the same.
  Widget _docked(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: EditorShortcuts(
          _editor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 230, child: SceneTreePanel(_editor)),
              _rule(context),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SceneCanvas(_editor, content: _content()),
                    ),
                    _rule(context, vertical: false),
                    Expanded(flex: 2, child: SceneTimeline(_editor, _playback)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      _rule(context),
      SizedBox(width: 290, child: SceneInspector(_editor)),
    ],
  );

  /// Two modes over one document. Design is tree · canvas · inspector;
  /// Animate trades the tree for a full-width timeline under the canvas, the
  /// transport on the canvas bar, and the inspector stays for the key.
  Widget _modes(BuildContext context) {
    var toggle = _ModeToggle(
      animate: _animate,
      onChanged: (v) => setState(() => _animate = v),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: EditorShortcuts(
            _editor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_animate) ...[
                  SizedBox(width: 230, child: SceneTreePanel(_editor)),
                  _rule(context),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: _animate ? 3 : 1,
                        child: SceneCanvas(
                          _editor,
                          content: _content(),
                          trailing: [
                            if (_animate) SceneTransport(_playback),
                            toggle,
                          ],
                        ),
                      ),
                      if (_animate) ...[
                        _rule(context, vertical: false),
                        Expanded(
                          flex: 2,
                          child: SceneTimeline(
                            _editor,
                            _playback,
                            transport: false,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _rule(context),
        SizedBox(width: 290, child: SceneInspector(_editor)),
      ],
    );
  }

  /// The design layout with a transport bar along the bottom; the timeline
  /// is a drawer that bar opens, and it opens over the canvas's height.
  Widget _drawer(BuildContext context) {
    var colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: EditorShortcuts(
            _editor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 230, child: SceneTreePanel(_editor)),
                _rule(context),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SceneCanvas(_editor, content: _content()),
                      ),
                      _rule(context, vertical: false),
                      Container(
                        height: 32,
                        color: colors.panel,
                        padding: const EdgeInsets.symmetric(
                          horizontal: FwSpacing.md,
                        ),
                        child: Row(
                          spacing: FwSpacing.md,
                          children: [
                            SceneTransport(_playback),
                            const Spacer(),
                            Tappable(
                              onTap: () =>
                                  setState(() => _drawerOpen = !_drawerOpen),
                              borderRadius: BorderRadius.circular(
                                context.radii.radiusSmall,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FwSpacing.sm,
                                  vertical: FwSpacing.xxs,
                                ),
                                child: Row(
                                  spacing: FwSpacing.xs,
                                  children: [
                                    Icon(
                                      _drawerOpen
                                          ? Icons.keyboard_arrow_down
                                          : Icons.keyboard_arrow_up,
                                      size: FwIconSize.sm,
                                      color: colors.mut,
                                    ),
                                    Text(
                                      'Timeline',
                                      style: context.type.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_drawerOpen) ...[
                        _rule(context, vertical: false),
                        SizedBox(
                          height: 220,
                          child: SceneTimeline(
                            _editor,
                            _playback,
                            transport: false,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _rule(context),
        SizedBox(width: 290, child: SceneInspector(_editor)),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.animate, required this.onChanged});

  final bool animate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    Widget half(String label, bool value) => Tappable(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.xxs,
        ),
        color: animate == value ? colors.accentSoft : null,
        child: Text(
          label,
          style: context.type.caption.copyWith(
            color: animate == value ? colors.accentDark : colors.mut,
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.line),
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [half('Design', false), half('Animate', true)],
        ),
      ),
    );
  }
}

/// Stand-ins for the app's widgets, so the fixture lays out at the sizes
/// the real ones take.
final _externals = <String, SceneExternalBuilder>{
  'DrinkBadge': (context, args) {
    var size = (args['size'] as num?)?.toDouble() ?? 56;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF6B4226),
        shape: BoxShape.circle,
      ),
      child: Text('☕', style: TextStyle(fontSize: size * 0.45)),
    );
  },
  'Spinner': (context, args) {
    var size = (args['size'] as num?)?.toDouble() ?? 36;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD8C9BD), width: 3),
      ),
    );
  },
  'OrderButton': (context, args) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFE8632B),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Text(
      '${args['label'] ?? 'Order now'}',
      style: const TextStyle(color: Colors.white, fontSize: 15),
    ),
  ),
};
