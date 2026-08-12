import 'dart:io';

import 'package:crypto/crypto.dart';

import '../launcher_icon/model/role.dart';

/// Whether a launcher icon is still the one `flutter create` wrote.
///
/// **A project whose icon is the Flutter default cannot be told apart from any
/// other**, which is the whole thing project identity exists to fix. Three
/// untouched checkouts would be three windows showing the same blue bird, so
/// the honest answer for such a project is that it has no face yet.
///
/// Hashes rather than a heuristic, because the question is literally "is this
/// byte-for-byte the file the template ships". They go stale when Flutter
/// changes its template; the failure when they do is that an untouched project
/// looks like it has an icon, which is the behaviour from before any of this —
/// not a crash. `project_face_test.dart` says so where it will be read.
const stockIconHashes = {
  '7b0546f328068d8701df0cb849f6f1106edab1e8', // ios, 1024
  '6ae2aa59ecf8ab9341dbaaf8cc6b4a0bebbd487f', // macos, 1024
  'dd0452802ca0cd6c81b9b5982aeb56b051b73829', // android, xxxhdpi
  'b3fc122b12b47f9925deaf8158a8e630b610d622', // web, 512
};

bool isStockIcon(File file) {
  try {
    return stockIconHashes.contains(
      sha1.convert(file.readAsBytesSync()).toString(),
    );
  } on IOException {
    return false;
  }
}

/// Roles worth reading a project's face from, best first.
///
/// Ordered by how large the art tends to be, not by platform importance: macOS
/// and iOS ship 1024px, web 512px, Android's densest mipmap is usually 192px.
/// `windows.ico` is deliberately absent — it is the one role whose file Flutter
/// cannot decode.
const faceRoles = [
  IconRole.macosApp,
  IconRole.iosApp,
  IconRole.webIcon,
  IconRole.androidLegacy,
];

/// Directories whose presence makes a package something you could launch.
const platformDirectories = [
  'android',
  'ios',
  'macos',
  'web',
  'windows',
  'linux',
];
