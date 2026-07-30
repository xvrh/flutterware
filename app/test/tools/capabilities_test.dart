import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/session/capabilities.dart';

import '../../tool/generate_capabilities.dart' show capabilitiesPath;

/// The generated capability document has to be a consequence of the code, not
/// a description of it somebody remembers to update. This is what makes that
/// true: add an action, and the build fails until the document says so.
void main() {
  test('docs/capabilities.md matches this build', () {
    var file = File(capabilitiesPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Missing ${file.path}. Run: dart run tool/generate_capabilities.dart',
    );
    expect(
      file.readAsStringSync(),
      renderCapabilities(),
      reason:
          'The capability document is out of date. Regenerate it:\n'
          '  cd app && dart run tool/generate_capabilities.dart',
    );
  });
}
