import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../../ui/tree_row.dart';
import '../editor.dart';
import 'inline_name.dart';
import 'param_pane.dart';
import 'tokens_host.dart';

/// The rest of what the file declares, under the layers: its parameters and
/// its motions, each a section with a count and its own `+`.
///
/// A click OPENS a row in the drawer under the canvas — a motion's
/// timeline, a parameter's pane or table — and the open one is the
/// highlighted one. One verb, because the drawer is independent of the node
/// selection: it stays put while nodes are clicked on the canvas to key
/// them, so there was nothing a separate "select" had to protect. Rename in
/// place with a double-click on the name; right-click for the rest.
class SceneOutlineSections extends StatefulWidget {
  const SceneOutlineSections(
    this.editor, {
    super.key,
    this.sceneClassName,
    this.onOpenMotion,
    this.onOpenParam,
    this.onOpenToken,
    this.onOpenLibrary,
    this.tokens,
  });

  final SceneEditor editor;

  /// Opens a token below the canvas.
  final ValueChanged<String>? onOpenToken;

  /// Opens a library, by path — its divider in the tokens section is the
  /// row, and the drawer shows its modes. Null: the editor's own door.
  final ValueChanged<String>? onOpenLibrary;

  /// The group's libraries and the doors past this file; null hides the
  /// Tokens section's `+` and makes rename and delete local.
  final SceneTokensHost? tokens;

  /// What a new motion animates; null hides the motions' `+`.
  final String? sceneClassName;

  /// Opens a motion's timeline — the workspace's door, which also starts
  /// its playback.
  final ValueChanged<String>? onOpenMotion;

  /// Opens a parameter below the canvas.
  final ValueChanged<String>? onOpenParam;

  @override
  State<SceneOutlineSections> createState() => _SceneOutlineSectionsState();
}

class _SceneOutlineSectionsState extends State<SceneOutlineSections> {
  SceneEditor get editor => widget.editor;
  SceneDocument get doc => editor.doc;

  var _paramsOpen = true;
  var _motionsOpen = true;
  var _tokensOpen = true;

  /// The libraries folded away, by path; the app's exports by [_exportsKey].
  final _folded = <String>{};

  /// The row being renamed in place, if any.
  SceneAside? _renaming;

  /// The last row tapped and when: a second tap on it within the double-tap
  /// window renames. Detected by hand rather than with a double-tap
  /// recognizer, which would hold every single tap for 300ms — selection
  /// has to be instant. The same rule as the layers above.
  (SceneAside, DateTime)? _lastTap;

  @override
  Widget build(BuildContext context) {
    var params = doc.params;
    var motions = editor.motions.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _section(
          context,
          'Parameters',
          params.length,
          open: _paramsOpen,
          onToggle: () => setState(() => _paramsOpen = !_paramsOpen),
          onAdd: (at) => _addParamMenu(context, at),
        ),
        if (_paramsOpen)
          for (var p in params) _paramRow(context, p),
        _section(
          context,
          'Motions',
          motions.length,
          open: _motionsOpen,
          onToggle: () => setState(() => _motionsOpen = !_motionsOpen),
          onAdd: widget.sceneClassName == null
              ? null
              : (_) => _open(editor.addMotion(widget.sceneClassName!)),
        ),
        if (_motionsOpen)
          for (var name in motions) _motionRow(context, name),
        ..._tokensSection(context),
        const SizedBox(height: FwSpacing.sm),
      ],
    );
  }

  /// The group's tokens: one branch per library the group lists, with the
  /// tokens it declares under it, then the app's exports. Package-wide, so
  /// every scene of the group shows the same section. A library's row
  /// opens the library in the drawer; its chevron folds it.
  List<Widget> _tokensSection(BuildContext context) {
    var host = widget.tokens;
    var exports = [
      for (var t in doc.tokens)
        if (t.isExport) t,
    ];
    var count = doc.tokens.length;
    return [
      _section(
        context,
        'Tokens',
        count,
        open: _tokensOpen,
        onToggle: () => setState(() => _tokensOpen = !_tokensOpen),
        onAdd: host == null ? null : (at) => _addTokenMenu(context, at, null),
      ),
      if (_tokensOpen) ...[
        if (host != null)
          for (var library in host.libraries) ...[
            _branch(
              context,
              label: library.symbol,
              icon: Icons.style_outlined,
              facts: '${library.tokens.length}',
              tooltip: [
                library.fileName,
                if (library.modes.isNotEmpty)
                  'modes: ${library.modes.join(', ')}'
                else
                  'no modes yet',
                'click for its modes and its design file',
              ].join(' · '),
              open: !_folded.contains(library.path),
              onToggle: () => setState(() {
                if (!_folded.remove(library.path)) _folded.add(library.path);
              }),
              selected: editor.drawer == LibraryAside(library.path),
              onOpen: () => _openLibrary(library.path),
              onAdd: (at) => _addTokenMenu(context, at, library.path),
              addTooltip: 'New token in ${library.symbol}',
            ),
            if (!_folded.contains(library.path))
              for (var t in library.tokens) _tokenRow(context, t),
          ],
        if (exports.isNotEmpty) ...[
          _branch(
            context,
            label: 'from the app',
            icon: Icons.ios_share_outlined,
            facts: '${exports.length}',
            tooltip: "The group's exports — the app's own values, by name",
            open: !_folded.contains(_exportsKey),
            onToggle: () => setState(() {
              if (!_folded.remove(_exportsKey)) _folded.add(_exportsKey);
            }),
          ),
          if (!_folded.contains(_exportsKey))
            for (var t in exports) _tokenRow(context, t),
        ],
        if (host != null && host.libraries.isEmpty && exports.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.md + FwSpacing.xl,
              FwSpacing.xxs,
              FwSpacing.sm,
              FwSpacing.xs,
            ),
            child: Text(
              'No library yet — + starts one for this group.',
              style: context.type.micro.copyWith(color: context.colors.mut2),
            ),
          ),
      ],
    ];
  }

  static const _exportsKey = '<exports>';

  /// A branch one level under a section — a library, the app's exports —
  /// drawn as the layers above draw a frame: the chevron folds, the row
  /// selects (opens the library), and the `+` at its end adds under it.
  Widget _branch(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String facts,
    required String tooltip,
    required bool open,
    required VoidCallback onToggle,
    bool selected = false,
    VoidCallback? onOpen,
    void Function(Offset at)? onAdd,
    String? addTooltip,
  }) {
    var colors = context.colors;
    return FwTreeRow(
      depth: 1,
      density: TreeRowDensity.roomy,
      selected: selected,
      open: open,
      onToggleFold: onToggle,
      onTap: onOpen,
      label: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: Row(
          spacing: FwSpacing.sm,
          children: [
            Icon(
              icon,
              size: FwIconSize.sm,
              color: selected ? colors.accentDark : colors.mut,
            ),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.type.body.copyWith(
                  color: selected ? colors.accentDark : colors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: [
        Text(facts, style: context.type.caption.copyWith(color: colors.mut2)),
        if (onAdd != null) _addButton(context, addTooltip ?? 'New', onAdd),
      ],
    );
  }

  /// The `+` at a row's end: a real target, not a bare glyph — hover wash,
  /// a click-sized box — sized so the thumb of the scrollbar beside it
  /// does not take the click.
  Widget _addButton(
    BuildContext context,
    String tooltip,
    void Function(Offset at) onAdd,
  ) {
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (context) => Tappable(
          onTap: () {
            var box = context.findRenderObject()! as RenderBox;
            onAdd(box.localToGlobal(Offset(0, box.size.height)));
          },
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.all(FwSpacing.xs),
            child: Icon(
              Icons.add,
              size: FwIconSize.sm,
              color: context.colors.mut,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tokenRow(BuildContext context, SceneTokenDecl t) {
    var aside = TokenAside(t.name);
    var host = widget.tokens;
    // A colour is its swatch here, the way the layers show theirs: the
    // hex is in the tooltip, and the name keeps its room.
    var swatch = switch (t.value) {
      SceneColor c when !t.isExport => c,
      _ => null,
    };
    return _row(
      context,
      aside,
      depth: 2,
      icon: tokenIcon(t),
      name: t.name,
      trailing: swatch == null ? tokenValueLabel(t) : '',
      swatch: swatch,
      tooltip: tokenFacts(editor, host, t.name),
      onOpen: () => _openToken(t.name),
      menu: () => tokenMenu(
        editor,
        host,
        t.name,
        onRename: () => setState(() => _renaming = aside),
      ),
      rename: (wanted) {
        if (host?.rename case var rename?) {
          rename(t.name, wanted);
        } else if (host != null) {
          host.renameHere(editor, t.name, wanted);
        } else {
          throw ArgumentError('no library open to rename in');
        }
      },
    );
  }

  void _openToken(String name) {
    if (widget.onOpenToken case var open?) {
      open(name);
    } else {
      editor.openToken = name;
    }
  }

  void _openLibrary(String path) {
    if (widget.onOpenLibrary case var open?) {
      open(path);
    } else {
      editor.openLibrary = path;
    }
  }

  /// `+` on the section, or on one library's divider: a token of a kind,
  /// or a style, in that library — the first one when the section's own
  /// `+` was pressed — and, from the section, a new library.
  void _addTokenMenu(BuildContext context, Offset at, String? libraryPath) {
    var host = widget.tokens;
    if (host == null) return;
    var library = libraryPath == null
        ? host.libraries.firstOrNull
        : host.libraries.where((l) => l.path == libraryPath).firstOrNull;
    showContextMenu(context, at, [
      if (library != null)
        ...newTokenEntries(
          editor,
          host,
          library,
          onAdded: (name) {
            _openToken(name);
            setState(() {
              _tokensOpen = true;
              _renaming = TokenAside(name);
            });
          },
        ),
      if (libraryPath == null && host.onNewLibrary != null) ...[
        if (library != null) const MenuDivider(),
        MenuItem(
          'New library',
          icon: Icons.library_add_outlined,
          shortcut: 'in this folder',
          onSelected: host.onNewLibrary,
        ),
      ],
    ]);
  }

  /// A section's line: a branch at the root of this outline, drawn as the
  /// layers draw a frame — the chevron folds, and so does the row, since a
  /// section is nothing to select — with its count, and `+` at its end.
  Widget _section(
    BuildContext context,
    String label,
    int count, {
    required bool open,
    required VoidCallback onToggle,
    required void Function(Offset at)? onAdd,
  }) {
    var colors = context.colors;
    var type = context.type;
    return FwTreeRow(
      depth: 0,
      density: TreeRowDensity.roomy,
      open: open,
      onToggleFold: onToggle,
      onTap: onToggle,
      label: Row(
        spacing: FwSpacing.sm,
        children: [
          Text(label, style: type.sectionLabel),
          Text('$count', style: type.caption.copyWith(color: colors.mut2)),
        ],
      ),
      trailing: [
        if (onAdd != null)
          _addButton(
            context,
            'New ${label.toLowerCase().substring(0, label.length - 1)}',
            onAdd,
          ),
      ],
    );
  }

  Widget _paramRow(BuildContext context, SceneParamDecl p) {
    var aside = ParamAside(p.name);
    var readers = editor.readersOf(p.name).length;
    return _row(
      context,
      aside,
      icon: paramKindIcon(p.kind),
      name: p.name,
      trailing: readers == 0 ? '' : '· $readers',
      tooltip: '${paramKindLabel(p.kind)} · ${p.typeName}',
      onOpen: () => _openParam(p.name),
      menu: () => paramMenu(
        editor,
        p,
        onRename: () => setState(() => _renaming = aside),
        host: widget.tokens,
      ),
      rename: (wanted) => editor.renameParam(p.name, wanted),
    );
  }

  Widget _motionRow(BuildContext context, String name) {
    var aside = MotionAside(name);
    var m = editor.motions[name]!;
    var seconds = m.durationOf(m.timeline).inMilliseconds / 1000;
    return _row(
      context,
      aside,
      icon: Icons.play_arrow_outlined,
      name: name,
      trailing: '${seconds.toStringAsFixed(2)}s',
      tooltip: '${m.groups.length} groups · on ${m.sceneClassName}',
      onOpen: () => _open(name),
      menu: () => [
        MenuItem(
          'Rename',
          icon: Icons.edit_outlined,
          shortcut: 'double-click',
          onSelected: () => setState(() => _renaming = aside),
        ),
        const MenuDivider(),
        MenuItem(
          'Delete $name',
          icon: Icons.close,
          danger: true,
          onSelected: () => editor.removeMotion(name),
        ),
      ],
      rename: (wanted) => editor.renameMotion(name, wanted),
    );
  }

  void _open(String motion) {
    if (widget.onOpenMotion case var open?) {
      open(motion);
    } else {
      editor.activeMotion = motion;
    }
  }

  void _openParam(String name) {
    if (widget.onOpenParam case var open?) {
      open(name);
    } else {
      editor.openParam = name;
    }
  }

  Widget _row(
    BuildContext context,
    SceneAside aside, {
    int depth = 1,
    required IconData icon,
    required String name,
    required String trailing,
    SceneColor? swatch,
    required String tooltip,
    required VoidCallback onOpen,
    required List<MenuEntry> Function() menu,
    required void Function(String wanted) rename,
  }) {
    var colors = context.colors;
    var open = editor.drawer == aside;
    var renaming = _renaming == aside;
    return GestureDetector(
      onSecondaryTapDown: (d) =>
          showContextMenu(context, d.globalPosition, menu()),
      child: FwTreeRow(
        // Under the section's line, whose chevron is in the leading slot
        // the way a frame's is; the kind's icon takes that slot here.
        depth: depth,
        density: TreeRowDensity.roomy,
        selected: open,
        onTap: () {
          var now = DateTime.now();
          var again =
              _lastTap?.$1 == aside &&
              now.difference(_lastTap!.$2) < kDoubleTapTimeout;
          _lastTap = (aside, now);
          if (again) {
            setState(() => _renaming = aside);
            return;
          }
          onOpen();
        },
        leading: Icon(
          icon,
          size: FwIconSize.sm,
          color: open ? colors.accentDark : colors.mut,
        ),
        label: renaming
            ? InlineNameField(
                initial: name,
                dense: true,
                style: context.type.body,
                onCommit: (wanted) {
                  try {
                    rename(wanted);
                  } on ArgumentError catch (e) {
                    return '${e.message}';
                  }
                  setState(() => _renaming = null);
                  return null;
                },
                onCancel: () => setState(() => _renaming = null),
              )
            : Tooltip(
                message: tooltip,
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.body.copyWith(
                    color: open ? colors.accentDark : colors.ink,
                  ),
                ),
              ),
        trailing: [
          if (swatch != null)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: swatch.flutter,
                shape: BoxShape.circle,
                border: Border.all(color: colors.line),
              ),
            ),
          if (trailing.isNotEmpty)
            // Capped, not flexed: a flex would split the row with the name.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                trailing,
                overflow: TextOverflow.ellipsis,
                style: context.type.caption.copyWith(color: colors.mut2),
              ),
            ),
        ],
      ),
    );
  }

  void _addParamMenu(BuildContext context, Offset at) {
    showContextMenu(context, at, [
      const MenuHeader('New parameter'),
      for (var (kind, label, type) in paramKinds)
        MenuItem(
          label,
          shortcut: type,
          onSelected: () {
            var name = editor.freeParamName(kind.name);
            editor.addParam(name, kind);
            _openParam(name);
            setState(() {
              _paramsOpen = true;
              _renaming = ParamAside(name);
            });
          },
        ),
    ]);
  }
}
