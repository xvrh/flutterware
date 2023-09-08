import 'package:flutterware_app/src/drawing/model/property_bag_parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:petitparser/reflection.dart';
import 'package:test/test.dart';

void main() {
  final grammar = PropertyBagGrammarDefinition().build();
  final parser = PropertyBagParserDefinition().build();

  test('linter', () {
    expect(linter(grammar), isEmpty);
    expect(linter(parser), isEmpty);
  });

  test('Parse simple', () {
    var code = '[theName] x=1 y=0 na="abc"';
    var result = parser.parse(code);
    expect(result is Success, true);
    expect(result.value, PropertyBag('theName', {'x': 1, 'y': 0, 'na': 'abc'}));
    expect(result.value.toString(), code);
  });

  test('Parse array', () {
    var code = '[theName] x=[1, 2, 3]';
    var result = parser.parse(code);
    expect(result is Success, true);
    expect(
        result.value,
        PropertyBag('theName', {
          'x': [1, 2, 3]
        }));
    expect(result.value.toString(), code);
  });

  test('Parse object', () {
    var code = '[theName] x={xx=2}';
    var result = parser.parse(code);
    expect(result is Success, true);
    expect(
        result.value,
        PropertyBag('theName', {
          'x': {'xx': 2}
        }));
    expect(result.value.toString(), code);
  });
}
