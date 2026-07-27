import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../embedder/embedded_engine.dart';
import '../embedder/protocol.dart';
import '../ui/design/design.dart';
import 'catalog_entry.dart';
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
  late final AppLifecycleListener _lifecycle;

  CatalogSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    // Coming back to the window after editing elsewhere. `onResume` is
    // documented as "a view in the application gains input focus", which on
    // desktop is exactly the alt-tab back from the editor.
    _lifecycle = AppLifecycleListener(onResume: _reloadIfChanged);

    // And coming back to the *panel*: the shell rebuilds it from scratch when
    // you switch plugins, so a mount is the other half of the same signal.
    // After the frame, because this runs during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadIfChanged());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Cheap by construction: the daemon answers `unchanged` when nothing on disk
  /// moved, so this fires as often as it likes without touching the guest.
  void _reloadIfChanged() {
    if (mounted) unawaited(_session.reloadIfChanged());
  }

  void _maybeResize(EmbeddedEngine engine, Size size, double dpr) {
    if (size == _lastReportedSize) return;
    var width = (size.width * dpr).round();
    var height = (size.height * dpr).round();
    if (width < 1 || height < 1) return;
    _lastReportedSize = size;
    engine.resize(width, height, dpr);
  }

  /// True for the reload chord, which the canvas has to answer itself: its
  /// [Focus] forwards every key to the guest and reports it handled, so nothing
  /// above ever sees this one.
  bool _isReload(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.keyR &&
      (HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _reload,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _reload,
      },
      child: _buildBody(context),
    );
  }

  void _reload() {
    if (_session.phase == CatalogSessionPhase.ready) {
      unawaited(_session.reload());
    }
  }

  Widget _buildBody(BuildContext context) {
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
                    _StatusBar(session: _session, onReload: _reload),
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
        // The error goes where the widget would have been. The guest is still
        // rendering the last entry that loaded, and showing that under a
        // selection it does not belong to is how you end up wondering why your
        // edit did nothing.
        if (_session.selectedError case var error?) {
          return _CompileError(
            entry: _session.selected!,
            error: error,
            onRetry: _session.busyWith == null ? _reload : null,
          );
        }
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
            if (_isReload(event)) {
              if (event is KeyDownEvent) _reload();
              return KeyEventResult.handled;
            }
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
          // Hover is not a [Listener]'s business: with no button held the
          // engine sends `PointerHoverEvent`, which `onPointerMove` never
          // sees. Without this the demo is blind to the mouse unless you are
          // dragging — no ink highlight, no `MouseRegion`, no hover tooltip,
          // every demo frozen in its resting state.
          child: MouseRegion(
            onEnter: (e) => engine.sendPointer(
              phaseKind: PointerPhase.add,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
            ),
            onHover: (e) => engine.sendPointer(
              phaseKind: PointerPhase.hover,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
            ),
            // Paired with the add: the guest is tracking a device that has
            // left the window, and a hover state left behind never lifts.
            onExit: (e) => engine.sendPointer(
              phaseKind: PointerPhase.remove,
              x: e.localPosition.dx * dpr,
              y: e.localPosition.dy * dpr,
            ),
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
    var error = context.colors.red;
    return ListView(
      // One list, in discovery's order. A demo that stops compiling is marked
      // where it sits rather than moved to a section of its own: it is still
      // selectable — selecting it is how you retry it — and a typo should not
      // cost you your place in the tree.
      children: [
        for (var entry in session.allEntries)
          _EntryTile(
            entry: entry,
            broken: session.compileErrorFor(entry),
            selected: entry.id == session.selected?.id,
            errorColor: error,
            onTap: ready ? () => session.switchTo(entry) : null,
          ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.broken,
    required this.selected,
    required this.errorColor,
    required this.onTap,
  });

  final CatalogEntry entry;

  /// The compiler's complaint, or null when the entry builds.
  final String? broken;
  final bool selected;
  final Color errorColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      enabled: onTap != null,
      // Selection has to be the tile, not the title: the titles carry explicit
      // colours — red for broken — which a `selectedColor` would not override.
      selectedTileColor: context.colors.accentSoft,
      // Trailing, so that marking one entry does not indent every other one
      // and leave the list with a ragged left edge.
      trailing: broken == null
          ? null
          : Icon(Icons.error_outline, size: 16, color: errorColor),
      title: Text(
        entry.name,
        style: broken == null
            ? context.type.body
            : context.type.body.copyWith(color: errorColor),
      ),
      subtitle: Text(
        broken?.split('\n').first ?? entry.symbol,
        style: context.type.caption,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

/// Why the selected entry is not on screen, where it would have been.
///
/// Deliberately not a red page. The compiler's own words are the content, and
/// they are long, dense and monospaced: they need a calm surface and real
/// contrast, not a wash that fights them.
class _CompileError extends StatelessWidget {
  const _CompileError({
    required this.entry,
    required this.error,
    required this.onRetry,
  });

  final CatalogEntry entry;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return ColoredBox(
      color: colors.bg,
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.error_outline, size: 18, color: colors.red),
                ),
                const Gap(FwSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.name} doesn’t compile',
                        style: context.type.bodyStrong.copyWith(
                          color: colors.red,
                        ),
                      ),
                      const Gap(FwSpacing.xxs),
                      // Where to go and fix it.
                      Text(
                        '${entry.path} · ${entry.symbol}',
                        style: context.type.caption,
                      ),
                    ],
                  ),
                ),
                const Gap(FwSpacing.lg),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
            const Gap(FwSpacing.lg),
            // Loose, not expanded: the block is as tall as the diagnostic and
            // no taller. Five lines of error stretched down a 900px panel
            // reads as an empty page with a caption.
            Flexible(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.panel,
                  border: Border.all(color: colors.line),
                  borderRadius: BorderRadius.circular(context.radii.radius),
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(FwSpacing.lg),
                    // Horizontal too, and never wrapped: a diagnostic puts a
                    // caret line under the offending column, and a wrapped line
                    // points the caret at the wrong character.
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        error,
                        style: context.type.caption.copyWith(
                          fontFamily: 'monospace',
                          color: colors.ink2,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.session, required this.onReload});

  final CatalogSession session;
  final VoidCallback onReload;

  /// Right-aligned in a fixed column, so a number that gains a digit pushes
  /// nothing along with it.
  static String _ms(Duration d) => '${'${d.inMilliseconds}'.padLeft(4)}ms';

  @override
  Widget build(BuildContext context) {
    var parts = <String>[];
    if (session.coldCompile case var cold?) parts.add('cold ${_ms(cold)}');
    if (session.lastSwitch case var report?) {
      parts.add(
        report.ok
            ? '${report.entry.name}: compile ${_ms(report.compile)} '
                  '· reload ${_ms(report.reload)} '
                  // What the reload was *made of*: edited files on a reload,
                  // added libraries on a first visit. Both are zero when the
                  // guest is showing what it already had.
                  '· ${report.reloaded ? '${report.editedCount} edited' : '+${report.newSourceCount} libs'}'
            : '${report.entry.name}: did not compile',
      );
    }
    var failed = session.lastSwitch?.ok == false;
    var ready = session.phase == CatalogSessionPhase.ready;
    var busy = session.busyWith;
    var colors = context.colors;
    var mono = context.type.caption.copyWith(fontFamily: 'monospace');
    return Container(
      // No red bar. A failure has a whole panel explaining it now, and a status
      // line that changes colour as well as content is one more thing moving.
      color: colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
      // Every slot below is fixed, and the bar with them. A row that reflows
      // each time the compiler is asked something is a row nobody can read
      // while it works — which is the only time it has anything to say.
      height: 32,
      child: Row(
        spacing: FwSpacing.lg,
        children: [
          Expanded(
            child: Text(
              parts.join('   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: failed ? mono.copyWith(color: colors.red) : mono,
            ),
          ),
          // Activity sits by the button that starts it, not in front of the
          // report — an empty slot at the head of the line reads as an indent.
          SizedBox(
            width: 76,
            child: Text(
              busy == null ? '' : '$busy…',
              textAlign: TextAlign.right,
              style: mono,
            ),
          ),
          SizedBox(
            width: 12,
            height: 12,
            child: busy == null
                ? null
                : CircularProgressIndicator(strokeWidth: 2, color: colors.mut2),
          ),
          IconButton(
            onPressed: ready && busy == null ? onReload : null,
            icon: const Icon(Icons.refresh, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Reload (${Platform.isMacOS ? '⌘R' : 'Ctrl+R'})',
          ),
        ],
      ),
    );
  }
}
