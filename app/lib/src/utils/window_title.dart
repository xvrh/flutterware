import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Names the desktop window after the project it was opened on.
///
/// A user runs the tool once per repository, so several windows of the same
/// application can be up at once with nothing to tell them apart. The bundle
/// name — shared by every instance — cannot carry that; the window title is
/// per-window, so it can.
///
/// It does not show in the window. `MainFlutterWindow.swift` hides the title
/// bar to reclaim that band for the shell, so what this feeds is Mission
/// Control, the Window menu, and the Dock icon's right-click menu. Making it
/// visible where a user actually looks is a separate question.
///
/// macOS only. Elsewhere [set] does nothing rather than throwing: a window
/// without a title is a cosmetic loss, and no caller has anything better to do
/// about it.
class WindowTitle {
  static const _channel = MethodChannel('flutterware/window');

  // dart2js compiles `dart:io` but `Platform` throws when touched, and the
  // shell's entry points are shared with the web exports.
  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  /// Titles the window `<project> — Flutterware`, for the project rooted at
  /// [projectPath].
  static Future<void> setForProject(String projectPath) {
    var name = p.basename(p.normalize(p.absolute(projectPath)));
    return set(name.isEmpty ? 'Flutterware' : '$name — Flutterware');
  }

  static Future<void> set(String title) async {
    if (!isSupported) return;
    // A missing implementation means an older host bundle — worth neither a
    // crash on startup nor a log line every launch.
    try {
      await _channel.invokeMethod<void>('setTitle', title);
    } on MissingPluginException {
      return;
    }
  }

  /// Replaces the window's Dock tile — and its ⌘-Tab entry, which follows the
  /// same image — with [png].
  ///
  /// Unlike the title, this one reaches the surfaces a user scans *first*. It
  /// also cannot be undone by us: macOS keeps the app's own icon until the
  /// process exits, so passing null is not a thing to offer. Whoever calls this
  /// owns what the window looks like for the rest of its life.
  static Future<void> setIcon(Uint8List png) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setIcon', png);
    } on MissingPluginException {
      return;
    }
  }
}
