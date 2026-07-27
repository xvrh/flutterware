import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../embedder/embedded_engine.dart';
import '../embedder/protocol.dart';
import '../ui/design/design.dart';
import 'catalog_entry.dart';
import 'catalog_session.dart';
import 'catalog_tree.dart';

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
              if (_session.browsing.listVisible)
                SizedBox(width: 260, child: _EntryList(session: _session))
              else
                _ShowListStrip(browsing: _session.browsing),
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

/// The entry browser: a filter, then the tree.
class _EntryList extends StatelessWidget {
  const _EntryList({required this.session});

  final CatalogSession session;

  @override
  Widget build(BuildContext context) {
    var browsing = session.browsing;
    // Built from everything discovered, broken included: an entry you are
    // midway through fixing keeps its place, and selecting it is the retry.
    var tree = filterCatalogTree(
      buildCatalogTree(session.allEntries),
      browsing.filter,
    );
    var filtering = browsing.filter.trim().isNotEmpty;
    // Whatever is selected is visible, whatever was folded away before it was.
    var reveal = branchesTo(tree, session.selected?.id);
    var rows = <Widget>[];
    void walk(List<CatalogNode> nodes, int depth) {
      for (var node in nodes) {
        switch (node) {
          case CatalogLeaf(:var entry):
            rows.add(
              _LeafRow(
                entry: entry,
                depth: depth,
                broken: session.compileErrorFor(entry),
                selected: entry.id == session.selected?.id,
                highlight: browsing.filter.trim(),
                onTap: session.phase == CatalogSessionPhase.ready
                    ? () => session.switchTo(entry)
                    : null,
              ),
            );
          case CatalogBranch(:var children):
            // A filtered tree is already the answer to a question; folding
            // part of it away would only hide what was asked for.
            var open =
                filtering ||
                reveal.contains(node.id) ||
                browsing.isOpen(node.id);
            rows.add(
              _BranchRow(
                branch: node,
                depth: depth,
                open: open,
                highlight: browsing.filter.trim(),
                onTap: filtering ? null : () => browsing.toggle(node.id),
              ),
            );
            if (open) walk(children, depth + 1);
        }
      }
    }

    walk(tree, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterField(browsing: browsing, tree: tree),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    filtering ? 'Nothing matches' : 'No entries',
                    style: context.type.caption,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
                  children: rows,
                ),
        ),
      ],
    );
  }
}

/// Indent for [depth], plus the width a branch spends on its chevron so that
/// leaves and folders at the same level start at the same place.
EdgeInsets _rowPadding(int depth) =>
    EdgeInsets.only(left: FwSpacing.md + depth * 14.0, right: FwSpacing.md);

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.depth,
    required this.open,
    required this.highlight,
    required this.onTap,
  });

  final CatalogBranch branch;
  final int depth;
  final bool open;

  /// What the filter is showing this row for, marked in the label.
  final String highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: _rowPadding(depth),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: colors.mut,
              ),
              const Gap(FwSpacing.xs),
              Expanded(
                child: _Marked(
                  text: branch.label,
                  mark: highlight,
                  style: context.type.caption.copyWith(color: colors.ink2),
                ),
              ),
              if (!open) ...[
                const Gap(FwSpacing.xs),
                Text(
                  '${branch.entries.length}',
                  style: context.type.micro.copyWith(color: colors.mut2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeafRow extends StatelessWidget {
  const _LeafRow({
    required this.entry,
    required this.depth,
    required this.broken,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  final CatalogEntry entry;
  final int depth;

  /// What the filter is showing this row for, marked in the name.
  final String highlight;

  /// The compiler's complaint, or null when the entry builds.
  final String? broken;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = broken != null ? colors.red : colors.ink;
    return Tooltip(
      // One line per entry leaves no room for the file, and the file is often
      // what you remember it by.
      message: '${entry.path} · ${entry.symbol}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected ? colors.accentSoft : null,
          padding: _rowPadding(depth),
          child: SizedBox(
            height: 26,
            child: Row(
              children: [
                // The chevron column a branch occupies, so a leaf beside a
                // folder is indented to match rather than sitting under it.
                const SizedBox(width: 14 + FwSpacing.xs),
                Expanded(
                  child: _Marked(
                    text: entry.name,
                    mark: highlight,
                    style: context.type.bodySmall.copyWith(color: color),
                  ),
                ),
                if (broken != null) ...[
                  const Gap(FwSpacing.xs),
                  Icon(Icons.error_outline, size: 14, color: colors.red),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [text], with every occurrence of [mark] struck through with a highlighter.
///
/// A filtered list otherwise makes you find, in every row, the thing you just
/// typed. A row with no mark on it has answered too: it matched on its file or
/// its symbol, neither of which fits on the row.
class _Marked extends StatelessWidget {
  const _Marked({required this.text, required this.mark, required this.style});

  final String text;
  final String mark;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    var haystack = text.toLowerCase();
    var needle = mark.toLowerCase();
    if (needle.isEmpty || !haystack.contains(needle)) {
      return Text(text, overflow: TextOverflow.ellipsis, style: style);
    }

    var marked = style.copyWith(
      // Amber rather than a raw yellow, and see-through, so it reads as a
      // highlighter over the row instead of a second background colour.
      backgroundColor: context.colors.amber.withValues(alpha: 0.35),
      color: context.colors.ink,
    );
    var spans = <TextSpan>[];
    var at = 0;
    while (true) {
      var found = haystack.indexOf(needle, at);
      if (found < 0) {
        spans.add(TextSpan(text: text.substring(at)));
        break;
      }
      if (found > at) spans.add(TextSpan(text: text.substring(at, found)));
      at = found + needle.length;
      spans.add(TextSpan(text: text.substring(found, at), style: marked));
    }
    return Text.rich(
      TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _FilterField extends StatefulWidget {
  const _FilterField({required this.browsing, required this.tree});

  final CatalogBrowsing browsing;

  /// What "collapse all" would have to name.
  final List<CatalogNode> tree;

  @override
  State<_FilterField> createState() => _FilterFieldState();
}

/// One size for both of the field's icon slots, filled or not.
const _iconSlot = BoxConstraints.tightFor(width: 24, height: 22);

/// Says work is happening, but only once that is news.
///
/// A switch is 90ms. Anything that appears and disappears inside that is a
/// flash on every click, which reads as a fault rather than as progress — so
/// the dot waits out the common case and fades in only for the work you would
/// otherwise wonder about. Its slot is always there, so nothing moves either
/// way.
class BusyDot extends StatefulWidget {
  const BusyDot({super.key, required this.busy});

  /// What the session is doing, or null when it is idle.
  final String? busy;

  /// Longer than a warm switch, shorter than a wait you would question.
  static const appearsAfter = Duration(milliseconds: 250);

  @override
  State<BusyDot> createState() => _BusyDotState();
}

class _BusyDotState extends State<BusyDot> {
  Timer? _timer;
  var _shown = false;

  @override
  void didUpdateWidget(BusyDot old) {
    super.didUpdateWidget(old);
    if (widget.busy == old.busy) return;
    _timer?.cancel();
    if (widget.busy == null) {
      setState(() => _shown = false);
    } else {
      _timer = Timer(BusyDot.appearsAfter, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var dot = AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
    return SizedBox(
      width: 8,
      height: 8,
      child: widget.busy == null
          ? dot
          : Tooltip(message: widget.busy!, child: dot),
    );
  }
}

class _FilterFieldState extends State<_FilterField> {
  late final _controller = TextEditingController(
    // Seeded rather than empty: the panel is rebuilt from scratch every time
    // you come back to it, and a filter that clears itself is a filter you
    // stop trusting.
    text: widget.browsing.filter,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(FwSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _controller,
                style: context.type.caption.copyWith(color: colors.ink),
                onChanged: (value) => widget.browsing.filter = value,
                decoration: InputDecoration(
                  hintText: 'Filter',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.md,
                  ),
                  prefixIcon: Icon(Icons.search, size: 14, color: colors.mut2),
                  // Both slots are the same size whether or not they hold
                  // anything. An `InputDecorator` sizes itself around its
                  // icons, so a clear button that comes and goes with the text
                  // takes the field's height with it.
                  prefixIconConstraints: _iconSlot,
                  suffixIconConstraints: _iconSlot,
                  suffixIcon: _controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: Icon(Icons.close, size: 14, color: colors.mut2),
                          padding: EdgeInsets.zero,
                          constraints: _iconSlot,
                          onPressed: () {
                            _controller.clear();
                            widget.browsing.filter = '';
                          },
                        ),
                ),
              ),
            ),
          ),
          const Gap(FwSpacing.xs),
          // One button for both directions: with nothing folded away the only
          // useful thing it can do is fold, and after that, unfold.
          IconButton(
            icon: Icon(
              widget.browsing.anyClosed ? Icons.unfold_more : Icons.unfold_less,
              size: 16,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: widget.browsing.anyClosed ? 'Expand all' : 'Collapse all',
            onPressed: () => widget.browsing.anyClosed
                ? widget.browsing.openAll()
                : widget.browsing.closeAll(allBranches(widget.tree)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Hide the list',
            onPressed: () => widget.browsing.listVisible = false,
          ),
        ],
      ),
    );
  }
}

/// All that is left of the list when it is hidden: the way back.
class _ShowListStrip extends StatelessWidget {
  const _ShowListStrip({required this.browsing});

  final CatalogBrowsing browsing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: FwSpacing.md),
          child: IconButton(
            icon: const Icon(Icons.chevron_right, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: 'Show the list',
            onPressed: () => browsing.listVisible = true,
          ),
        ),
      ),
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
          BusyDot(busy: busy),
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
