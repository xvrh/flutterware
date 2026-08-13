import 'dart:io';

import 'package:flutterware/src/constants.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The version is written in three places and only one of them is checked by
/// anything else.
///
/// `pubspec.yaml` is what pub publishes and `app/pubspec.yaml` has to match it
/// (the comment in the root pubspec says so, and nothing enforced it either).
/// [flutterwareVersion] is the third, and it is the one a human reads: it is
/// what `fw --version` prints and what the MCP handshake announces. A constant
/// that has drifted from the package it names is worse than no version at all,
/// because it is believed.
void main() {
  String versionIn(String pubspec) {
    var file = File(p.join(Directory.current.path, pubspec));
    var match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(file.readAsStringSync());
    if (match == null) fail('no version: line in $pubspec');
    return match.group(1)!;
  }

  test('the constant, the package and the app agree', () {
    expect(
      flutterwareVersion,
      versionIn('pubspec.yaml'),
      reason:
          'flutterwareVersion in lib/src/constants.dart is not the published '
          'version — `fw --version` would name a release this is not.',
    );
    // Up to the `+`: `flutterware_app` is a Flutter application, so its version
    // carries a build number the published package has no equivalent of. What
    // has to agree is the release the two describe.
    expect(
      versionIn(p.join('app', 'pubspec.yaml')).split('+').first,
      versionIn('pubspec.yaml'),
      reason: 'app/pubspec.yaml and pubspec.yaml must move together',
    );
  });
}
