import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../shell/shell_controller.dart';
import '../utils/window_title.dart';
import 'tile_composer.dart';

/// Keeps the Dock tile showing whichever project the window is on.
///
/// The window title reaches the Window menu, Mission Control and the Dock's own
/// menu — useful, but none of them is what a user scans when picking between
/// three identical windows. The tile is, and so is ⌘-Tab, which follows the
/// same image.
///
/// Set, never unset. macOS has no "put my bundle icon back": once
/// `applicationIconImage` is assigned it holds until the process exits. So a
/// worktree with no face leaves whatever is already there rather than trying to
/// restore a default that cannot be restored — which also means the first
/// project to resolve wins the tile until another one does.
class DockIcon {
  DockIcon._(this._shell) {
    _shell.addListener(_onChanged);
    _onChanged();
  }

  /// Starts following [shell]. A no-op anywhere the tile does not exist.
  static void follow(ShellController shell) {
    if (kIsWeb || !Platform.isMacOS) return;
    DockIcon._(shell);
  }

  final ShellController _shell;

  /// The icon file the tile currently shows, so a rebuild that changed nothing
  /// does not recompose — the shell notifies for every panel update.
  String? _applied;

  var _busy = false;

  void _onChanged() {
    var face = _shell.selectedSession?.face;
    if (face == null || _busy) return;
    var path = face.file.path;
    if (path == _applied) return;
    _applied = path;
    _busy = true;
    // Fire-and-forget: nothing waits on the Dock, and a failure here must not
    // take a worktree open down with it.
    unawaited(
      _apply(
        face.file,
      ).catchError((_) => _applied = null).whenComplete(() => _busy = false),
    );
  }

  Future<void> _apply(File icon) async {
    var png = await TileComposer.compose(await icon.readAsBytes());
    if (png != null) await WindowTitle.setIcon(png);
  }

  void dispose() => _shell.removeListener(_onChanged);
}
