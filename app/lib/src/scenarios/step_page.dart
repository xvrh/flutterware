import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutterware/previews_guest.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../address/address_scope.dart';
import '../previews/devices.dart';
import '../inspect/elements_view.dart';
import '../inspect/inspect_dock.dart';
import '../inspect/node_highlight.dart';
import '../inspect/pick_region.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/capture_button.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'artifacts.dart';
import 'events_view.dart';
import 'framed_shot.dart';
import 'motion_player.dart';
import '../inspect/focus_order.dart';
import '../inspect/semantics_node.dart';
import '../inspect/semantics_view.dart';
import '../inspect/transcript.dart';
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

// Plural on purpose: the motion player is rebuilt — new controller, new
// ticker — every time the previous/next links change the step under this same
// State, and the single-ticker mixin vends exactly one ticker per State
// *lifetime*, disposed or not. With it, the second step of any walk through a
// frames-recording run threw during build.
class _ScenarioStepPageState extends State<ScenarioStepPage>
    with TickerProviderStateMixin {
  /// The node the pointer is over — set from the tree's rows and from the
  /// picker's sweep, drawn once over the screenshot. One rectangle, pointed
  /// at from either end, as the catalog does it.
  final _highlight = ValueNotifier<String?>(null);

  /// The semantics tab's hover, its own notifier: the id spaces differ, and
  /// only the elements one round-trips through the picker.
  final _semanticsHighlight = ValueNotifier<SemanticsSnapshotNode?>(null);
  final _picking = ValueNotifier<bool>(false);

  /// The Semantics tab's reading-order switch: on, the overlay numbers every
  /// utterance on the screenshot, matching the script's row indices.
  final _focusOrder = ValueNotifier<bool>(false);

  var _tab = 'elements';
  var _collapsed = false;

  /// Playback over the transition that arrived at this step, or null when the
  /// run recorded none.
  ScenarioMotionController? _motion;

  /// The step's tree, read from its `.tree.json` — null while loading, with
  /// [_treeError] carrying the failure when there is one.
  InspectTree? _tree;
  String? _treeError;
  String? _loadedPath;

  /// The step's semantics tree, read from its `.semantics.json` when the
  /// step has one; [_semanticsError] says why when it does not.
  SemanticsSnapshotNode? _semantics;
  String? _semanticsError;

  /// The same capture read as a script, with the label audits' findings —
  /// derived from [_semantics] in the same setState that parses it.
  SemanticsTranscript? _transcript;

  /// The transition's events, read from its `.events.json`. Empty for a quiet
  /// transition and for a run that predates the capture; [_eventsPlaceholder]
  /// tells the two apart.
  var _events = const <Map<String, Object?>>[];
  String? _eventsPlaceholder;

  /// The source the three reads below go through, and part of what decides
  /// whether they have to be done again.
  ScenarioArtifacts? _artifacts;

  /// Bumped on every load, so a read that finishes after the reader moved on
  /// does not write its answer over the step now on screen.
  var _generation = 0;

  /// What the player on hand was built for — `didChangeDependencies` fires on
  /// any inherited change (theme, scopes), and rebuilding the player for one
  /// of those would throw away the frame the person had scrubbed to.
  var _motionLoaded = false;
  String? _motionFrames;

  // `didChangeDependencies`, not `initState`: the artifacts come from an
  // inherited widget, which cannot be depended on before the first build.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTree();
    if (!_motionLoaded || _motionFrames != widget.step.frames) _loadMotion();
  }

  @override
  void didUpdateWidget(ScenarioStepPage old) {
    super.didUpdateWidget(old);
    _loadTree();
    if (old.step.frames != widget.step.frames) {
      // Walking to the next step, or a re-run replacing this one: either way
      // the recording just left behind is not what is on screen any more.
      scenarioMotionResidency.forget(old.step);
      _loadMotion();
    }
  }

  @override
  void dispose() {
    _motion?.dispose();
    _highlight.dispose();
    _semanticsHighlight.dispose();
    _picking.dispose();
    _focusOrder.dispose();
    super.dispose();
  }

  /// Builds this step's player, resting on the last frame — which is the
  /// screenshot, so arriving on the page looks exactly as it did before the
  /// recording existed. Walking to the next step with the previous/next links
  /// rebuilds it for the new transition.
  void _loadMotion() {
    _motionLoaded = true;
    _motionFrames = widget.step.frames;
    _motion?.dispose();
    _motion = ScenarioMotionController.forStep(widget.step, this)
      ?..rest()
      ..addListener(_onFrame);
    if (_motion == null) return;
    // After the frame, not from `initState`: precaching resolves against the
    // element's image configuration, which does not exist yet here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(precacheScenarioMotion(context, widget.step));
    });
  }

  void _onFrame() {
    if (mounted) setState(() {});
  }

  /// Reads the step's three JSON artifacts, once per step.
  ///
  /// Asynchronous, because on the exported page these are three HTTP requests
  /// rather than three small files the harness just wrote — the panel's own
  /// reads still complete within a frame or two, and nothing here shows a
  /// spinner for them.
  void _loadTree() {
    var artifacts = ScenarioArtifactsScope.of(context);
    var path = widget.step.tree;
    if (path == _loadedPath && artifacts == _artifacts) return;
    _loadedPath = path;
    _artifacts = artifacts;
    _highlight.value = null;
    _semanticsHighlight.value = null;
    unawaited(_read(artifacts, ++_generation));
  }

  Future<void> _read(ScenarioArtifacts artifacts, int generation) async {
    var step = widget.step;
    // Fetched together: three round trips one after another is three times the
    // latency on a page served from anywhere but localhost.
    var (tree, semantics, events) = await (
      step.tree == null
          ? Future<String?>.value()
          : artifacts.readString(step.tree!),
      step.semantics == null
          ? Future<String?>.value()
          : artifacts.readString(step.semantics!),
      step.events == null
          ? Future<String?>.value()
          : artifacts.readString(step.events!),
    ).wait;
    if (!mounted || generation != _generation) return;

    setState(() {
      if (tree == null) {
        _tree = null;
        _treeError = 'The tree could not be read: ${step.tree} is not there.';
      } else {
        try {
          _tree = InspectTree.fromJson(
            (jsonDecode(tree) as Map).cast<String, Object?>(),
          );
          _treeError = null;
        } catch (error) {
          _tree = null;
          _treeError = 'The tree could not be read:\n$error';
        }
      }

      _semantics = null;
      _transcript = null;
      if (step.semantics == null) {
        // Absence has two honest readings and only one file to tell them by.
        _semanticsError =
            'No semantics captured for this step — the run predates the '
            'capture, or the app disabled semantics.';
      } else if (semantics == null) {
        _semanticsError =
            'The semantics tree is gone: ${step.semantics} is not there.';
      } else {
        try {
          _semantics = SemanticsSnapshotNode.fromJson(
            (jsonDecode(semantics) as Map).cast<String, Object?>(),
          );
          _transcript = SemanticsTranscript.of(_semantics!);
          _semanticsError = null;
        } catch (error) {
          _semanticsError = 'The semantics tree could not be read:\n$error';
        }
      }

      _events = const [];
      _eventsPlaceholder = null;
      if (events != null) {
        try {
          _events = [
            for (var event in jsonDecode(events) as List)
              (event as Map).cast<String, Object?>(),
          ];
        } catch (error) {
          _eventsPlaceholder = 'The events could not be read:\n$error';
        }
      } else {
        // A quiet transition is the common case and reads as one; a step with
        // a count but no file is a run whose artifacts have moved.
        _eventsPlaceholder = step.hasEvents
            ? 'This step recorded ${step.eventCount} events, but the '
                  'file is gone. Run the scenario again.'
            : 'Nothing happened on the way to this step — no logs, no '
                  'requests, no platform calls.';
      }
    });
  }

  void _select(String id) => AddressScope.write(context).setParam('node', id);

  /// The step's shot as PNG bytes — the artifact as-is when the run captured
  /// PNG, encoded here when it captured raw pixels. Encoding on demand
  /// mirrors why raw exists at all: every capture pays a write, only the
  /// rare one somebody exports pays an encode. Read through the artifacts
  /// scope like every other read on this page; a missing file is a null, the
  /// button's quiet refusal.
  Future<Uint8List?> _capturePng() async {
    var step = widget.step;
    var image = step.image;
    if (image == null) return null;
    var bytes = await ScenarioArtifactsScope.of(context).readBytes(image);
    if (bytes == null || step.format != 'raw') return bytes;
    return img.encodePng(
      img.Image.fromBytes(
        width: step.width!,
        height: step.height!,
        bytes: bytes.buffer,
        bytesOffset: bytes.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      ),
    );
  }

  /// Named after the files the run wrote — `<run dir>-<index>-<label>` — so a
  /// directory of saves reads like the run that produced them.
  String _suggestedName() {
    var path = widget.step.image ?? '';
    return '${p.basename(p.dirname(path))}-'
        '${p.basenameWithoutExtension(path)}.png';
  }

  /// The recorded frame to draw instead of the shot, or null when playback is
  /// parked at the end — where the shot itself is the frame, and the page is
  /// exactly what it was before any of this existed.
  ImageProvider? get _frame {
    var motion = _motion;
    if (motion == null || motion.index >= motion.frames.length - 1) return null;
    return scenarioFrameImage(
      ScenarioArtifactsScope.of(context),
      widget.step,
      motion.frames[motion.index],
    );
  }

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
                  child: Icon(
                    Icons.arrow_back,
                    size: FwIconSize.lg,
                    color: colors.mut,
                  ),
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
                // Not on the exported web page, which compiles this very
                // file: the clipboard and the save dialog are desktop
                // affordances (`dart:io` throws at first touch under
                // dart2js), and the browser's own right-click already saves
                // an image.
                if (!kIsWeb)
                  CaptureButton(
                    primary: CaptureTarget(
                      label: 'the screenshot',
                      capture: _capturePng,
                      suggestedName: _suggestedName,
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
                        image: _frame,
                        // Dropped while the transition is anywhere but its
                        // last frame: every rectangle in the tree was measured
                        // on the frame the step settled at, and drawn over a
                        // frame from the middle of a page push it would box a
                        // widget that is not there yet.
                        screenOverlay: _frame != null
                            ? null
                            : _ScreenOverlay(
                                tree: _tree,
                                highlight: _highlight,
                                semanticsHighlight: _semanticsHighlight,
                                picking: _picking,
                                onPick: _select,
                                focusOrder: _focusOrder,
                                // Only while the Semantics tab is the one
                                // showing — its toggle is the only way to turn
                                // the numbers off, so they must not outlive it.
                                focusNodes: _tab == 'semantics'
                                    ? _transcript?.utterances
                                          .map((u) => u.node)
                                          .toList()
                                    : null,
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
          if (_motion case var motion?)
            _MotionTransport(motion: motion, step: widget.step),
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
                  // Recorded by the guest during the run — including in a web
                  // export, which replays what the guest wrote rather than
                  // reading an app of its own.
                  readsWidgets: true,
                ),
              ),
              InspectDockTab(
                id: 'semantics',
                label: 'Semantics',
                badge: _transcript?.findingCount ?? 0,
                body: (context) => SemanticsView(
                  root: _semantics,
                  transcript: _transcript,
                  placeholder: _semanticsError ?? 'No semantics captured.',
                  highlight: _semanticsHighlight,
                  focusOrder: _focusOrder,
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

/// The transport for the transition into this step: play, scrub, step a frame
/// at a time.
///
/// Under the pixels rather than in the inspect dock, because that is what it
/// is about — the dock holds trees and lists, and a scrubber that lived in a
/// tab would be a control for something you cannot see while you use it.
///
/// The scrubber is labelled in the app's **own** milliseconds. Under FakeAsync
/// a frame is exactly one interval after the last, so `132ms` is where the
/// animation was and not where this machine happened to draw it — which is
/// also why this can never say anything about jank.
class _MotionTransport extends StatelessWidget {
  const _MotionTransport({required this.motion, required this.step});

  final ScenarioMotionController motion;
  final ScenarioRunStep step;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var last = motion.frames.length - 1;
    var dropped = step.framesDropped ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.sm,
      ),
      child: Row(
        children: [
          Tappable(
            onTap: motion.toggle,
            child: Padding(
              padding: const EdgeInsets.all(FwSpacing.xs),
              child: Icon(
                motion.playing ? Icons.pause : Icons.play_arrow,
                size: FwIconSize.lg,
                color: colors.accent,
              ),
            ),
          ),
          _StepFrameButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous frame',
            onTap: motion.index > 0 ? () => motion.step(-1) : null,
          ),
          _StepFrameButton(
            icon: Icons.chevron_right,
            tooltip: 'Next frame',
            onTap: motion.index < last ? () => motion.step(1) : null,
          ),
          const Gap(FwSpacing.md),
          Expanded(
            // `Slider` insists on a Material ancestor and the panel has none
            // — the shell's surfaces are the design system's, not Material's.
            child: Material(
              type: MaterialType.transparency,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: colors.accent,
                  inactiveTrackColor: colors.mut3,
                  thumbColor: colors.accent,
                ),
                child: Slider(
                  value: motion.index.toDouble(),
                  max: last.toDouble(),
                  divisions: last,
                  onChanged: (value) => motion.seek(value.round()),
                ),
              ),
            ),
          ),
          const Gap(FwSpacing.md),
          Text(
            '${motion.position.inMilliseconds} / '
            '${motion.duration.inMilliseconds} ms',
            style: context.type.caption,
          ),
          const Gap(FwSpacing.md),
          Text(
            '${motion.frames.length} frames',
            style: context.type.caption.copyWith(color: colors.mut),
          ),
          if (dropped > 0) ...[
            const Gap(FwSpacing.md),
            Tooltip(
              // The honest reading of a recording that hit its cap: the app
              // was still moving when the recorder stopped, so the last frame
              // is not where the animation ended.
              message:
                  'The recording stopped at its frame cap with $dropped more '
                  'frames to go — the app was still animating.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.content_cut,
                    size: FwIconSize.xs,
                    color: colors.mut,
                  ),
                  const Gap(FwSpacing.xs),
                  Text(
                    'cut off',
                    style: context.type.caption.copyWith(color: colors.mut),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepFrameButton extends StatelessWidget {
  const _StepFrameButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Tappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.xs),
          child: Icon(
            icon,
            size: FwIconSize.lg,
            color: onTap == null ? colors.mut3 : colors.mut,
          ),
        ),
      ),
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
    required this.focusOrder,
    required this.focusNodes,
  });

  final InspectTree? tree;
  final ValueNotifier<String?> highlight;
  final ValueNotifier<SemanticsSnapshotNode?> semanticsHighlight;
  final ValueNotifier<bool> picking;
  final ValueChanged<String> onPick;

  /// The Semantics tab's reading-order switch.
  final ValueNotifier<bool> focusOrder;

  /// The utterances to number when the switch is on, in reading order — null
  /// while another tab is showing, which is what keeps the discs from
  /// outliving the toggle that controls them.
  final List<SemanticsSnapshotNode>? focusNodes;

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

    // The reading-order discs sit under the highlight rectangle, so hovering
    // a row still points at one box even while the whole order is numbered.
    var layered = ValueListenableBuilder(
      valueListenable: focusOrder,
      builder: (context, numbered, child) {
        var nodes = focusNodes;
        if (!numbered || nodes == null || nodes.isEmpty) return child!;
        var colors = context.colors;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: FocusOrderPainter(
                rects: [for (var node in nodes) node.rect],
                color: colors.accent,
                onColor: colors.onPrimary,
                haloColor: colors.bg,
              ),
            ),
            child!,
          ],
        );
      },
      child: box,
    );

    return ValueListenableBuilder(
      valueListenable: picking,
      builder: (context, on, _) {
        if (!on) return IgnorePointer(child: layered);
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
          child: layered,
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
              Icon(
                Icons.arrow_back_ios,
                size: FwIconSize.xs,
                color: colors.mut,
              ),
            Text(
              '${step.index} · ${scenarioStepLabel(step)}',
              style: context.type.caption.copyWith(
                color: scenarioStepTone(context, step),
              ),
            ),
            if (isNext)
              Icon(
                Icons.arrow_forward_ios,
                size: FwIconSize.xs,
                color: colors.mut,
              ),
          ],
        ),
      ),
    );
  }
}
