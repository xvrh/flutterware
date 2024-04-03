import 'package:flutter/material.dart';

class CollapseButton extends StatelessWidget {
  final bool isCollapsed;
  final void Function(bool) onChanged;

  const CollapseButton({
    super.key,
    required this.isCollapsed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!isCollapsed),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: isCollapsed ? Colors.blueAccent : Colors.black26,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(
              isCollapsed ? Icons.unfold_less : Icons.unfold_more,
              color: Colors.white,
              size: 14,
            ),
            Text(
              isCollapsed ? 'Collapsed' : 'Detailed',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
