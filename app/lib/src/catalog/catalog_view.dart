import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../embedder/embedded_engine.dart';
import '../embedder/protocol.dart';
import 'catalog_session.dart';

/// The catalog loop: entries on the left, the live guest on the right.
/// Selecting an entry hot-reloads the running guest rather than restarting it.
///
/// Mounted by the `flutterware.ui_catalog` plugin as its panel, and by
/// `main_catalog_dev.dart` for working on the loop itself.
///
/// It **renders** a [CatalogSession]; it does not own one. The owner outlives
/// the widget, which is what lets a cold compile keep running — and keep
/// reporting into the sidebar — while you are looking at another plugin.
class CatalogView extends StatefulWidget {
  const CatalogView({super.key, required this.session});

  final CatalogSession session;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final FocusNode _focusNode = FocusNode();
  Size? _lastReportedSize;

  CatalogSession get _session => widget.session;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _maybeResize(EmbeddedEngine engine, Size size, double dpr) {
    if (size == _lastReportedSize) return;
    var width = (size.width * dpr).round();
    var height = (size.height * dpr).round();
    if (width < 1 || height < 1) return;
    _lastReportedSize = size;
    engine.resize(width, height, dpr);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: AnimatedBuilder(
        animation: _session,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 260, child: _EntryList(session: _session)),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildCanvas(context)),
                    const Divider(height: 1),
                    _StatusBar(session: _session),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    switch (_session.phase) {
      case CatalogSessionPhase.starting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              const CircularProgressIndicator(),
              Text(
                'Building the guest and compiling the first entry… '
                '${_session.busyFor.inSeconds}s',
              ),
            ],
          ),
        );
      case CatalogSessionPhase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: SelectableText(
                _session.errorMessage ?? 'unknown error',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        );
      case CatalogSessionPhase.ready:
        return _buildTexture(context, _session.engine!);
    }
  }

  Widget _buildTexture(BuildContext context, EmbeddedEngine engine) {
    var dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeResize(engine, constraints.biggest, dpr);
        });
        return Focus(
          focusNode: _focusNode,
          onKeyEvent: (node, event) {
            engine.sendKey(
              kind: event is KeyDownEvent
                  ? KeyEventKind.down
                  : event is KeyRepeatEvent
                  ? KeyEventKind.repeat
                  : KeyEventKind.up,
              physicalKey: event.physicalKey.usbHidUsage,
              logicalKey: event.logicalKey.keyId,
            );
            return KeyEventResult.handled;
          },
          child: Listener(
            onPointerDown: (e) {
              _focusNode.requestFocus();
              engine.sendPointer(
                phaseKind: PointerPhase.down,
                x: e.localPosition.dx * dpr,
                y: e.localPosition.dy * dpr,
                buttons: 1,
              );
            },
            onPointerMove: (e) => engine.sendPointer(
              phaseKind: PointerPhase.move,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
              buttons: 1,
            ),
            onPointerUp: (e) => engine.sendPointer(
              phaseKind: PointerPhase.up,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
            ),
            child: SizedBox.expand(
              child: engine.textureId == null
                  ? const SizedBox()
                  : Texture(textureId: engine.textureId!),
            ),
          ),
        );
      },
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    var ready = session.phase == CatalogSessionPhase.ready;
    return ListView(
      children: [
        for (var entry in session.entries)
          ListTile(
            dense: true,
            selected: entry.id == session.active?.id,
            enabled: ready,
            title: Text(entry.name),
            subtitle: Text(
              entry.symbol,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            onTap: ready ? () => session.switchTo(entry) : null,
          ),

        // Shown, not hidden. A demo you are midway through editing has not
        // disappeared, it just does not build yet, and the compiler already
        // said why.
        if (session.quarantined.isNotEmpty) ...[
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "DOESN'T COMPILE",
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          for (var broken in session.quarantined)
            ListTile(
              dense: true,
              title: Text(
                broken.entry.name,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(
                broken.error.split('\n').first,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(broken.entry.name),
                  content: SingleChildScrollView(
                    child: SelectableText(
                      broken.error,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    var parts = <String>[];
    // The word only. The timings that follow are measured, not guessed at from
    // a counter running while you read them.
    if (session.busyWith case var busy?) parts.add('$busy…');
    if (session.coldCompile case var cold?) {
      parts.add('cold ${cold.inMilliseconds}ms');
    }
    if (session.lastSwitch case var report?) {
      parts.add(
        report.ok
            ? '${report.entry.name}: compile ${report.compile.inMilliseconds}ms '
                  '· reload ${report.reload.inMilliseconds}ms '
                  '· +${report.newSourceCount} libs'
            : '${report.entry.name}: did not compile',
      );
    }
    var failed = session.lastSwitch?.ok == false;
    return Container(
      color: failed
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              parts.join('   '),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          if (failed)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Compile error'),
                  content: SingleChildScrollView(
                    child: SelectableText(
                      session.lastSwitch!.error ?? '',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Show error'),
            ),
        ],
      ),
    );
  }
}
