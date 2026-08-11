import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/previews_guest.dart';

import '../address/address_scope.dart';
import '../previews/devices.dart';
import '../inspect/elements_view.dart';
import '../inspect/inspect_dock.dart';
import '../inspect/node_highlight.dart';
import '../inspect/pick_region.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'events_view.dart';
import 'framed_shot.dart';
import '../inspect/semantics_node.dart';
import '../inspect/semantics_view.dart';
import 'step_status.dart';

/// One step, pushed over the flow: the frame big, the inspect dock under it —
/// the same Chrome-shaped panel Previews docks under its preview, with
/// the tabs a snapshot can honestly serve. The back arrow returns to the
/// flow; previous/next walk the run's graph without going back.
///
/// **Elements** is the step's `.tree.json` — the capture's third leg, read at
/// last — in the catalog's own tree view: hover a row and the widget's box
/// lights up on the screenshot, pick on the screenshot and the tree jumps to
/// the node. **Texts** is the visible-text projection that used to be the
/// sidebar. Selection is the `node` address parameter, exactly as in the
/// catalog, so a step link with a node in it is shareable.
class ScenarioStepPage extends StatefulWidget {
  const ScenarioStepPage({
    super.key,
    required this.steps,
    required this.step,
    required this.device,
    required this.onBack,
    required this.onOpenStep,
    required this.displayRoot,
    this.statusFallback = Brightness.dark,
  });

  final List<ScenarioRunStep> steps;
  final ScenarioRunStep step;
  final Device? device;
  final VoidCallback onBack;
  final void Function(ScenarioRunStep) onOpenStep;

  /// What a node's source path is shortened against — the package root.
  final String displayRoot;

  /// Status-chrome tint when the step declared no overlay style.
  final Brightness statusFallback;

  @override
  State<ScenarioStepPage> createState() => _ScenarioStepPageState();
}

class _ScenarioStepPageState extends State<ScenarioStepPage> {
  /// The node the pointer is over — set from the tree's rows and from the
  /// picker's sweep, drawn once over the screenshot. One rectangle, pointed
  /// at from either end, as the catalog does it.
  final _highlight = ValueNotifier<String?>(null);

  /// The semantics tab's hover, its own notifier: the id spaces differ, and
  /// only the elements one round-trips through the picker.
  final _semanticsHighlight = ValueNotifier<SemanticsSnapshotNode?>(null);
  final _picking = ValueNotifier<bool>(false);

  var _tab = 'elements';
  var _collapsed = false;

  /// The step's tree, read from its `.tree.json` — null while loading, with
  /// [_treeError] carrying the failure when there is one.
  InspectTree? _tree;
  String? _treeError;
  String? _loadedPath;

  /// The step's semantics tree, read from its `.semantics.json` when the
  /// step has one; [_semanticsError] says why when it does not.
  SemanticsSnapshotNode? _semantics;
  String? _semanticsError;

  /// The transition's events, read from its `.events.json`. Empty for a quiet
  /// transition and for a run that predates the capture; [_eventsPlaceholder]
  /// tells the two apart.
  var _events = const <Map<String, Object?>>[];
  String? _eventsPlaceholder;

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  @override
  void didUpdateWidget(ScenarioStepPage old) {
    super.didUpdateWidget(old);
    _loadTree();
  }

  @override
  void dispose() {
    _highlight.dispose();
    _semanticsHighlight.dispose();
    _picking.dispose();
    super.dispose();
  }

  /// Reads the step's trees once per step. The files are already on disk —
  /// the harness wrote them beside the pixels — and small, so this is a plain
  /// synchronous read from `initState`/`didUpdateWidget`, never a spinner.
  void _loadTree() {
    var path = widget.step.tree;
    if (path == _loadedPath) return;
    _loadedPath = path;
    _highlight.value = null;
    _semanticsHighlight.value = null;
    try {
      _tree = InspectTree.fromJson(
        (jsonDecode(widget.step.treeFile.readAsStringSync()) as Map)
            .cast<String, Object?>(),
      );
      _treeError = null;
    } catch (error) {
      _tree = null;
      _treeError = 'The tree could not be read:\n$error';
    }
    _semantics = null;
    if (widget.step.semanticsFile case var file?) {
      try {
        _semantics = SemanticsSnapshotNode.fromJson(
          (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>(),
        );
        _semanticsError = null;
      } catch (error) {
        _semanticsError = 'The semantics tree could not be read:\n$error';
      }
    } else {
      // Absence has two honest readings and only one file to tell them by.
      _semanticsError =
          'No semantics captured for this step — the run predates the '
          'capture, or the app disabled semantics.';
    }
    _events = const [];
    _eventsPlaceholder = null;
    if (widget.step.eventsFile case var file? when file.existsSync()) {
      try {
        _events = [
          for (var event in jsonDecode(file.readAsStringSync()) as List)
            (event as Map).cast<String, Object?>(),
        ];
      } catch (error) {
        _eventsPlaceholder = 'The events could not be read:\n$error';
      }
    } else {
      // A quiet transition is the common case and reads as one; a step with a
      // count but no file is a run whose artifacts have moved.
      _eventsPlaceholder = widget.step.hasEvents
          ? 'This step recorded ${widget.step.eventCount} events, but the '
                'file is gone. Run the scenario again.'
          : 'Nothing happened on the way to this step — no logs, no requests, '
                'no platform calls.';
    }
  }

  void _select(String id) => AddressScope.write(context).setParam('node', id);

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (previous, next) = _neighbours();

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.lg,
              vertical: FwSpacing.md,
            ),
            child: Row(
              children: [
                Tappable(
                  onTap: widget.onBack,
                  child: Icon(Icons.arrow_back, size: 18, color: colors.mut),
                ),
                const Gap(FwSpacing.lg),
                Expanded(
                  child: Text(
                    '${widget.step.index} · ${scenarioStepLabel(widget.step)}',
                    style: context.type.heading.copyWith(
                      color: widget.step.failure != null
                          ? colors.red
                          : context.type.heading.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Above the pixels, because on a failed step the message is what the
          // reader came for and the picture is the evidence.
          ScenarioStepNotice(widget.step),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: colors.panel2,
                    padding: const EdgeInsets.all(FwSpacing.xl),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: FramedShot(
                        step: widget.step,
                        device: widget.device,
                        fallbackBrightness: widget.statusFallback,
                        screenOverlay: _ScreenOverlay(
                          tree: _tree,
                          highlight: _highlight,
                          semanticsHighlight: _semanticsHighlight,
                          picking: _picking,
                          onPick: _select,
                        ),
                      ),
                    ),
                  ),
                ),
                if (previous != null)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: _StepLink(
                      previous,
                      isNext: false,
                      onTap: () => widget.onOpenStep(previous),
                    ),
                  ),
                if (next != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _StepLink(
                      next,
                      isNext: true,
                      onTap: () => widget.onOpenStep(next),
                    ),
                  ),
              ],
            ),
          ),
          InspectDock(
            available: constraints.maxHeight,
            current: _tab,
            collapsed: _collapsed,
            onChanged: (current, collapsed) => setState(() {
              _tab = current;
              _collapsed = collapsed;
            }),
            leading: ValueListenableBuilder(
              valueListenable: _picking,
              builder: (context, on, _) => InspectStripButton(
                icon: Icons.my_location,
                tooltip: on
                    ? 'Stop picking (esc)'
                    : 'Pick a widget on the screenshot',
                active: on,
                onTap: () {
                  // Arming it is also a request to see the tree, as in the
                  // catalog.
                  setState(() {
                    _collapsed = false;
                    _tab = 'elements';
                  });
                  _picking.value = !_picking.value;
                },
              ),
            ),
            tabs: [
              InspectDockTab(
                id: 'elements',
                label: 'Elements',
                body: (context) => ElementsView(
                  root: _tree?.root,
                  placeholder: _treeError ?? 'No tree captured for this step.',
                  highlight: _highlight,
                  displayRoot: widget.displayRoot,
                ),
              ),
              InspectDockTab(
                id: 'semantics',
                label: 'Semantics',
                body: (context) => SemanticsView(
                  root: _semantics,
                  placeholder: _semanticsError ?? 'No semantics captured.',
                  highlight: _semanticsHighlight,
                ),
              ),
              InspectDockTab(
                id: 'events',
                label: 'Events',
                badge: widget.step.notableEventCount,
                body: (context) => ScenarioEventsView(
                  events: _events,
                  transition: scenarioStepTransition(widget.step),
                  dropped: widget.step.eventsDropped ?? 0,
                  placeholder: _eventsPlaceholder ?? 'No events captured.',
                ),
              ),
              InspectDockTab(
                id: 'texts',
                label: 'Texts',
                body: (context) => _TextsTab(step: widget.step),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Walks the graph, not the emission order: previous is this step's
  /// parent, next its first child — so inside a split branch the links stay
  /// on the branch. Parentless data (older artifacts) falls back to the
  /// list order it used to walk.
  (ScenarioRunStep?, ScenarioRunStep?) _neighbours() {
    var steps = widget.steps;
    var step = widget.step;
    if (steps.any((s) => s.parent != null)) {
      return (
        steps.firstWhereOrNull((s) => s.index == step.parent),
        steps.firstWhereOrNull((s) => s.parent == step.index),
      );
    }
    var position = steps.indexWhere((s) => s.index == step.index);
    return (
      position > 0 ? steps[position - 1] : null,
      position >= 0 && position + 1 < steps.length ? steps[position + 1] : null,
    );
  }
}

/// The inspector's presence on the screenshot: the highlight rectangle, and —
/// while the picker is armed — the sweep and the click. Sits in the screen's
/// own logical coordinates (see [FramedShot.screenOverlay]), which are the
/// coordinates every node's box is in — the widget tree's and the semantics
/// tree's alike — so a pointer position *is* a tree query.
class _ScreenOverlay extends StatelessWidget {
  const _ScreenOverlay({
    required this.tree,
    required this.highlight,
    required this.semanticsHighlight,
    required this.picking,
    required this.onPick,
  });

  final InspectTree? tree;
  final ValueNotifier<String?> highlight;
  final ValueNotifier<SemanticsSnapshotNode?> semanticsHighlight;
  final ValueNotifier<bool> picking;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    var box = ValueListenableBuilder(
      valueListenable: highlight,
      builder: (context, lit, _) => ValueListenableBuilder(
        valueListenable: semanticsHighlight,
        builder: (context, semanticsLit, _) {
          // The elements highlight wins when both are set — it is the one the
          // picker writes, and the two tabs cannot be hovered at once.
          var node = lit == null ? null : tree?.nodeAt(lit);
          // An offstage node's rect is where it was, not where anything is:
          // drawing it over the screenshot would box a different widget. The
          // row still lights up; the picture stays quiet.
          if (node?.offstage ?? false) node = null;
          var (rect, label) = switch ((node, semanticsLit)) {
            (var n?, _) when n.layout != null => (
              Rect.fromLTWH(
                n.layout!.x,
                n.layout!.y,
                n.layout!.width,
                n.layout!.height,
              ),
              n.type,
            ),
            (_, var s?) => (s.rect, s.headline),
            _ => (null, null),
          };
          return CustomPaint(
            painter: NodeHighlightPainter(
              rect: rect,
              label: label,
              color: context.colors.accent,
            ),
          );
        },
      ),
    );

    return ValueListenableBuilder(
      valueListenable: picking,
      builder: (context, on, _) {
        if (!on) return IgnorePointer(child: box);
        return InspectPickRegion(
          onSweep: (point) =>
              highlight.value = tree?.nodeAtPoint(point.dx, point.dy)?.id,
          onClear: () => highlight.value = null,
          onPick: (point) {
            // On a snapshot the rectangles are all there is — no live guest
            // to run the framework's own hit test, so the pointer's
            // approximation is also the commit.
            var hit = tree?.nodeAtPoint(point.dx, point.dy);
            // A miss is a miss, not a selection to clear.
            if (hit != null) onPick(hit.id);
          },
          onDisarm: () => picking.value = false,
          child: box,
        );
      },
    );
  }
}

/// The visible-text projection and the tags — the step page's old sidebar,
/// now a dock tab beside Elements.
class _TextsTab extends StatelessWidget {
  const _TextsTab({required this.step});

  final ScenarioRunStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.panel,
      width: double.infinity,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(FwSpacing.lg),
        children: [
          Text('VISIBLE TEXTS', style: context.type.sectionLabel),
          const Gap(FwSpacing.md),
          if (step.texts.isEmpty)
            Text('No visible texts.', style: context.type.bodyMuted)
          else
            for (var text in step.texts)
              Padding(
                padding: const EdgeInsets.only(bottom: FwSpacing.xs),
                child: SelectableText(text, style: context.type.bodySmall),
              ),
          if (step.tags.isNotEmpty) ...[
            const Gap(FwSpacing.lg),
            Text('TAGS', style: context.type.sectionLabel),
            const Gap(FwSpacing.md),
            Text(step.tags.join(', '), style: context.type.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _StepLink extends StatelessWidget {
  const _StepLink(this.step, {required this.isNext, required this.onTap});

  final ScenarioRunStep step;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.sm,
        ),
        color: colors.bg.withValues(alpha: 0.9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isNext)
              Icon(Icons.arrow_back_ios, size: 12, color: colors.mut),
            Text(
              '${step.index} · ${scenarioStepLabel(step)}',
              style: context.type.caption.copyWith(
                color: scenarioStepTone(context, step),
              ),
            ),
            if (isNext)
              Icon(Icons.arrow_forward_ios, size: 12, color: colors.mut),
          ],
        ),
      ),
    );
  }
}
