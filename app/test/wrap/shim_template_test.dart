import 'package:flutterware_app/src/wrap/shim_template.dart';
import 'package:test/test.dart';

void main() {
  test('renderShim bakes in the real binary, kind, and wrap exe', () {
    final shim = renderShim(
      realBinary: '/sdk/bin/flutter',
      kind: 'flutter',
      wrapExe: '/cache/wrap',
    );
    expect(shim, startsWith('#!/usr/bin/env bash'));
    expect(shim, contains('REAL="/sdk/bin/flutter"'));
    expect(shim, contains('KIND="flutter"'));
    expect(shim, contains('WRAP_EXE="/cache/wrap"'));
    // The marker walk-up and classification must be present.
    expect(shim, contains('flutter_version'));
    expect(shim, contains('run|test'));
    expect(shim, contains('wrap-audit.log'));
  });
}
