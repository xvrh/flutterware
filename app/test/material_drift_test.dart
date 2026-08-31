import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The studio is drawn from its own tokens, and stock Material is how that
/// erodes.
///
/// A bare Material control does not merely look different — it lands on
/// another design system's ramp: a `DropdownButton` sets its value in
/// `titleMedium`, a `border: OutlineInputBorder()` throws away the themed
/// radius and line colour the theme spelled out. Each one shipped is a form
/// column mixing two type ramps, which is exactly how the Render workbench
/// came to mix 11.5px and 16px labels in one pane.
///
/// A structural test rather than a lint because no lint spells this, and
/// because each rule has a named replacement: the picker is `FwPicker`
/// (`lib/src/ui/picker.dart`), and the input border is already on the theme —
/// delete the override. See the design-system section in CLAUDE.md.
void main() {
  var root = Directory.current.path;
  var scanned = p.join(root, 'lib', 'src');

  List<File> sources() =>
      Directory(scanned)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  /// The file with full-line comments removed, so a doc comment may *name* a
  /// banned control while explaining why it is banned.
  String code(File file) => file
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the directory this guards is actually there', () {
    // Without this the whole file passes by scanning nothing, which is how a
    // guard dies silently when a path moves.
    expect(
      Directory(scanned).existsSync(),
      isTrue,
      reason: 'lib/src is missing — run this from app/',
    );
  });

  test('no Material dropdowns — the house picker is FwPicker', () {
    var dropdown = RegExp(r'\bDropdownButton|\bDropdownMenu');
    var offenders = [
      for (var file in sources())
        if (dropdown.firstMatch(code(file)) case var match?)
          '${p.relative(file.path, from: root)}: ${match.group(0)}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Use FwPicker (lib/src/ui/picker.dart) — a Material dropdown sets '
          'its value in titleMedium with Material 3 paddings, off the ramp '
          'everything beside it uses.',
    );
  });

  test('no private mono styles — the token is context.type.mono', () {
    // The fallback list is the drift signature: every hand-rolled mono spells
    // it out, and the copies had already drifted to 12, 12.5 and 13px when
    // this rule landed. FwTypography.mono exists precisely because this was
    // six copies once before. A deliberate deviation is a copyWith on the
    // token — size, height, colour — never a new TextStyle.
    var fallback = RegExp(r"'Menlo'");
    var offenders = [
      for (var file in sources())
        if (!file.path.endsWith(p.join('design', 'typography.dart')) &&
            fallback.hasMatch(code(file)))
          p.relative(file.path, from: root),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Machine data wears context.type.mono; deviate on one axis with '
          'copyWith rather than respelling the family.',
    );
  });

  test('no bare OutlineInputBorder() — the themed border already exists', () {
    var bare = RegExp(r'OutlineInputBorder\(\s*\)');
    var offenders = [
      for (var file in sources())
        if (bare.hasMatch(code(file))) p.relative(file.path, from: root),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Delete the border: override — buildAppTheme already sets the house '
          'radius and line colour on every input. A deliberate variant builds '
          'from tokens: OutlineInputBorder(borderRadius: '
          'BorderRadius.circular(context.radii.radius), borderSide: …).',
    );
  });
}
