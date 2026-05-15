import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'embedded_engine.dart';
import 'protocol.dart';

/// A standalone dev harness that runs the embedder guest and shows its live
/// output in an external texture.
class EmbedderHarnessScreen extends StatefulWidget {
  const EmbedderHarnessScreen({
    super.key,
    required this.appPackageRoot,
    required this.flutterSdkRoot,
  });

  final String appPackageRoot;
  final String flutterSdkRoot;

  @override
  State<EmbedderHarnessScreen> createState() => _EmbedderHarnessScreenState();
}

class _EmbedderHarnessScreenState extends State<EmbedderHarnessScreen> {
  late final EmbeddedEngine _engine = EmbeddedEngine(
    appPackageRoot: widget.appPackageRoot,
    flutterSdkRoot: widget.flutterSdkRoot,
  );
  final FocusNode _focusNode = FocusNode();
  Size? _lastReportedSize;

  @override
  void initState() {
    super.initState();
    _engine.start();
  }

  @override
  void dispose() {
    _engine.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _maybeResize(Size size, double dpr) {
    if (size == _lastReportedSize) return;
    var width = (size.width * dpr).round();
    var height = (size.height * dpr).round();
    if (width < 1 || height < 1) return;
    _lastReportedSize = size;
    _engine.resize(width, height, dpr);
  }

  void _sendPointer(PointerPhase phase, Offset local, double dpr,
      {int buttons = 0}) {
    _engine.sendPointer(
      phaseKind: phase,
      x: local.dx * dpr,
      y: local.dy * dpr,
      buttons: buttons,
    );
  }

  @override
  Widget build(BuildContext context) {
    var dpr = MediaQuery.of(context).devicePixelRatio;
    return Scaffold(
      appBar: AppBar(title: const Text('Embedder harness')),
      body: AnimatedBuilder(
        animation: _engine,
        builder: (context, _) {
          switch (_engine.phase) {
            case EmbeddedEnginePhase.building:
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Building and starting the embedder guest…'),
                  ],
                ),
              );
            case EmbeddedEnginePhase.error:
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Embedder error:\n${_engine.errorMessage}',
                      style: const TextStyle(color: Colors.red)),
                ),
              );
            case EmbeddedEnginePhase.running:
              return LayoutBuilder(
                builder: (context, constraints) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _maybeResize(constraints.biggest, dpr);
                  });
                  return Focus(
                    focusNode: _focusNode,
                    onKeyEvent: (node, event) {
                      var kind = event is KeyDownEvent
                          ? KeyEventKind.down
                          : event is KeyRepeatEvent
                              ? KeyEventKind.repeat
                              : KeyEventKind.up;
                      _engine.sendKey(
                        kind: kind,
                        physicalKey: event.physicalKey.usbHidUsage,
                        logicalKey: event.logicalKey.keyId,
                      );
                      return KeyEventResult.handled;
                    },
                    child: Listener(
                      onPointerDown: (e) {
                        _focusNode.requestFocus();
                        _sendPointer(PointerPhase.down, e.localPosition, dpr,
                            buttons: 1);
                      },
                      onPointerMove: (e) => _sendPointer(
                          PointerPhase.move, e.localPosition, dpr,
                          buttons: 1),
                      onPointerHover: (e) => _sendPointer(
                          PointerPhase.hover, e.localPosition, dpr),
                      onPointerUp: (e) =>
                          _sendPointer(PointerPhase.up, e.localPosition, dpr),
                      child: SizedBox.expand(
                        child: _engine.textureId == null
                            ? const SizedBox()
                            : Texture(textureId: _engine.textureId!),
                      ),
                    ),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
