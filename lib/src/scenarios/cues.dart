/// What a scenario says to whatever is filming it.
///
/// A cue is an ordinary object the author already has — its own class, its own
/// fields — handed over by `s.film.emit(...)` and read back by an edit with a
/// pattern. There is no registry and no map: the class is the identity.
///
/// The stock cues below are the ones a stage that knows nothing about the app
/// can still act on. They are cues like any other; nothing privileges them.
library;

/// A cue that can also be written down.
///
/// Optional. Every cue reaches an edit as itself, because the edit runs in the
/// same process; implementing this only changes what a person reading the
/// timeline file sees.
abstract class ScenarioCueData {
  Map<String, Object?> toJson();
}

/// A caption for the stretch that follows — `s.title('Order a coffee')`.
///
/// Named for the package rather than for the word, because `Title` is a
/// Flutter widget and a scenario file imports both.
class ScenarioTitle implements ScenarioCueData {
  const ScenarioTitle(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'text': text};

  @override
  String toString() => 'title: $text';

  @override
  bool operator ==(Object other) =>
      other is ScenarioTitle && other.text == text;

  @override
  int get hashCode => text.hashCode;
}
