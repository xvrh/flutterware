
import 'package:analyzer/dart/ast/ast.dart';
import 'package:more/char_matcher.dart';

String numToCode(num value, {int maxDigits = 3}) {
  if (value is int) return value.toString();

  var string = value.toStringAsFixed(maxDigits);
  if (maxDigits > 0) {
    string = CharMatcher.charSet('0').trimTailingFrom(string);
    string = CharMatcher.charSet('.').trimTailingFrom(string);
  }
  return string;
}

double expressionToDouble(Expression expression) {
  if (expression is DoubleLiteral) {
    return expression.value;
  } else if (expression is IntegerLiteral) {
    return expression.value!.toDouble();
  }
  throw UnsupportedError('Expression is not a valid double literal (${expression.runtimeType})');
}

String commentValue(String rawComment) {
  return CharMatcher.charSet('/').trimLeadingFrom(rawComment).trim();
}