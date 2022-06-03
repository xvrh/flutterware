

import 'package:flutter/material.dart';

import '../../ui.dart';

enum LineType { leaf, collapsed, expanded }

class MenuLine extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onExpand;
  final LineType type;
  final int depth;
  final Widget child;

  const MenuLine({
    Key? key,
    required this.selected,
    required this.onTap,
    this.onExpand,
    required this.type,
    required this.depth,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.selection : null,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 12.0 * depth),
            GestureDetector(
              onTap: onExpand,
              child: Icon(
                type == LineType.expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 17,
                color: type == LineType.leaf
                    ? Colors.transparent
                    : (selected ? Colors.white : Colors.black54),
              ),
            ),
            const SizedBox(width: 1),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: selected ? Colors.white : null),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}