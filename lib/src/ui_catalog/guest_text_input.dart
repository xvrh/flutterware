import 'package:flutter/services.dart';

/// The guest's text input — what lets a demo's `TextField` receive typing.
///
/// The guest has no platform text input: the host is a few hundred lines of C
/// with nothing on the other end of `flutter/textinput`, so the platform
/// control's messages go into the void and no field could ever receive a
/// character. This control replaces it ([TextInput.setInputControl]) and
/// builds the editing state in Dart instead, from the key events the GUI
/// already forwards — each carrying the character the host's keyboard layout
/// resolved it to.
///
/// Only *insertion* lives here, because insertion is the one thing a platform
/// IME normally owns. Deletion, caret movement, selection and the editing
/// chords are the framework's own — `DefaultTextEditingShortcuts` handles
/// them on every desktop platform — and they work the moment the field has
/// focus, with or without this. What stays missing is composition: dead keys
/// and CJK input need a real IME, which means proxying the host's, which is
/// not built.
class GuestTextInput with TextInputControl {
  GuestTextInput._();

  static final instance = GuestTextInput._();

  TextInputClient? _client;
  TextInputConfiguration? _configuration;
  TextEditingValue _value = TextEditingValue.empty;
  var _listening = false;

  /// Replaces the platform control. Call once, before `runApp`.
  void install() {
    TextInput.setInputControl(this);
  }

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _client = client;
    _configuration = configuration;
    // On while attached, off otherwise: an unfocused catalog pays nothing per
    // key, and a demo's own key handling sees every key whenever no field has
    // focus.
    if (!_listening) {
      _listening = true;
      HardwareKeyboard.instance.addHandler(_handleKey);
    }
  }

  @override
  void detach(TextInputClient client) {
    // A client switch attaches the new client before the old one's connection
    // closes; only the current client's detach may tear down.
    if (_client != client) return;
    if (_listening) {
      _listening = false;
      HardwareKeyboard.instance.removeHandler(_handleKey);
    }
    _client = null;
    _configuration = null;
    _value = TextEditingValue.empty;
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    _configuration = configuration;
  }

  @override
  void setEditingState(TextEditingValue value) {
    _value = value;
  }

  bool _handleKey(KeyEvent event) {
    if (_client == null || event is KeyUpEvent) return false;
    var character = event.character;
    if (character == null || character.isEmpty) return false;
    // A chord is a command, not text, whichever letter names it.
    var keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) return false;
    if (character == '\r' || character == '\n') return _enter();
    // Everything else non-printing — backspace, escape, tab — is someone
    // else's key: the editing shortcuts', or focus traversal's.
    if (_isControl(character)) return false;
    _insert(character);
    return true;
  }

  static bool _isControl(String character) =>
      character.runes.every((r) => r < 0x20 || r == 0x7F);

  /// Splits the way a platform IME does: a newline into a multiline field,
  /// the configured action — submit, usually — for anything else.
  ///
  /// The insert half cannot be left to the field: `EditableText` receiving
  /// `TextInputAction.newline` inserts nothing, *because* it assumes the IME
  /// already did.
  bool _enter() {
    var client = _client;
    var configuration = _configuration;
    if (client == null || configuration == null) return false;
    if (configuration.inputType == TextInputType.multiline) {
      _insert('\n');
    } else {
      client.performAction(configuration.inputAction);
    }
    return true;
  }

  void _insert(String text) {
    var selection = _value.selection;
    var start = selection.isValid ? selection.start : _value.text.length;
    var end = selection.isValid ? selection.end : _value.text.length;
    _value = TextEditingValue(
      text: _value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    TextInput.updateEditingValue(_value);
  }
}
