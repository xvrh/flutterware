import 'package:flutter/material.dart';
import '../../utils.dart';

class Breadcrumb extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onBack;

  const Breadcrumb({
    super.key,
    required this.children,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 13, color: AppColors.breadcrumbLink),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onBack != null) ...[
            InkWell(
              onTap: onBack,
              child: SizedBox(
                height: 25,
                width: 25,
                child: Icon(
                  Icons.arrow_back,
                  color: AppColors.breadcrumbLink,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          for (var child in children) ...[
            child,
            if (child != children.last)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.breadcrumbLink,
                  size: 18,
                ),
              )
          ]
        ],
      ),
    );
  }
}

class BreadcrumbEntry extends StatelessWidget {
  static final overview =
      BreadcrumbEntry(title: Text('Project overview'), url: '/project/home');

  final Widget title;
  final String url;

  const BreadcrumbEntry({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        context.router.go(url);
      },
      child: title,
    );
  }
}
