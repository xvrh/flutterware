/// The flavor row above the plates.
///
/// Its own file because a chip stopped being a label. A flavor now arrives with
/// the evidence for it, and the row's job is to say which ones you can go and
/// read — a chip for a flavor nobody has generated has to be visibly different
/// from one for a flavor that is there, or the row invites a click into an
/// empty panel and calls it a bug.
library;

import 'package:flutter/material.dart';

import '../../ui/design/design.dart';
import '../../ui/theme.dart';
import '../model/scan.dart';

/// Every flavor the package has, with the default in front.
///
/// `main` leads because it is what the panel shows when the address names no
/// flavor, and a row that opened with `dev` would read as though `dev` were the
/// project's own default.
class FlavorChips extends StatelessWidget {
  const FlavorChips({super.key, required this.flavors, this.selected});

  final List<IconFlavor> flavors;

  /// The flavor the panel is showing, or null for the default.
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: FwSpacing.sm,
      runSpacing: FwSpacing.sm,
      children: [
        _Chip(label: 'main', selected: selected == null),
        for (var flavor in flavors)
          _Chip(
            label: flavor.name,
            selected: flavor.name == selected,
            // A flavor with nothing generated is still worth a chip — it is
            // how you find out the config exists at all — but it must not look
            // like one there is something to see behind.
            //
            // Said in words rather than drawn. The first attempt muted the
            // label and thinned the border, which in a screenshot of the row
            // was indistinguishable from the chip beside it; a suffix survives
            // being small, being greyscale, and not being hovered.
            note: flavor.isUnbuilt ? 'not generated' : null,
            hint: flavorHint(flavor),
          ),
      ],
    );
  }
}

/// What is behind a flavor, for the chip's tooltip.
///
/// Only ever says something when the answer is incomplete. A flavor generated
/// for both platforms needs no explaining, and a tooltip on every chip trains
/// people to ignore the ones that matter.
String? flavorHint(IconFlavor flavor) {
  if (flavor.isUnbuilt) {
    return 'flutter_launcher_icons-${flavor.name}.yaml exists, but nothing has '
        'been generated for it yet.';
  }
  var missing = [
    if (!flavor.has(IconFlavorSource.androidSourceSet))
      'no android/app/src/${flavor.name}/',
    if (!flavor.has(IconFlavorSource.iosCatalog))
      'no AppIcon-${flavor.name}.appiconset',
  ];
  if (missing.isEmpty) return null;
  return 'Generated for one platform only — ${missing.join(' and ')}.';
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    this.note,
    this.hint,
  });

  final String label;
  final bool selected;

  /// A muted qualifier after the name, for a chip with nothing behind it.
  final String? note;

  final String? hint;

  @override
  Widget build(BuildContext context) {
    var chip = _build(context);
    return hint == null ? chip : Tooltip(message: hint!, child: chip);
  }

  Widget _build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.panel2,
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(color: selected ? colors.accent : colors.line),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label),
            if (note != null)
              TextSpan(
                text: '  ·  $note',
                style: TextStyle(color: colors.mut),
              ),
          ],
        ),
        style: context.type.caption,
      ),
    );
  }
}
