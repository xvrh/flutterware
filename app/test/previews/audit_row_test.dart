import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';

/// The audit's verdict on one rendered entry — in particular that a failed
/// network fetch, which `flutter_test`'s 400-for-everything binding makes
/// permanent, does not count the entry broken. Two such false positives out
/// of ninety were measured as enough to stop a consumer reading the audit.
void main() {
  test('a network-only failure is not a broken preview', () {
    var row = const PreviewAuditRow(
      id: 'demo/a.dart#A.new',
      errors: [
        {
          'exception': 'HTTP request failed, statusCode: 400, https://…',
          'library': 'image resource service',
          'network': true,
        },
      ],
    );
    expect(row.ok, isTrue);
    expect(row.indicting, isEmpty);
  });

  test('a real error still is, and keeps only its own entries', () {
    var row = const PreviewAuditRow(
      id: 'demo/a.dart#A.new',
      errors: [
        {
          'exception': 'HTTP request failed, statusCode: 400, https://…',
          'library': 'image resource service',
          'network': true,
        },
        {
          'exception': 'A RenderFlex overflowed by 7.8 pixels.',
          'library': 'rendering library',
        },
      ],
    );
    expect(row.ok, isFalse);
    expect(row.indicting, hasLength(1));
    expect('${row.indicting.single['exception']}', contains('RenderFlex'));
  });

  test('a failure or compile error is never excused by the mark', () {
    expect(const PreviewAuditRow(id: 'a', failure: 'timed out').ok, isFalse);
    expect(const PreviewAuditRow(id: 'a', compileError: 'nope').ok, isFalse);
  });
}
