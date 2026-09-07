import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';

import '../../ui/action_button.dart';
import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../tokens_library.dart';
import 'inline_name.dart';
import 'tokens_host.dart';

/// One library, open in the drawer under the canvas, for what is the
/// library's rather than any token's: its modes.
///
/// A mode is one set of values behind the same references — `dark`,
/// `contrast` — and it exists here by name before any token differs in it,
/// so adding one is a name, not a value. Each row says how many tokens
/// differ in it; the canvas's mode picker shows the artboard in it. Then
/// the tokens the library declares, each a step to its pane.
class SceneLibraryPane extends StatefulWidget {
  const SceneLibraryPane(
    this.editor,
    this.path, {
    super.key,
    this.host,
    this.onOpenToken,
  });

  final SceneEditor editor;
  final String path;
  final SceneTokensHost? host;
  final ValueChanged<String>? onOpenToken;

  @override
  State<SceneLibraryPane> createState() => _SceneLibraryPaneState();
}

class _SceneLibraryPaneState extends State<SceneLibraryPane> {
  /// The mode being renamed, or `''` for the new one being named.
  String? _naming;

  /// The last row clicked and when: a second click within the double-tap
  /// window renames. Timed by hand rather than by a double-tap recognizer,
  /// which would hold every single click back for the whole window.
  (String, DateTime)? _lastTap;

  @override
  Widget build(BuildContext context) {
    var library = widget.host?.libraryAt(widget.path);
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    if (library == null) {
      return Container(
        key: ValueKey('pane:library:${widget.path}'),
        color: colors.panel,
        padding: const EdgeInsets.all(FwSpacing.lg),
        alignment: Alignment.topLeft,
        child: Text("Not one of the group's libraries.", style: caption),
      );
    }
    return AnimatedBuilder(
      animation: library.listenable,
      builder: (context, _) => Container(
        key: ValueKey('pane:library:${widget.path}'),
        color: colors.panel,
        alignment: Alignment.topLeft,
        // The drawer is a band; an import's refusals can outgrow it.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FwSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: FwSpacing.xxl,
            children: [
              SizedBox(width: 360, child: _modes(context, library, caption)),
              Expanded(child: _tokens(context, library, caption)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modes(
    BuildContext context,
    TokensLibrary library,
    TextStyle caption,
  ) {
    var colors = context.colors;
    var editor = widget.editor;
    var modes = library.modes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text('Modes', style: caption),
        ),
        Text(
          'One set of values behind the same references. A token shows its '
          'default in a mode until it is given a value there.',
          style: context.type.micro.copyWith(color: colors.mut2),
        ),
        const SizedBox(height: FwSpacing.sm),
        _modeRow(
          context,
          library,
          null,
          label: 'default',
          facts:
              '${library.tokens.length} '
              '${library.tokens.length == 1 ? 'token' : 'tokens'}',
        ),
        for (var mode in modes)
          _modeRow(
            context,
            library,
            mode,
            label: mode,
            facts: switch (library.differingIn(mode)) {
              0 => 'same as default everywhere',
              1 => '1 token differs',
              var n => '$n tokens differ',
            },
          ),
        if (_naming == '')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
            child: InlineNameField(
              initial: '',
              dense: true,
              style: context.type.body,
              onCommit: (wanted) {
                try {
                  library.addMode(wanted);
                } on ArgumentError catch (e) {
                  return '${e.message}';
                }
                setState(() => _naming = null);
                editor.tokenMode = wanted.trim();
                return null;
              },
              onCancel: () => setState(() => _naming = null),
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Tappable(
              key: const ValueKey('library:add-mode'),
              onTap: () => setState(() => _naming = ''),
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FwSpacing.xs,
                  vertical: FwSpacing.xxs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: FwSpacing.xs,
                  children: [
                    Icon(Icons.add, size: FwIconSize.sm, color: colors.accent),
                    Text(
                      'Add mode',
                      style: context.type.body.copyWith(color: colors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// One mode: its name (double-click renames), what differs in it, and a
  /// check when the canvas shows it — click to show it. The default is a
  /// row too, so the artboard can be put back.
  Widget _modeRow(
    BuildContext context,
    TokensLibrary library,
    String? mode, {
    required String label,
    required String facts,
  }) {
    var colors = context.colors;
    var editor = widget.editor;
    var shown = editor.tokenMode == mode;
    var renaming = mode != null && _naming == mode;
    return GestureDetector(
      onSecondaryTapDown: mode == null
          ? null
          : (d) => showContextMenu(context, d.globalPosition, [
              MenuItem(
                'Rename',
                icon: Icons.edit_outlined,
                shortcut: 'double-click',
                onSelected: () => setState(() => _naming = mode),
              ),
              const MenuDivider(),
              MenuItem(
                'Delete $mode',
                icon: Icons.delete_outline,
                danger: true,
                onSelected: () => library.deleteMode(mode),
              ),
            ]),
      child: Tappable(
        key: ValueKey('library:mode:${mode ?? 'default'}'),
        onTap: () {
          var now = DateTime.now();
          var again =
              mode != null &&
              _lastTap?.$1 == mode &&
              now.difference(_lastTap!.$2) < kDoubleTapTimeout;
          _lastTap = (mode ?? '', now);
          if (again) {
            setState(() => _naming = mode);
            return;
          }
          editor.tokenMode = mode;
        },
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.xs,
            vertical: FwSpacing.xxs,
          ),
          child: Row(
            spacing: FwSpacing.sm,
            children: [
              Icon(
                shown ? Icons.visibility : Icons.visibility_outlined,
                size: FwIconSize.sm,
                color: shown ? colors.accentDark : colors.mut3,
              ),
              Expanded(
                child: renaming
                    ? InlineNameField(
                        initial: mode,
                        dense: true,
                        style: context.type.body,
                        onCommit: (wanted) {
                          try {
                            library.renameMode(mode, wanted);
                          } on ArgumentError catch (e) {
                            return '${e.message}';
                          }
                          if (shown) editor.tokenMode = wanted.trim();
                          setState(() => _naming = null);
                          return null;
                        },
                        onCancel: () => setState(() => _naming = null),
                      )
                    : Text(
                        label,
                        style: context.type.body.copyWith(
                          color: shown ? colors.accentDark : colors.ink,
                        ),
                      ),
              ),
              Text(
                facts,
                style: context.type.caption.copyWith(color: colors.mut2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tokens(
    BuildContext context,
    TokensLibrary library,
    TextStyle caption,
  ) {
    var colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text(library.fileName, style: caption),
        ),
        if (library.tokens.isEmpty)
          Text(
            'No token yet — + on the library in the tree adds one.',
            style: context.type.micro.copyWith(color: colors.mut2),
          ),
        Wrap(
          spacing: FwSpacing.md,
          runSpacing: FwSpacing.xxs,
          children: [
            for (var t in library.tokens)
              Tappable(
                onTap: () =>
                    (widget.onOpenToken ?? (n) => widget.editor.openToken = n)(
                      t.name,
                    ),
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.xs,
                    vertical: FwSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: FwSpacing.xs,
                    children: [
                      Icon(
                        tokenIcon(t),
                        size: FwIconSize.sm,
                        color: colors.mut,
                      ),
                      Text(
                        t.name,
                        style: context.type.mono.copyWith(
                          color: colors.accentDark,
                        ),
                      ),
                      Text(
                        tokenValueLabel(t),
                        style: context.type.caption.copyWith(
                          color: colors.mut2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        ..._import(context, library, caption),
      ],
    );
  }

  /// The design file this library draws from: what the last import did,
  /// what it refused and what it left alone — and the door to the next.
  List<Widget> _import(
    BuildContext context,
    TokensLibrary library,
    TextStyle caption,
  ) {
    var colors = context.colors;
    var micro = context.type.micro.copyWith(color: colors.mut2);
    var note = library.importNote;
    return [
      Padding(
        padding: const EdgeInsets.only(top: FwSpacing.lg, bottom: FwSpacing.xs),
        child: Text('Design file', style: caption),
      ),
      if (note == null)
        Text(
          "Nothing imported yet. A design file's variables merge in by "
          'name: yours stay, theirs update.',
          style: micro,
        )
      else ...[
        Text(
          'Imported ${note.from} on ${note.when} — ${note.summary}.',
          key: const ValueKey('library:import-note'),
          style: context.type.body,
        ),
        if (note.notImported.isNotEmpty) ...[
          const SizedBox(height: FwSpacing.xs),
          Text('Not imported', style: caption),
          for (var line in note.notImported)
            Text(line, style: micro.copyWith(color: colors.warningText)),
        ],
        if (note.kept.isNotEmpty) ...[
          const SizedBox(height: FwSpacing.xs),
          Text(
            'Kept, not in the design file: ${note.kept.join(', ')}',
            style: micro,
          ),
        ],
      ],
      if (widget.host?.importInto case var importInto?)
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FwActionButton(
              label: note == null ? 'Import variables…' : 'Import again…',
              tooltip: "A design file's variables JSON, merged in by name",
              onPressed: () => importInto(library.path),
            ),
          ),
        ),
    ];
  }
}
