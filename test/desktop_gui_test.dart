import 'package:flutterware/src/desktop_gui.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Where the built GUI is, on all three platforms from whichever one you are on.
///
/// The pair matters more than either half since `trimWorkingCopy` arrived: the
/// first element is what a finished working copy *keeps* and everything beside
/// it inside `build/<platform>` is deleted. A product path that is wrong but
/// happens to exist would spare the wrong directory — so the literals are
/// pinned here rather than trusted, on platforms this machine never executes.
void main() {
  String noArch() => fail('only Linux asks for the architecture');

  ({String product, String executable, String binary}) on(
    String os, {
    String Function()? arch,
  }) {
    var (product, executable) = relativeProduct(os, linuxArch: arch ?? noArch);
    return (
      product: product,
      executable: executable,
      binary: p.join(product, executable),
    );
  }

  test('macOS keeps the bundle, and the executable is inside it', () {
    var mac = on('macos');

    expect(
      mac.product,
      p.join(
        'build',
        'macos',
        'Build',
        'Products',
        'Release',
        'Flutterware.app',
      ),
    );
    expect(
      mac.binary,
      p.join(
        'build',
        'macos',
        'Build',
        'Products',
        'Release',
        'Flutterware.app',
        'Contents',
        'MacOS',
        'Flutterware',
      ),
      reason: 'the path the launcher tested before the pair was split out',
    );
  });

  test('Windows keeps the Release directory, not the bare .exe', () {
    var windows = on('windows');

    expect(windows.product, p.join('build', 'windows', 'runner', 'Release'));
    expect(
      windows.binary,
      p.join('build', 'windows', 'runner', 'Release', 'Flutterware.exe'),
    );
  });

  test('Linux keeps the bundle, which carries lib/ and data/ beside app', () {
    var linux = on('linux', arch: () => 'arm64');

    expect(
      linux.product,
      p.join('build', 'linux', 'arm64', 'release', 'bundle'),
    );
    expect(
      linux.binary,
      p.join('build', 'linux', 'arm64', 'release', 'bundle', 'app'),
    );
  });

  test('only Linux pays for uname', () {
    var asked = 0;
    for (var os in ['macos', 'windows']) {
      relativeProduct(os, linuxArch: () => (asked++, 'x64').$2);
    }

    expect(asked, 0);
  });

  test('an unknown platform answers as the desktop we are on', () {
    // `Platform.operatingSystem` is also `ios`/`android`/`fuchsia`, and the
    // switch has always fallen through to macOS rather than throwing. Pinned
    // so that stays a decision rather than an accident.
    expect(on('fuchsia').product, on('macos').product);
  });
}
