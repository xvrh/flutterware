import 'package:flutter/material.dart';
import '../../ui.dart';

class SideBar extends StatelessWidget {
  final Widget header;
  final Widget child;

  const SideBar({Key? key, required this.header, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarHeader(title: header),
        Expanded(child: child),
      ],
    );
  }
}

class SidebarHeader extends StatelessWidget {
  final Widget title;

  const SidebarHeader({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        border: Border(
          bottom: BorderSide(color: AppColors.separator, width: 1),
        ),
      ),
      padding: EdgeInsets.symmetric(vertical: 5, horizontal: 5),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontSize: 12,
        ),
        child: title,
      ),
    );
  }
}
