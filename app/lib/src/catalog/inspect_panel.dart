import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog_guest.dart';

import '../address/address_scope.dart';
import '../ui/design/design.dart';
import 'catalog_session.dart';

/// The inspection panel: Chrome's shape, docked under the preview.
///
/// Collapsible and resizable, because the resting height is not the working
/// one — a widget tree is deep, and 260px is enough to see that there is a tree
/// and not enough to read it.
///
/// It reads the **live** guest through [CatalogSession], never a
/// `PluginAction`: an action renders its own headless copy, and a copy has none
/// of the state a person put this one into. That is the whole reason the panel
/// is not simply a rendering of `fw run ui_catalog inspect --tree`.
class InspectPanel extends StatefulWidget {
  const InspectPanel({
    super.key,
    required this.session,
    required this.available,
    required this.highlight,
    required this.picking,
    required this.controls,
  });

  final CatalogSession session;

  /// The node the pointer is over, shared with the preview's overlay — set
  /// here when you run down the tree, set there when you sweep the picker over
  /// the demo. One rectangle, pointed at from either end.
  final ValueNotifier<String?> highlight;

  /// Whether the preview is in picking mode.
  final ValueNotifier<bool> picking;

  /// How tall the panel and the preview are together.
  ///
  /// Passed in rather than measured here, and that is not fussiness: a `Column`
  /// lays a non-flex child out with an **unbounded** main axis, so a
  /// `LayoutBuilder` in this position reads `maxHeight: infinity` and any clamp
  /// against it is a clamp against nothing. The panel would resize past the
  /// bottom of the window and take the canvas with it.
  final double available;

  /// The Controls tab's body, supplied rather than built here.
  ///
  /// Keeps this file free of knob widgets — which the top bar's axis controls
  /// share, so they cannot simply move — and keeps the import pointing one way.
  final WidgetBuilder controls;

  @override
  State<InspectPanel> createState() => _InspectPanelState();
}

class _InspectPanelState extends State<InspectPanel> {
  /// Below this the panel is a scrollbar with ambitions.
  static const _minHeight = 140.0;

  /// What the preview keeps no matter how far the panel is dragged up. Without
  /// it the panel can eat the thing it is inspecting.
  static const _canvasFloor = 160.0;

  static const _stripHeight = 34.0;

  double _height = 260;
  var _collapsed = false;

  /// The tree's share of the width. The detail pane is the narrower of the two
  /// because a tree row is wide by nature — type, description, box and source
  /// all read on one line — while a detail is a short column of pairs.
  double _split = 0.62;

  @override
  void initState() {
    super.initState();
    // After the frame: turning this on starts a read, and a read that lands
    // synchronously would notify during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncInspecting();
      // Wider than [_syncInspecting] on purpose: the watch runs for as long as
      // the panel is here, whichever tab is showing, because a resize changes
      // what Problems should say and Problems is not the Elements tab.
      widget.session.panelOpen = true;
    });
  }

  @override
  void dispose() {
    // Safe here only because the setters deliberately do not notify.
    widget.session
      ..inspecting = false
      ..panelOpen = false;
    super.dispose();
  }

  /// Tells the session whether the tree is actually being looked at.
  ///
  /// Called after anything that could change the answer — a tab, the collapse
  /// — rather than once at mount, because the panel now opens on Controls and
  /// a mount is no longer the moment the tree becomes visible.
  void _syncInspecting() {
    widget.session.inspecting =
        !_collapsed && widget.session.inspectTab == InspectTab.elements;
  }

  @override
  Widget build(BuildContext context) {
    var ceiling = math.max(
      _minHeight,
      widget.available - _canvasFloor - _stripHeight,
    );
    // No `AddressScope` of its own: `inspect` is declared by [CatalogView],
    // because the picker writes a selection from the *preview* and that is on
    // the other side of the canvas. One namespace, two writers.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Grip(
          enabled: !_collapsed,
          onDrag: (delta) => setState(() {
            // Up is negative and up is bigger.
            _height = (_height - delta).clamp(_minHeight, ceiling);
          }),
        ),
        _TabStrip(
          current: widget.session.inspectTab,
          collapsed: _collapsed,
          problemCount:
              (widget.session.errorsForSelection?.errors.length ?? 0) +
              (widget.session.selectedError == null ? 0 : 1),
          picking: widget.picking,
          onPick: () {
            // Arming it is also a request to see the tree: picking a widget
            // and landing on the knobs would be answering a question nobody
            // asked.
            setState(() {
              _collapsed = false;
              widget.session.inspectTab = InspectTab.elements;
              _syncInspecting();
            });
            widget.picking.value = !widget.picking.value;
          },
          onTab: (tab) => setState(() {
            // Clicking the tab you are on is how you get the panel back
            // without hunting for the chevron.
            if (tab == widget.session.inspectTab && !_collapsed) {
              _collapsed = true;
            } else {
              _collapsed = false;
              widget.session.inspectTab = tab;
            }
            _syncInspecting();
          }),
          onCollapse: () => setState(() {
            _collapsed = !_collapsed;
            _syncInspecting();
          }),
          // Both, whichever tab is open. The tree is read again, and the
          // problems are *forgotten* and collected again — the record only
          // grows on its own, so a problem that has stopped needs somebody to
          // say so.
          onRefresh: () async {
            await widget.session.forgetErrors();
            await widget.session.readTree();
          },
        ),
        // Clamped on the way out as well as on the drag: the window can be
        // made smaller after the panel was dragged tall, and nothing about
        // that resize goes through [_Grip].
        if (!_collapsed)
          SizedBox(height: math.min(_height, ceiling), child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.session.inspectTab) {
      case InspectTab.controls:
        return widget.controls(context);
      case InspectTab.elements:
        return _Elements(
          session: widget.session,
          split: _split,
          onSplit: (fraction) => setState(() => _split = fraction),
          highlight: widget.highlight,
        );
      case InspectTab.problems:
        return _Problems(session: widget.session);
      case InspectTab.console:
        return _Console(session: widget.session);
    }
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

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.current,
    required this.collapsed,
    required this.problemCount,
    required this.picking,
    required this.onPick,
    required this.onTab,
    required this.onCollapse,
    required this.onRefresh,
  });

  final InspectTab current;
  final bool collapsed;

  /// How many distinct things the entry on screen reported.
  final int problemCount;
  final ValueListenable<bool> picking;
  final VoidCallback onPick;
  final ValueChanged<InspectTab> onTab;
  final VoidCallback onCollapse;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: context.colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
      child: Row(
        children: [
          // Leftmost, where Chrome puts it, and before the tabs because it is
          // not one: it changes what the *preview* does.
          ValueListenableBuilder(
            valueListenable: picking,
            builder: (context, on, _) => _StripButton(
              icon: Icons.my_location,
              tooltip: on
                  ? 'Stop picking (esc)'
                  : 'Pick a widget in the preview',
              active: on,
              onTap: onPick,
            ),
          ),
          // Scrolls rather than overflows. The panel is as narrow as the
          // window minus the entry list, which on a laptop with the list open
          // is not much — and a tab strip that paints Flutter's stripes over
          // itself in an inspector is a poor advertisement.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var tab in InspectTab.values)
                    _Tab(
                      label: tab.label,
                      selected: !collapsed && tab == current,
                      // Only Problems carries one, and only when there is
                      // something to carry: a badge that is always there is a
                      // decoration.
                      badge: tab == InspectTab.problems ? problemCount : 0,
                      onTap: () => onTab(tab),
                    ),
                ],
              ),
            ),
          ),
          // No `Spacer` beside the `Expanded` above. Two flex children divide
          // the free space between them, so a spacer here did not push the
          // buttons to the edge — it took half of what was left and parked
          // them somewhere in the middle. The same mistake as the tree row,
          // one widget over.
          if (!collapsed)
            _StripButton(
              icon: Icons.refresh,
              // Says what it is for rather than what it does. Until the guest
              // pushes changes (S5e), a demo's own state — a menu you opened,
              // a row you scrolled to — moves without anything here being
              // told, and nothing ever says a problem has stopped.
              tooltip: 'Read it all again',
              onTap: () => onRefresh(),
            ),
          _StripButton(
            icon: collapsed ? Icons.expand_less : Icons.expand_more,
            tooltip: collapsed ? 'Show the panel' : 'Hide the panel',
            onTap: onCollapse,
          ),
        ],
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

/// What the entry on screen reported while building and painting.
///
/// **Not what it failed to compile.** That is a different question with a
/// different answer already on screen — the compiler's own words, where the
/// widget would have been — and it is answered before a frame is ever drawn.
/// This is the half that a green compile says nothing about: a demo that throws
/// in `build` paints Flutter's red `ErrorWidget` while everything about
/// compiling and reloading reports success.
class _Problems extends StatelessWidget {
  const _Problems({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    // **The compile error belongs here too.** An entry that does not build
    // never renders, so waiting for a render report is waiting for something
    // that will never arrive — which is what this pane did: it sat on
    // "waiting…" forever for the one entry in the catalog that most obviously
    // has a problem. A tab called Problems should hold every reason this entry
    // is not working, and refusing to compile is the first of them.
    var compileError = session.selectedError;
    var report = session.errorsForSelection;
    var errors = report?.errors ?? const <InspectError>[];

    if (compileError == null && errors.isEmpty) {
      return Container(
        color: context.colors.panel,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          report == null
              ? 'Waiting for the entry to render…'
              : 'It renders without the framework reporting anything.',
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(color: context.colors.mut),
        ),
      );
    }

    return Container(
      color: context.colors.panel,
      child: ListView.separated(
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: FwSpacing.sm),
        itemCount: errors.length + (compileError == null ? 0 : 1),
        separatorBuilder: (context, _) =>
            Divider(height: 1, color: context.colors.line),
        itemBuilder: (context, index) {
          if (compileError != null && index == 0) {
            // First, because nothing below it ran. The others are what the
            // framework said while the entry was on screen; this is why it
            // never got there.
            return _Problem(
              error: InspectError(exception: compileError, library: 'compiler'),
            );
          }
          return _Problem(
            error: errors[index - (compileError == null ? 0 : 1)],
          );
        },
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final InspectError error;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: FwSpacing.sm),
                child: Icon(Icons.error_outline, size: 14, color: colors.red),
              ),
              Expanded(
                child: SelectableText(
                  error.exception,
                  style: context.type.caption.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, top: FwSpacing.xxs),
            child: Text(
              [
                ?error.library,
                ?error.context,
                // Counted rather than repeated: an error thrown from `paint`
                // fires once per frame, and a panel driving frames continuously
                // would otherwise show one overflow as several hundred
                // problems.
                if (error.count > 1) '${error.count}×',
              ].join(' · '),
              style: context.type.micro.copyWith(color: colors.mut),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the demo printed, newest at the bottom.
///
/// **The output existed and reached nowhere anybody could see it.** The guest's
/// `print` went to the *host's* console — the terminal running the GUI — so the
/// panel could not show it, `fw` could not return it, and an agent driving a
/// demo could not read the first thing a developer reaches for when something
/// is wrong. That is finding 8 of the panel spec, and this is the half of it
/// you can look at.
///
/// Scoped to the selected entry, like every other pane here. The guest empties
/// its buffer when the entry changes, so this shows what *this* demo has said
/// rather than a running tape of the session.
class _Console extends StatefulWidget {
  const _Console({required this.session});

  final CatalogSession session;

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  final _scroll = ScrollController();

  /// Whether new lines drag the view down with them.
  ///
  /// Kept **off the moment you scroll up**, which is the one thing a console
  /// has to get right: a demo printing every frame with a view that snaps back
  /// to the bottom is a console you cannot read a word of. Scrolling back to
  /// the end turns it on again, so nothing has to be pressed to resume.
  var _following = true;

  @override
  void initState() {
    super.initState();
    widget.session.guestLogs.addListener(_onLines);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.session.guestLogs.removeListener(_onLines);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // A few pixels of slack: `maxScrollExtent` moves as lines are added, and
    // demanding an exact match would drop out of following on the very frame a
    // line arrives.
    var atEnd = _scroll.offset >= _scroll.position.maxScrollExtent - 8;
    if (atEnd != _following) setState(() => _following = atEnd);
  }

  void _onLines() {
    if (!_following) return;
    // After the frame that lays the new line out — there is nothing to scroll
    // to until it has a height.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      color: colors.panel,
      child: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: widget.session.guestLogs,
              builder: (context, lines, _) {
                if (lines.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(FwSpacing.lg),
                      child: Text(
                        'Nothing printed yet. '
                        'Anything this demo prints shows up here.',
                        textAlign: TextAlign.center,
                        style: context.type.caption.copyWith(color: colors.mut),
                      ),
                    ),
                  );
                }
                var dropped = widget.session.logsDropped;
                return ListView.builder(
                  controller: _scroll,
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
                  itemCount: lines.length + (dropped == 0 ? 0 : 1),
                  itemBuilder: (context, index) {
                    // Said rather than silently begun in the middle: a
                    // scrollback that quietly starts partway reads as one that
                    // has everything, and the one time that matters is the one
                    // time you are looking for the first line.
                    if (dropped > 0 && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FwSpacing.lg,
                          vertical: FwSpacing.xxs,
                        ),
                        child: Text(
                          '$dropped earlier ${dropped == 1 ? 'line' : 'lines'} '
                          'dropped',
                          style: context.type.micro.copyWith(color: colors.mut),
                        ),
                      );
                    }
                    return _LogLine(
                      line: lines[index - (dropped == 0 ? 0 : 1)],
                    );
                  },
                );
              },
            ),
          ),
          Container(height: 1, color: colors.line),
          Row(
            children: [
              _StripButton(
                icon: Icons.block,
                tooltip: 'Clear',
                onTap: () => widget.session.clearLogs(),
              ),
              const Spacer(),
              if (!_following)
                _StripButton(
                  icon: Icons.vertical_align_bottom,
                  tooltip: 'Follow new lines',
                  onTap: () {
                    setState(() => _following = true);
                    if (_scroll.hasClients) {
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final InspectLogLine line;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var at = DateTime.fromMillisecondsSinceEpoch(line.at);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed width and monospace so the times form a column rather than a
          // ragged edge that the eye has to re-find on every line.
          SizedBox(
            width: 62,
            child: Text(
              '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}'
              '.${at.millisecond.toString().padLeft(3, '0')}',
              style: context.type.micro.copyWith(
                color: colors.mut,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              line.text,
              style: context.type.caption.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Armed, for the picker — which is a mode rather than a press, and a mode
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

/// Tree on the left, the selected node's detail on the right.
class _Elements extends StatelessWidget {
  const _Elements({
    required this.session,
    required this.split,
    required this.onSplit,
    required this.highlight,
  });

  final CatalogSession session;
  final ValueNotifier<String?> highlight;
  final double split;
  final ValueChanged<double> onSplit;

  @override
  Widget build(BuildContext context) {
    var tree = session.treeForSelection;
    if (tree == null || tree.root == null) {
      return Container(
        color: context.colors.panel,
        alignment: Alignment.center,
        child: Text(
          session.selected == null ? 'No entry selected' : 'Reading the tree…',
          style: context.type.caption.copyWith(color: context.colors.mut),
        ),
      );
    }

    var selectedId = AddressScope.params(context)['node'];
    var selected = selectedId == null ? null : tree.nodeAt(selectedId);

    return LayoutBuilder(
      builder: (context, constraints) {
        var treeWidth = (constraints.maxWidth * split)
            .clamp(200.0, math.max(200.0, constraints.maxWidth - 220))
            .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: treeWidth,
              child: _TreeView(
                root: tree.root!,
                selectedId: selectedId,
                highlight: highlight,
              ),
            ),
            _SplitGrip(
              onDrag: (delta) => onSplit(
                ((treeWidth + delta) / constraints.maxWidth).clamp(0.2, 0.85),
              ),
            ),
            Expanded(
              child: _Detail(
                node: selected,
                selectedId: selectedId,
                displayRoot: session.displayRoot,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SplitGrip extends StatelessWidget {
  const _SplitGrip({required this.onDrag});

  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (event) => onDrag(event.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(child: Container(width: 1, color: context.colors.line)),
        ),
      ),
    );
  }
}

/// The widget tree, indented.
///
/// Folded state is tracked by what has been **closed**, the same way the entry
/// browser does it: a node that appears after a reload is then open like
/// everything around it, where an opened-set would hide new work until somebody
/// thought to look for it.
class _TreeView extends StatefulWidget {
  const _TreeView({
    required this.root,
    required this.selectedId,
    required this.highlight,
  });

  final InspectNode root;
  final String? selectedId;

  /// Set as the pointer runs down the rows, so the preview draws the box for
  /// whatever is under it. Cleared when the pointer leaves the list — a
  /// highlight that outlived the hover would be pointing at nothing.
  final ValueNotifier<String?> highlight;

  @override
  State<_TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<_TreeView> {
  static const _rowHeight = 22.0;

  final _closed = <String>{};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TreeView old) {
    super.didUpdateWidget(old);
    var id = widget.selectedId;
    if (id != null && id != old.selectedId) _reveal(id);
  }

  /// Unfolds whatever was hiding [id] and scrolls it into view.
  ///
  /// The picker can land three levels inside a folded subtree and below the
  /// scroll, and selecting a row somewhere the asker cannot see is answering
  /// the question into the void. Chrome brings the tree to the element; so does
  /// this.
  void _reveal(String id) {
    var parts = id.isEmpty ? const <String>[] : id.split('/');
    var opened = false;
    // Every ancestor, root first: '' then '0' then '0/1' for '0/1/2'.
    for (var i = 0; i <= parts.length - 1; i++) {
      if (_closed.remove(parts.take(i).join('/'))) opened = true;
    }
    if (opened) setState(() {});

    // After the frame, so the rows reflect whatever was just unfolded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      var index = _rows().indexWhere((row) => row.$1.id == id);
      if (index < 0) return;
      var offset = index * _rowHeight;
      var top = _scroll.offset;
      var bottom = top + _scroll.position.viewportDimension - _rowHeight;
      // Only when it is actually out of sight: scrolling a row that was
      // already visible moves the tree under the reader for no reason.
      if (offset < top || offset > bottom) {
        _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  /// The visible rows, flattened, with the depth each should be drawn at.
  List<(InspectNode, int)> _rows() {
    var rows = <(InspectNode, int)>[];
    void walk(InspectNode node, int depth) {
      rows.add((node, depth));
      if (_closed.contains(node.id)) return;
      for (var child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(widget.root, 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    var rows = _rows();

    return Container(
      color: context.colors.panel,
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          onExit: (_) => widget.highlight.value = null,
          child: ListView.builder(
            primary: false,
            controller: _scroll,
            itemCount: rows.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, index) {
              var (node, depth) = rows[index];
              return _TreeRow(
                node: node,
                depth: depth,
                // Measured once for the list rather than per row: it is the
                // panel's width, and the panel does not change width between two
                // rows of the same frame.
                indent: math.min(depth * 12.0, constraints.maxWidth * 0.4),
                // Below this there is no room for it and the type, and the type
                // is what you scan by.
                showSize: constraints.maxWidth > 320,
                highlight: widget.highlight,
                open: !_closed.contains(node.id),
                selected: node.id == widget.selectedId,
                onHover: (over) {
                  if (over) {
                    widget.highlight.value = node.id;
                  } else if (widget.highlight.value == node.id) {
                    // Only if it is still ours: the pointer has already entered
                    // the next row by the time this fires, and clearing then would
                    // put out the light that row just turned on.
                    widget.highlight.value = null;
                  }
                },
                onToggle: () => setState(() {
                  if (!_closed.remove(node.id)) _closed.add(node.id);
                }),
                onTap: () =>
                    AddressScope.write(context).setParam('node', node.id),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.indent,
    required this.showSize,
    required this.open,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onHover,
    required this.highlight,
  });

  final InspectNode node;
  final int depth;

  /// How far the row is pushed in, **capped**: twelve levels at twelve pixels
  /// each is most of a narrow panel, and an indent that eats the whole row is
  /// what put Flutter's overflow stripes across an inspector.
  final double indent;

  /// Whether there is room for the box on the right.
  final bool showSize;
  final bool open;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  /// Read as well as written, so the row lights up for whatever the rectangle
  /// is currently on — including when the *picker* is what put it there. Sweep
  /// the demo and the tree follows you, which is the same courtesy in reverse.
  final ValueNotifier<String?> highlight;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      onHover: onHover,
      child: ValueListenableBuilder(
        valueListenable: highlight,
        builder: (context, lit, child) => Container(
          // Selection outranks hover: one is where you are, the other is where
          // you were going.
          color: selected
              ? colors.accentSoft
              : lit == node.id
              ? colors.panel2
              : null,
          child: child,
        ),
        child: Container(
          padding: EdgeInsets.only(left: FwSpacing.sm + indent),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: node.children.isEmpty
                    ? null
                    : InkWell(
                        onTap: onToggle,
                        child: Icon(
                          open ? Icons.arrow_drop_down : Icons.arrow_right,
                          size: 14,
                          color: colors.mut,
                        ),
                      ),
              ),
              // **One flexible child, not two beside a `Spacer`.** Three flex
              // children divide the free space between them, so the spacer was
              // taking a third of every row — which both truncated the
              // description early, against an obviously empty right margin,
              // and left the size wherever the description happened to stop.
              // The text takes everything that is going; the size is a column.
              Expanded(
                child: Row(
                  children: [
                    // The type keeps what it needs and the description gives
                    // way: a deep node indents its row a long way, and the type
                    // is what you scan by.
                    Flexible(
                      child: Text(
                        node.type,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: context.type.caption.copyWith(
                          // The demo's own widgets bright, the plumbing between
                          // them dim: a summary tree is mostly the former, and
                          // the few that are not are what you scroll past.
                          color: node.createdByLocalProject
                              ? colors.ink
                              : colors.mut,
                        ),
                      ),
                    ),
                    if (node.description case var description?
                        when description != node.type) ...[
                      const SizedBox(width: FwSpacing.sm),
                      Flexible(
                        child: Text(
                          description,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: context.type.caption.copyWith(
                            color: colors.mut2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showSize)
                // A fixed width and right-aligned, so the numbers form a
                // column rather than each landing where its row's text ran
                // out. Present even when the node has no box, or the rows
                // either side of one would close the gap and the column would
                // wander again.
                SizedBox(
                  width: 84,
                  child: Padding(
                    padding: const EdgeInsets.only(right: FwSpacing.md),
                    child: Text(
                      switch (node.layout) {
                        var l? => '${_n(l.width)}×${_n(l.height)}',
                        null => '',
                      },
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: context.type.micro.copyWith(color: colors.mut3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is known about one node.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.node,
    required this.selectedId,
    required this.displayRoot,
  });

  final InspectNode? node;

  /// What a source path is shortened against — see [CatalogSession.displayRoot].
  final String displayRoot;

  /// Told apart from [node] being null: an id that resolves to nothing is a
  /// selection that outlived the tree it named, which is worth saying rather
  /// than showing as "nothing selected".
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (node == null) {
      return Container(
        color: context.colors.panel2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          selectedId == null
              ? 'Select a widget'
              : 'The tree no longer has $selectedId.\nIt named a position, and '
                    'the shape changed.',
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(color: colors.mut),
        ),
      );
    }

    var it = node!;
    var layout = it.layout;
    return Container(
      color: colors.panel2,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(FwSpacing.lg),
        children: [
          SelectableText(
            it.type,
            style: context.type.bodyStrong.copyWith(color: colors.ink),
          ),
          if (it.description case var description? when description != it.type)
            SelectableText(
              description,
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          const SizedBox(height: FwSpacing.md),
          // The id is the thing an agent is handed and the thing it hands back
          // — `screenshot --node`, `tree --node` — so it is selectable rather
          // than decorative.
          _Pair(label: 'id', value: it.id.isEmpty ? '(root)' : it.id),
          if (it.source case var source?)
            _Pair(
              label: 'source',
              // Shortened against the worktree, so this is the same string
              // `fw run ui_catalog inspect --tree` prints for the same node — one can be
              // pasted where the other was expected.
              value: source.describe(relativeTo: displayRoot),
            ),
          if (layout != null) ...[
            const SizedBox(height: FwSpacing.md),
            _Pair(
              label: 'size',
              value: '${_n(layout.width)} × ${_n(layout.height)}',
            ),
            _Pair(label: 'offset', value: '${_n(layout.x)}, ${_n(layout.y)}'),
            if (layout.constraints case var constraints?)
              _Pair(label: 'given', value: constraints.describe()),
            if (layout.flex case var flex?)
              _Pair(
                label: 'flex',
                value: [
                  flex.direction,
                  ?flex.mainAxisAlignment,
                  ?flex.crossAxisAlignment,
                  ?flex.mainAxisSize,
                ].join(', '),
              ),
            if (layout.flexFactor case var factor?)
              _Pair(
                label: 'in parent',
                value: layout.flexFit == null
                    ? 'flex $factor'
                    : 'flex $factor (${layout.flexFit})',
              ),
            if (layout.isRepaintBoundary)
              _Pair(label: 'paints', value: 'repaint boundary'),
          ] else ...[
            const SizedBox(height: FwSpacing.md),
            Text(
              // Not zero-filled, because "it has no box" and "its box is empty"
              // are different answers and only one of them is a bug.
              'Lays nothing out of its own — a provider or a builder.',
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: context.type.micro.copyWith(color: context.colors.mut3),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: context.type.caption.copyWith(color: context.colors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout arrives as doubles and is nearly always whole pixels, so `48` beats
/// `48.0` and `47.5` still says so.
String _n(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);
