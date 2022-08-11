
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
  var multiplicator = 1;
  if (expression is PrefixExpression) {
    multiplicator = expression.operator.toString() == '-' ? -1 : 1;
    expression = expression.operand;
  }

  double value;
  if (expression is DoubleLiteral) {
    value = expression.value;
  } else if (expression is IntegerLiteral) {
    value = expression.value!.toDouble();
  } else {
    throw UnsupportedError(
        'Expression is not a valid double literal (${expression.runtimeType})');
  }
  return value * multiplicator;
}

String commentValue(String rawComment) {
  return CharMatcher.charSet('/').trimLeadingFrom(rawComment).trim();
}