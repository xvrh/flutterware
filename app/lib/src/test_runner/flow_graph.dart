import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart' hide InteractiveViewer;
import 'package:flutter/services.dart';
import 'package:flutterware/internals/test_runner.dart';
import '../utils.dart';
import '../utils/graphite.dart';
import 'detail.dart';
import 'protocol/api.dart';
import 'protocol/run.dart';
import 'screenshot_frame.dart';
import 'toolbar.dart';
import 'ui/interactive_viewer.dart';
import 'ui/zoom.dart';

class RunView extends StatefulWidget {
  final TestRunnerApi client;
  final BuiltList<String> testName;
  final Widget? reloadToolbar;

  RunView(this.client, this.testName, {this.reloadToolbar})
      : super(key: Key(testName.join('-')));

  @override
  State<RunView> createState() => _RunViewState();
}

class _RunViewState extends State<RunView> {
  final _interactionController = TransformationController()
    ..value = ((Matrix4.identity() * 0.5 as Matrix4)..translate(50.0, 100.0));
  late RunReference _runReference;
  late StreamSubscription _reloadSubscription;

  @override
  void initState() {
    super.initState();
    _start();

    _reloadSubscription = widget.client.project.onReloaded.listen((_) {
      _refresh();
    });
  }

  void _refresh() {
    _runReference.dispose();
    setState(() {
      _start();
    });
  }

  void _start() {
    var toolbar = ToolBarScope.of(context).parameters;
    _runReference = widget.client.run.start(
      RunArgs(
        widget.testName,
        device: toolbar.device,
        locale: toolbar.locale,
        accessibility: toolbar.accessibility,
        imageRatio: 1.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var run = _runReference;
    var isInDetail = context.router.path.remaining.toString().isNotEmpty;
    return StreamBuilder<TestRun>(
      stream: run.onUpdated,
      initialData: run.value,
      builder: (context, snapshot) {
        var toolbarScope = ToolBarScope.of(context);

        Widget contentWidget;
        if (snapshot.hasError) {
          contentWidget = ErrorWidget(snapshot.error!);
        } else if (!snapshot.hasData) {
          contentWidget = Container();
        } else {
          var run = snapshot.requireData;
          contentWidget = RouterOutlet({
            '': (_) => _FlowMaster(this, run),
            'detail/:screen': (detail) => DetailPage(run, detail['screen']),
          });
        }
        var isCompleted = snapshot.data?.isCompleted ?? false;
        var result = snapshot.data?.result;

        var reloadToolbar = widget.reloadToolbar;
        return RunToolbar(
          supportedLocales: snapshot.data?.supportedLocales,
          initialParameters: toolbarScope.parameters,
          onChanged: (p) {
            var oldParameters = toolbarScope.parameters;
            toolbarScope.parameters = p;
            if (oldParameters.requiresFullRun(p)) {
              _refresh();
            } else {
              setState(() {
                // Will collapse run after rebuild
              });
            }
          },
          leadingActions: [
            if (isCompleted)
              if (isInDetail || reloadToolbar == null)
                ElevatedButton(
                  onPressed: () {
                    if (isInDetail) {
                      context.go('');
                    } else {
                      _refresh();
                    }
                  },
                  child: Icon(
                    isInDetail ? Icons.arrow_back : Icons.refresh,
                    size: 15,
                  ),
                )
              else
                reloadToolbar
            else
              ElevatedButton(
                onPressed: null,
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              )
          ],
          trailingActions: [if (result != null) ResultIcon(result)],
          child: contentWidget,
        );
      },
    );
  }

  @override
  void dispose() {
    _reloadSubscription.cancel();
    _runReference.dispose();
    super.dispose();
  }
}

class ResultIcon extends StatelessWidget {
  final RunResult result;

  const ResultIcon(this.result, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (result.success) {
      return Tooltip(
        message: '${result.duration}',
        child: Icon(
          Icons.check,
          color: Colors.green,
        ),
      );
    } else {
      return Tooltip(
        message: '${result.error}',
        child: Icon(
          Icons.error_outline,
          color: Colors.red,
        ),
      );
    }
  }
}

class _FlowMaster extends StatefulWidget {
  final TestRun run;
  final _RunViewState parent;

  const _FlowMaster(this.parent, this.run, {Key? key}) : super(key: key);

  @override
  State<_FlowMaster> createState() => _FlowMasterState();
}

class _FlowMasterState extends State<_FlowMaster> {
  late double _scale;

  @override
  void initState() {
    super.initState();
    widget.parent._interactionController.addListener(_onInteraction);
    _updateScale();
  }

  void _onInteraction() {
    setState(() {
      _updateScale();
    });
  }

  void _updateScale() {
    _scale = widget.parent._interactionController.value.getMaxScaleOnAxis();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _FlowGraph(widget.run),
        //TODO(xha): re-enable with a more powerful feature to filter tags
        //Positioned(
        //  right: 5,
        //  top: 5,
        //  child: CollapseButton(
        //    isCollapsed: ToolBarScope.of(context).isCollapsed,
        //    onChanged: (v) {
        //      parent._setCollapsed(v);
        //    },
        //  ),
        //),
        Positioned(
          right: 5,
          bottom: 5,
          child: ZoomButtons(
            value: _scale,
            onScale: (v) {
              widget.parent._interactionController.value =
                  widget.parent._interactionController.value.scaled(v);
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.parent._interactionController.removeListener(_onInteraction);
    super.dispose();
  }
}

class _FlowGraph extends StatefulWidget {
  final TestRun run;

  const _FlowGraph(this.run, {Key? key}) : super(key: key);

  @override
  __FlowGraphState createState() => __FlowGraphState();
}

class __FlowGraphState extends State<_FlowGraph> {
  late List<NodeInput> _inputs;
  bool _isZoomKeyPressed = false;

  @override
  void initState() {
    super.initState();
    _fillInput();
    RawKeyboard.instance.addListener(_onKeyPressed);
  }

  void _onKeyPressed(RawKeyEvent event) {
    var zoomKeyPressed = event.isControlPressed || event.isMetaPressed;
    if (_isZoomKeyPressed != zoomKeyPressed) {
      setState(() {
        _isZoomKeyPressed = zoomKeyPressed;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _FlowGraph oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.run != widget.run) {
      _fillInput();
    }
  }

  void _fillInput() {
    var screens = widget.run.screens;
    _inputs = screens.values
        .map((s) => NodeInput(
            id: s.id,
            next: s.next.map((n) {
              var target = screens[n.to]!;
              return target.id;
            }).toList()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    const emptyNode = '--';
    var inputs = _inputs;
    if (inputs.isEmpty) {
      inputs = [NodeInput(id: emptyNode, next: [])];
    }

    var parentState = context.findAncestorStateOfType<_RunViewState>()!;

    return DirectGraph(
      list: inputs,
      cellSize: Size(widget.run.args.device.width * widget.run.args.imageRatio,
          widget.run.args.device.height * widget.run.args.imageRatio),
      cellPadding: 90.0,
      contactEdgesDistance: 0,
      tipLength: 20,
      orientation: MatrixOrientation.horizontal,
      interactiveBuilder: (context, child) {
        return InteractiveViewer(
          transformationController: parentState._interactionController,
          scrollControls: _isZoomKeyPressed
              ? InteractiveViewerScrollControls.scrollScales
              : InteractiveViewerScrollControls.scrollPans,
          maxScale: 1.5,
          minScale: 0.1,
          constrained: false,
          boundaryMargin: EdgeInsets.all(5000),
          child: child,
        );
      },
      builder: (ctx, node) {
        if (node.id == emptyNode) return const SizedBox();

        var screen = widget.run.screens[node.id]!;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              var screen = widget.run.screens[node.id]!;
              context.go('detail/${screen.id}');
            },
            child: _ScreenView(
              widget.run,
              screen,
              key: Key(node.id),
            ),
          ),
        );
      },
      paintBuilder: (edge) {
        var p = Paint()
          ..color = Colors.blueGrey
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5;
        return p;
      },
      edgeTooltip: (from, to) {
        var splitName = widget.run.screens[to]!.splitName;
        if (splitName != null) {
          return EdgeTooltip(
            splitName,
            style: TextStyle(
              color: Colors.blueGrey.withOpacity(0.8),
              fontSize: 15,
            ),
          );
        }
        return null;
      },
    );
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_onKeyPressed);
    super.dispose();
  }
}

class _ScreenView extends StatelessWidget {
  final TestRun run;
  final Screen screen;

  const _ScreenView(this.run, this.screen, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var main = ScreenshotFrame(screen, run.args);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: Colors.blueGrey, width: 2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: main,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FractionalTranslation(
            translation: Offset(0, -1),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Text(
                screen.name,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, color: Colors.black54),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
