/// What a guest says about its keyboard.
///
/// Pure Dart, beside `knob.dart` and `axis.dart` and for the same reason: the
/// GUI, `fw` and MCP all read this, and none of them may pull in Flutter to do
/// it. The mode itself lives in `devices.dart` with [ScreenOrientation],
/// because a `PreviewCanvas` names it; the drawing lives in
/// `fake_keyboard.dart`.
library;

import '../devices.dart';

/// What the guest says about its keyboard: what it was told, what the app
/// asked for, and what is actually on screen.
///
/// The last two are separate facts and reporting only one of them is how a
/// control ends up lying. `requested` is the app's opinion — a field has
/// focus — and `height` is what the screen lost, which is zero whenever the
/// mode overrules the app.
class KeyboardState {
  const KeyboardState({
    this.mode = KeyboardMode.auto,
    this.requested = false,
    this.height = 0,
    this.deviceHeight = 0,
  });

  factory KeyboardState.fromJson(Map<String, Object?> json) => KeyboardState(
    mode: switch (json['mode']) {
      String name => keyboardModeById(name) ?? KeyboardMode.auto,
      _ => KeyboardMode.auto,
    },
    requested: json['requested'] == true,
    height: (json['height'] as num? ?? 0).toDouble(),
    deviceHeight: (json['deviceHeight'] as num? ?? 0).toDouble(),
  );

  final KeyboardMode mode;

  /// Whether the app has a field focused — the `show()` with no `hide()` after
  /// it. True regardless of [mode], because it is what the app said rather
  /// than what was done with it.
  final bool requested;

  /// What the screen actually lost, in logical pixels. Zero when the keyboard
  /// is down.
  final double height;

  /// What this device's keyboard measures when it is up — the number the host
  /// pushed. Non-zero even while the keyboard is down, which is what lets a
  /// host draw a control that says how much raising it would cost.
  final double deviceHeight;

  bool get up => height > 0;

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'requested': requested,
    'height': height,
    'deviceHeight': deviceHeight,
  };

  @override
  bool operator ==(Object other) =>
      other is KeyboardState &&
      other.mode == mode &&
      other.requested == requested &&
      other.height == height &&
      other.deviceHeight == deviceHeight;

  @override
  int get hashCode => Object.hash(mode, requested, height, deviceHeight);

  @override
  String toString() =>
      'KeyboardState(${mode.name}, ${up ? 'up (${height.round()})' : 'down'})';
}
