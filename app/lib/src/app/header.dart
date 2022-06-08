import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';
import '../ui.dart';
import 'ui/breadcrumb.dart';

class Header extends StatefulWidget {
  final String projectName;

  const Header(
    this.projectName, {
    Key? key,
  }) : super(key: key);

  @override
  State<Header> createState() => HeaderState();
}

class HeaderState extends State<Header> {
  Iterable<Widget> Function(BuildContext)? _itemsBuilder;

  @override
  Widget build(BuildContext context) {
    var itemsBuilder = _itemsBuilder;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        border: Border(
          bottom: BorderSide(color: AppColors.separator, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Breadcrumb(
          children: [
            BreadcrumbItem(
              Text(widget.projectName),
              onTap: () => context.router.go('/home'),
            ),
            if (itemsBuilder != null) ...itemsBuilder(context),
          ],
        ),
      ),
    );
  }

  void setItemsBuilder(Iterable<Widget> Function(BuildContext)? builder) {
    setState(() {
      _itemsBuilder = builder;
    });
  }
}
