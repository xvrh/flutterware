import 'package:flutter/material.dart';

import 'design/design.dart';
import 'tappable.dart';
import 'theme.dart';

/// A bar over a list: a row of mode pills, an optional search box, and a count
/// of what survived.
///
/// The run cockpit's Logs tab drew this first and it is the shape a person
/// meets first, so it is the one the server panel's four lists now speak. It
/// is here rather than copied a fourth time because the fourth copy is where
/// they start disagreeing about whether the count is on the left.
///
/// The search box flexes and the count stands down below [_roomy]: these bars
/// sit over lists that are sometimes a whole panel and sometimes a 280px
/// column beside a detail.
class FwFilterBar extends StatelessWidget {
  const FwFilterBar({
    super.key,
    required this.pills,
    required this.count,
    this.hint,
    this.onSearch,
    this.searchController,
    this.trailing,
  });

  /// Label, whether it is the current one, what to do about it.
  final List<(String, bool, VoidCallback)> pills;

  /// What survived the filter — `'12 of 40'`, `'40 lines'`.
  final String count;

  final String? hint;

  /// Null draws no search box, and the pills take the whole bar.
  final ValueChanged<String>? onSearch;

  /// Passed to [FwSearchBox.controller] — see there for when a host needs one.
  final TextEditingController? searchController;

  /// Hard right, after the count — a clear button, a refresh.
  final Widget? trailing;

  static const _roomy = 520.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var roomy = constraints.maxWidth > _roomy;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.lg,
            vertical: FwSpacing.sm,
          ),
          child: Row(
            children: [
              for (var (label, selected, onTap) in pills)
                Padding(
                  padding: const EdgeInsets.only(right: FwSpacing.xs),
                  child: FwPill(label: label, selected: selected, onTap: onTap),
                ),
              if (onSearch case var it?) ...[
                const Gap(FwSpacing.sm),
                Expanded(
                  child: FwSearchBox(
                    hint: hint ?? 'Filter…',
                    onChanged: it,
                    controller: searchController,
                  ),
                ),
              ] else
                const Spacer(),
              if (roomy) ...[
                const Gap(FwSpacing.md),
                Text(
                  count,
                  style: context.type.micro.copyWith(
                    color: context.colors.mut3,
                  ),
                ),
              ],
              ?trailing,
            ],
          ),
        );
      },
    );
  }
}

/// One mode of a filter bar. Not a checkbox: the pills in a row are one
/// choice, and the selected one is filled rather than merely outlined.
class FwPill extends StatelessWidget {
  const FwPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : null,
          borderRadius: BorderRadius.circular(context.radii.pill),
          border: Border.all(
            color: selected ? colors.accentSoft2 : colors.line,
          ),
        ),
        child: Text(label, style: context.type.bodySmall),
      ),
    );
  }
}

/// A one-line filter box, sized to whatever it is given.
class FwSearchBox extends StatelessWidget {
  const FwSearchBox({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;

  /// Owned by the host when the typed text has to outlive this widget.
  ///
  /// Without one the text lives in the field's own `EditableText` state, which
  /// dies with the element — so a host that lifts its filter value up but
  /// leaves the box uncontrolled ends up showing an empty box over a list that
  /// is still filtered. Either both survive or neither does.
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.search, size: FwIconSize.sm, color: colors.mut2),
          const Gap(FwSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: context.type.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: context.type.bodySmall.copyWith(color: colors.mut2),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
