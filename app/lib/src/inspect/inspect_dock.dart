import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// One tab of an [InspectDock]: a label, an optional badge, and a body built
/// only while the tab is the open one.
class InspectDockTab {
  const InspectDockTab({
    required this.id,
    required this.label,
    this.badge = 0,
    required this.body,
  });

  final String id;
  final String label;

  /// Zero draws nothing at all — a badge that is always there is a
  /// decoration.
  final int badge;

  final WidgetBuilder body;
}

/// The Chrome-shaped docked panel: a draggable grip, a tab strip, a
/// collapsible and resizable body. Extracted from the UI catalog's inspect
/// panel so the scenarios step page is the *same* surface — one look, one
/// muscle memory — while each host declares its own tabs; the catalog's
/// live-guest tabs (Controls, Problems, Console) stay the catalog's.
///
/// Controlled: [current] and [collapsed] belong to the host, because hosts
/// have reasons of their own to move them — arming the catalog's picker jumps
/// the panel to Elements. The interaction grammar lives here, though:
/// clicking the open tab collapses the panel, clicking any tab while
/// collapsed restores it.
class InspectDock extends StatefulWidget {
  const InspectDock({
    super.key,
    required this.tabs,
    required this.current,
    required this.collapsed,
    required this.available,
    required this.onChanged,
    this.leading,
    this.onRefresh,
  });

  final List<InspectDockTab> tabs;

  /// The open tab's [InspectDockTab.id].
  final String current;

  final bool collapsed;

  /// How tall the panel and whatever it is docked under are together.
  ///
  /// Passed in rather than measured here, and that is not fussiness: a
  /// `Column` lays a non-flex child out with an **unbounded** main axis, so a
  /// `LayoutBuilder` in this position reads `maxHeight: infinity` and any
  /// clamp against it is a clamp against nothing. The panel would resize past
  /// the bottom of the window and take the canvas with it.
  final double available;

  /// Every state move: a tab switch, a collapse, a restore.
  final void Function(String current, bool collapsed) onChanged;

  /// Before the tabs — the catalog's picker, the step page's. Not a tab
  /// because it is not one: it changes what the surface *above* does.
  final Widget? leading;

  /// Shown while expanded, when the host has something to re-read.
  final Future<void> Function()? onRefresh;

  @override
  State<InspectDock> createState() => _InspectDockState();
}

class _InspectDockState extends State<InspectDock> {
  /// Below this the panel is a scrollbar with ambitions.
  static const _minHeight = 140.0;

  /// What the surface above keeps no matter how far the panel is dragged up.
  /// Without it the panel can eat the thing it is inspecting.
  static const _canvasFloor = 160.0;

  static const _stripHeight = 34.0;

  double _height = 260;

  InspectDockTab get _current => widget.tabs.firstWhere(
    (tab) => tab.id == widget.current,
    orElse: () => widget.tabs.first,
  );

  @override
  Widget build(BuildContext context) {
    var ceiling = math.max(
      _minHeight,
      widget.available - _canvasFloor - _stripHeight,
    );
    // Its own (invisible) Material: the strip and the tree run on InkWell,
    // and a reusable dock should not gamble on the host having one.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Grip(
            enabled: !widget.collapsed,
            onDrag: (delta) => setState(() {
              // Up is negative and up is bigger.
              _height = (_height - delta).clamp(_minHeight, ceiling);
            }),
          ),
          _strip(context),
          // Clamped on the way out as well as on the drag: the window can be
          // made smaller after the panel was dragged tall, and nothing about
          // that resize goes through [_Grip].
          if (!widget.collapsed)
            SizedBox(
              height: math.min(_height, ceiling),
              child: Builder(builder: _current.body),
            ),
        ],
      ),
    );
  }

  Widget _strip(BuildContext context) {
    return InspectTabStrip(
      tabs: widget.tabs,
      // Null while collapsed: no tab is open, so none of them is lit.
      current: widget.collapsed ? null : widget.current,
      onSelect: (id) {
        // Clicking the tab you are on is how you get the panel back without
        // hunting for the chevron.
        if (id == widget.current && !widget.collapsed) {
          widget.onChanged(widget.current, true);
        } else {
          widget.onChanged(id, false);
        }
      },
      leading: widget.leading,
      trailing: [
        if (!widget.collapsed)
          if (widget.onRefresh case var refresh?)
            InspectStripButton(
              icon: Icons.refresh,
              tooltip: 'Read it all again',
              onTap: () => refresh(),
            ),
        InspectStripButton(
          icon: widget.collapsed ? Icons.expand_less : Icons.expand_more,
          tooltip: widget.collapsed ? 'Show the panel' : 'Hide the panel',
          onTap: () => widget.onChanged(widget.current, !widget.collapsed),
        ),
      ],
    );
  }
}

/// The tab strip on its own, without the dock around it.
///
/// Split out because a host can want these tabs at the *top* of a pane rather
/// than docked under a canvas — the run cockpit's run page is the first, and
/// its own hand-rolled row of `TextButton`s was the reason: three surfaces
/// showing a widget tree, two of them matching and one of them not.
///
/// [InspectDock] is now a composition of this, a drag grip and a sized body,
/// so what ui_catalog and scenarios draw is unchanged.
class InspectTabStrip extends StatelessWidget {
  const InspectTabStrip({
    super.key,
    required this.tabs,
    required this.current,
    required this.onSelect,
    this.leading,
    this.trailing = const [],
  });

  /// Only [InspectDockTab.id], [InspectDockTab.label] and
  /// [InspectDockTab.badge] are read here — a strip does not build bodies.
  final List<InspectDockTab> tabs;

  /// The open tab's id, or null for none — which is what the dock passes while
  /// it is collapsed.
  final String? current;

  final void Function(String id) onSelect;

  /// Before the tabs. Not a tab because it is not one: it changes what the
  /// surface around the strip does.
  final Widget? leading;

  /// After them, hard right — a refresh, a collapse chevron.
  final List<Widget> trailing;

  static const height = _InspectDockState._stripHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: context.colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
      child: Row(
        children: [
          ?leading,
          // Scrolls rather than overflows: the panel is as narrow as its
          // window allows, and a tab strip that paints Flutter's stripes over
          // itself in an inspector is a poor advertisement.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var tab in tabs)
                    _Tab(
                      label: tab.label,
                      selected: tab.id == current,
                      badge: tab.badge,
                      onTap: () => onSelect(tab.id),
                    ),
                ],
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// The draggable top edge.
class _Grip extends StatelessWidget {
  const _Grip({required this.enabled, required this.onDrag});

  final bool enabled;
  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    var line = Container(height: 1, color: context.colors.line);
    if (!enabled) return line;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (event) => onDrag(event.delta.dy),
        // The line is one pixel; the thing you have to hit is not.
        child: SizedBox(height: 7, child: Center(child: line)),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Zero draws nothing at all.
  final int badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? context.colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.type.caption.copyWith(
                color: selected ? context.colors.ink : context.colors.mut,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: FwSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FwSpacing.xs,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: context.colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: context.type.micro.copyWith(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small icon button in the dock's strip — public so hosts can build their
/// own [InspectDock.leading] in the same voice.
class InspectStripButton extends StatelessWidget {
  const InspectStripButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Armed, for a picker — which is a mode rather than a press, and a mode
  /// that does not look like one is a mode you forget you are in.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: FwSpacing.xxs),
          padding: const EdgeInsets.all(FwSpacing.sm),
          decoration: active
              ? BoxDecoration(
                  color: context.colors.accentSoft,
                  borderRadius: BorderRadius.circular(
                    context.radii.radiusSmall,
                  ),
                )
              : null,
          child: Icon(
            icon,
            size: 16,
            color: active ? context.colors.accent : context.colors.mut,
          ),
        ),
      ),
    );
  }
}
