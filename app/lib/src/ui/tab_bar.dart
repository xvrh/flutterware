import 'package:flutter/material.dart';
import '../utils.dart';

class DesktopTabBar extends StatelessWidget {
  final List<DesktopTab> tabs;

  const DesktopTabBar({
    Key? key,
    required this.tabs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var selectedIndex = context.router.selectedIndex(tabs.map((t) => t.url));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabIndicator(
                tabs[i],
                isSelected: selectedIndex == i,
              ),
          ],
        ),
        Container(
          color: AppColors.tabDivider,
          height: 1,
        ),
        RouterOutlet(
          {
            for (var tab in tabs) tab.url: (c) => tab.content,
          },
          onNotFound: (c) => tabs.first.url,
        ),
      ],
    );
  }
}

class DesktopTab {
  final String label;
  final String url;
  final Widget content;

  DesktopTab(this.url, this.label, this.content);
}

class _TabIndicator extends StatelessWidget {
  final DesktopTab config;
  final bool isSelected;

  const _TabIndicator(
    this.config, {
    Key? key,
    required this.isSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(config.label),
    );

    body = IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefaultTextStyle.merge(
            style: TextStyle(
              color: isSelected ? AppColors.primary : null,
              fontWeight: FontWeight.w500,
            ),
            child: body,
          ),
          Container(
            height: 3,
            color: isSelected ? AppColors.primary : Colors.transparent,
          ),
        ],
      ),
    );

    return InkWell(
      onTap: () {
        context.go(config.url);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: body,
      ),
    );
  }
}
