import 'package:flutter/widgets.dart';
import 'extract_text.dart';

abstract class TranslationTracker {
  String call(String key, String translation);
}

class NormalTranslationTracker implements TranslationTracker {
  final _accessedKeys = <String, List<String>>{};

  @override
  String call(String key, String translation) {
    var keys = _accessedKeys[translation] ??= [];
    if (!keys.contains(key)) {
      keys.add(key);
    }
    return translation;
  }
}

const _zeroWidthSpaceCharacter = '\u200B';

class DisambiguateTranslationTracker implements TranslationTracker {
  final NormalTranslationTracker tracker;

  DisambiguateTranslationTracker(this.tracker);

  @override
  String call(String key, String translation) {
    var keys = tracker._accessedKeys[translation];
    if (keys != null && keys.length > 1) {
      var index = keys.indexOf(key);
      return '${_zeroWidthSpaceCharacter * index}$translation';
    }
    return translation;
  }

  MapEntry<String, String>? matchKey(Element candidate) {
    if (tracker._accessedKeys.isEmpty) return null;

    var text = textFromElement(candidate);

    if (text != null) {
      int? index;
      if (text.startsWith(_zeroWidthSpaceCharacter)) {
        index = text.indexOf(RegExp('[^$_zeroWidthSpaceCharacter]'));
        text = removeLeadingSpace(text);
      }
      var keys = tracker._accessedKeys[text];
      if (keys != null) {
        if (index != null && keys.length > index) {
          var key = keys[index];
          return MapEntry(key, text);
        } else {
          return MapEntry(keys.first, text);
        }
      }
    }
    return null;
  }

  static final _leadingSpaceExtractor = RegExp('^[$_zeroWidthSpaceCharacter]*');
  static String removeLeadingSpace(String input) {
    return input.replaceFirst(_leadingSpaceExtractor, '');
  }
}
