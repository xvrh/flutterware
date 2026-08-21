import 'dart:io';

import 'package:crypto/crypto.dart';

import '../launcher_icon/model/role.dart';

/// Whether a launcher icon is still the one `flutter create` wrote.
///
/// Read by the `init` guess and by nothing else. It used to decide the face
/// itself, and that was a mistake with a cost: the list below is byte-exact
/// against template files somebody else maintains, it had been taken from one
/// vintage of them, and a real mobile app whose generator writes iOS and
/// Android icons and leaves `macos/` alone therefore got the Flutter logo in its
/// Dock — the template icon in `macos/` was from an older Flutter and hashed to
/// nothing here. Nothing on screen could explain it. The face is a declared path
/// now; see `ProjectIdentity.icon`.
///
/// What is left is a guess, and a guess can be wrong out loud: see [guessFace]
/// for why staleness is affordable there and was not here.
///
/// Hashes rather than a heuristic, because the question is literally "is this
/// byte-for-byte a file the template ships". Several vintages of the same role
/// are expected in the set — Flutter rewrites this art from time to time, and an
/// entry is only ever additive.
const stockIconHashes = {
  '7b0546f328068d8701df0cb849f6f1106edab1e8', // ios, 1024
  '6ae2aa59ecf8ab9341dbaaf8cc6b4a0bebbd487f', // macos, 1024
  'dd0452802ca0cd6c81b9b5982aeb56b051b73829', // android, xxxhdpi
  'b3fc122b12b47f9925deaf8158a8e630b610d622', // web, 512
  // An older template, found in a project created years before the four above
  // were taken. It is the same picture; the file is not the same bytes.
  '4e5b0ce7d51339f2cff15749fe069d4a346eb515', // macos, 1024
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

/// Roles worth guessing a project's face from, best first.
///
/// Ordered by how large the art tends to be, not by platform importance: macOS
/// and iOS ship 1024px, web 512px, Android's densest mipmap is usually 192px.
/// `windows.ico` is deliberately absent — it is the one role whose file Flutter
/// cannot decode, so a guess naming it would scaffold a line that cannot work.
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
