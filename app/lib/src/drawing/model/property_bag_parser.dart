import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:petitparser/petitparser.dart';

import 'utils.dart';

class PropertyBag {
  final String name;
  final Map<String, dynamic> values;

  PropertyBag(this.name, this.values);

  static final _parser = PropertyBagParserDefinition().build();

  /// Parse a string of the format: name: key=value
  static PropertyBag parse(String input) {
    var result = _parser.parse(input);
    if (result is Failure) {
      throw Exception(result.message);
    }
    return result.value as PropertyBag;
  }

  @override
  bool operator ==(other) =>
      other is PropertyBag &&
      other.name == name &&
      const DeepCollectionEquality().equals(values, other.values);

  @override
  int get hashCode =>
      Object.hash(name, const DeepCollectionEquality().hash(values));

  @override
  String toString() => '[$name] ${_members(values)}';

  static String _members(Map<String, dynamic> objects) {
    return objects.entries.map((e) => '${e.key}=${_value(e.value)}').join(' ');
  }

  static String _value(object) {
    if (object is String) {
      return jsonEncode(object);
    } else if (object is num) {
      return numToCode(object);
    } else if (object is List) {
      return '[${object.map(_value).join(', ')}]';
    } else if (object is Map<String, dynamic>) {
      return '{${_members(object)}}';
    }
    throw Exception('${object.runtimeType} is not supported in PropertyBag');
  }
}

class PropertyBagGrammarDefinition extends GrammarDefinition {
  @override
  Parser start() => ref0(bag).end();

  Parser bag() => ref0(name) & ref0(members).star();

  Parser name() => ref1(token, '[') & ref0(identifier) & ref1(token, ']');

  Parser token(Object source, [String? name]) {
    if (source is String) {
      return source.toParser(message: 'Expected ${name ?? source}').trim();
    } else if (source is Parser) {
      ArgumentError.checkNotNull(name, 'name');
      return source.flatten('Expected $name').trim();
    } else {
      throw ArgumentError('Unknown token type: $source.');
    }
  }

  Parser array() =>
      ref1(token, '[') & ref0(elements).optional() & ref1(token, ']');
  Parser elements() => ref0(value).plusSeparated(ref1(token, ','));
  Parser members() => ref0(pair).plusSeparated(ref1(token, ' '));
  Parser object() =>
      ref1(token, '{') & ref0(members).optional() & ref1(token, '}');
  Parser pair() => ref0(identifier) & ref1(token, '=') & ref0(value);
  Parser value() => [
        ref0(stringToken),
        ref0(numberToken),
        ref0(object),
        ref0(array),
        ref0(trueToken),
        ref0(falseToken),
        ref0(nullToken),
      ].toChoiceParser(failureJoiner: selectFarthestJoined);
  Parser identifier() => ref0(identifierStart) & ref0(identifierPart).star();
  Parser identifierStart() => ref0(identifierStartNoDollar) | char(r'$');
  Parser identifierStartNoDollar() => ref0(letter) | char('_');
  Parser identifierPart() => ref0(identifierStart) | ref0(digit);

  Parser trueToken() => ref1(token, 'true');
  Parser falseToken() => ref1(token, 'false');
  Parser nullToken() => ref1(token, 'null');
  Parser stringToken() => ref2(token, ref0(stringPrimitive), 'string');
  Parser numberToken() => ref2(token, ref0(numberPrimitive), 'number');

  Parser characterPrimitive() =>
      ref0(characterNormal) | ref0(characterEscape) | ref0(characterUnicode);
  Parser characterNormal() => pattern(r'^"\');
  Parser characterEscape() => char(r'\') & pattern(jsonEscapeChars.keys.join());
  Parser characterUnicode() => string(r'\u') & pattern('0-9A-Fa-f').times(4);
  Parser numberPrimitive() =>
      char('-').optional() &
      char('0').or(digit().plus()) &
      char('.').seq(digit().plus()).optional() &
      pattern('eE')
          .seq(pattern('-+').optional())
          .seq(digit().plus())
          .optional();
  Parser stringPrimitive() =>
      char('"') & ref0(characterPrimitive).star() & char('"');
}

const Map<String, String> jsonEscapeChars = {
  r'\': r'\',
  '/': '/',
  '"': '"',
  'b': '\b',
  'f': '\f',
  'n': '\n',
  'r': '\r',
  't': '\t'
};

class PropertyBagParserDefinition extends PropertyBagGrammarDefinition {
  @override
  Parser bag() => super.bag().cast<List>().map((e) {
        final result = <String, dynamic>{};
        if (e[1] != null) {
          for (final element in e[1] as List) {
            var entry = (element as SeparatedList).elements[0]
                as MapEntry<String, dynamic>;
            var value = entry.value;
            if (value is SeparatedList) {
              value = value.elements;
            }
            result[entry.key] = value;
          }
        }

        return PropertyBag(e[0] as String, result);
      });

  @override
  Parser name() => super.name().cast<List>().map((e) => e[1] as String);

  @override
  Parser identifier() => super.identifier().flatten();

  @override
  Parser array() => super.array().cast<List>().map((each) => each[1] ?? []);

  @override
  Parser<Map<String, dynamic>> object() =>
      super.object().cast<List>().map((each) {
        final result = <String, dynamic>{};
        if (each[1] != null) {
          for (final element in (each[1] as SeparatedList).elements) {
            var entry = element as MapEntry<String, dynamic>;
            result[entry.key] = entry.value;
          }
        }
        return result;
      });

  @override
  Parser<MapEntry<String, dynamic>> pair() =>
      super.pair().cast<List>().map((each) {
        return MapEntry(each[0] as String, each[2]);
      });

  @override
  Parser trueToken() => super.trueToken().map((each) => true);
  @override
  Parser falseToken() => super.falseToken().map((each) => false);
  @override
  Parser nullToken() => super.nullToken().map((each) => null);
  @override
  Parser stringToken() => ref0(stringPrimitive).trim();
  @override
  Parser numberToken() =>
      super.numberToken().map((each) => num.parse(each as String));

  @override
  Parser stringPrimitive() => super
      .stringPrimitive()
      .cast<List>()
      .map((each) => (each[1] as List).join());
  @override
  Parser characterEscape() => super
      .characterEscape()
      .cast<List>()
      .map((each) => jsonEscapeChars[each[1] as String]);
  @override
  Parser characterUnicode() =>
      super.characterUnicode().cast<List>().map((each) {
        final charCode = int.parse((each[1] as Iterable).join(), radix: 16);
        return String.fromCharCode(charCode);
      });
}
