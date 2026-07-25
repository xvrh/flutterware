import 'tone.dart';

/// A plugin's whole state reduced to one line.
///
/// This is what the sidebar row, the worktree switcher, `fw status` and an
/// agent all read. It is deliberately tiny: a tone and a short human message.
class Status {
  const Status(this.tone, this.message);

  const Status.neutral(String message) : this(Tone.neutral, message);
  const Status.good(String message) : this(Tone.good, message);
  const Status.info(String message) : this(Tone.info, message);
  const Status.warn(String message) : this(Tone.warn, message);
  const Status.error(String message) : this(Tone.error, message);

  /// Nothing worth reporting — the row shows a label and no status text.
  static const none = Status(Tone.neutral, '');

  final Tone tone;
  final String message;

  bool get isEmpty => message.isEmpty;

  Map<String, Object?> toJson() => {'tone': tone.name, 'message': message};

  static Status fromJson(Map<String, Object?> json) =>
      Status(Tone.byName(json['tone']! as String), json['message']! as String);

  @override
  String toString() => message.isEmpty ? tone.name : '${tone.name}: $message';

  @override
  bool operator ==(Object other) =>
      other is Status && other.tone == tone && other.message == message;

  @override
  int get hashCode => Object.hash(tone, message);
}
