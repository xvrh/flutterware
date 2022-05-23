import 'dart:async';
import 'dart:math';
import 'package:built_collection/built_collection.dart';
import '../utils/router_outlet.dart';
import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart' hide InteractiveViewer;
import 'package:flutter/services.dart';
import '../ui.dart';
import '../utils/assets.dart';
import '../utils/graphite.dart';
import 'app_connected.dart';
import 'detail.dart';
import 'protocol/api.dart';
import 'protocol/run.dart';
import 'screens/screens.dart';
import 'service.dart';
import 'toolbar.dart';
import 'ui/collapse_button.dart';
import 'ui/interactive_viewer.dart';

class RunView extends StatefulWidget {
  final ScenarioService service;
  final ScenarioApi client;
  final BuiltList<String> scenarioName;

  RunView(this.service, this.client, this.scenarioName)
      : super(key: Key(scenarioName.join('-')));

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
        widget.scenarioName,
        device: toolbar.device,
        language: toolbar.language,
        accessibility: toolbar.accessibility,
        imageRatio: 1.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var run = _runReference;
    var isInDetail = context.router.path.remaining.toString().isNotEmpty;
    return StreamBuilder<ScenarioRun>(
      stream: run.onUpdated,
      initialData: run.value,
      builder: (context, snapshot) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ProjectView.of(context).header.setScreen(null);
          ProjectView.of(context).header.setRun(null);
        });

        var toolbarScope = ToolBarScope.of(context);
        var project = toolbarScope.widget.project;

        Widget contentWidget;
        if (snapshot.hasError) {
          contentWidget = ErrorWidget(snapshot.error!);
        } else if (!snapshot.hasData) {
          contentWidget = Container();
        } else {
          var run = snapshot.requireData;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ProjectView.of(context).header.setRun(run);
          });
          if (toolbarScope.isCollapsed) {
            run = run.collapse();
          }
          contentWidget = RouterOutlet({
            '': (_) => _FlowMaster(this, run),
            'detail/:screen': (detail) =>
                DetailPage(widget.service, project, run, detail['screen']),
          });
        }
        var isCompleted = snapshot.data?.isCompleted ?? false;
        var result = snapshot.data?.result;

        return RunToolbar(
          project: project,
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

  void _setCollapsed(bool value) {
    setState(() {
      ToolBarScope.of(context).isCollapsed = value;
    });
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

class _FlowMaster extends StatelessWidget {
  final ScenarioRun run;
  final _RunViewState parent;

  const _FlowMaster(this.parent, this.run, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Container(
                color: Colors.black.withOpacity(0.02),
                child: _FlowGraph(parent.widget.service, run),
              ),
              Positioned(
                right: 5,
                top: 5,
                child: CollapseButton(
                  isCollapsed: ToolBarScope.of(context).isCollapsed,
                  onChanged: (v) {
                    parent._setCollapsed(v);
                  },
                ),
              ),
            ],
          ),
        ),
        Container(
          color: AppColors.separator,
          height: 1,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(run.scenario.description ?? ''),
        ),
      ],
    );
  }
}

class _FlowGraph extends StatefulWidget {
  final ScenarioService service;
  final ScenarioRun run;

  const _FlowGraph(this.service, this.run, {Key? key}) : super(key: key);

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
        .where((s) => !s.isCollapsed)
        .map((s) => NodeInput(
            id: s.id,
            next: s.next.map((n) {
              var target = screens[n.to];
              target ??= screens.values.firstWhere(
                  (e) => e.collapsedScreens.any((c) => c.id == n.to));
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
              widget.service,
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
        var pathName = widget.run.screens[to]!.pathName;
        if (pathName != null) {
          return EdgeTooltip(
            pathName,
            style: TextStyle(
                color: Colors.blueGrey.withOpacity(0.8), fontSize: 15),
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
  final ScenarioService service;
  final ScenarioRun run;
  final Screen screen;

  const _ScreenView(this.service, this.run, this.screen, {Key? key})
      : super(key: key);

  Widget? _widgetForScreen(Screen screen) {
    return widgetForScreen(run, screen, service: service);
  }

  @override
  Widget build(BuildContext context) {
    var main = _widgetForScreen(screen) ??
        Container(
          color: Colors.black12,
          width: run.args.device.width * run.args.device.pixelRatio,
          height: run.args.device.height * run.args.device.pixelRatio,
          alignment: Alignment.center,
          child: Text(screen.name),
        );

    var documentationKey = screen.documentationKey;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = min(3, screen.collapsedScreens.length); i > 0; i--)
          Transform.translate(
            offset: Offset(i * 8, i * 8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.blueGrey.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
              ),
              width: run.args.device.width * run.args.device.pixelRatio,
              height: run.args.device.height * run.args.device.pixelRatio,
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Opacity(
                  opacity: 0.5,
                  child: _widgetForScreen(
                          screen.collapsedScreens.elementAt(i - 1)) ??
                      Container(color: Colors.white),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
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
              child: Column(
                children: [
                  if (documentationKey != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          assets.images.confluence.path,
                          height: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          documentationKey,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: const Color(0xFF0052CC),
                          ),
                        ),
                      ],
                    ),
                  Text(
                    screen.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (screen.collapsedScreens.isNotEmpty)
          Positioned(
            bottom: 0,
            right: 10,
            child: FractionalTranslation(
              translation: Offset(0, 1),
              child: Row(
                children: [
                  Text(
                    '+ ${screen.collapsedScreens.length} screen${screen.collapsedScreens.length > 1 ? 's' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        height: 0.9,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                        backgroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
