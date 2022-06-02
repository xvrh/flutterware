import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/test_visualizer/ui/breadcrumb.dart';
import 'package:flutter_studio_app/src/utils/debug.dart';

void main() => runDebugApp(BreadcrumbExample());

class BreadcrumbExample extends StatelessWidget {
  const BreadcrumbExample({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Breadcrumb(
              children: [
                BreadcrumbItemWithMenu(
                  Text(
                    'iAqualink+',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  options: {
                    'FluidraPro': Text('Fluidra Pro'),
                  },
                  onTapOption: (option) {
                    print('Go to $option');
                  },
                ),
                BreadcrumbItemWithMenu(
                  Text('v0.1.0 (10/10/2021)'),
                  options: {
                    'v1.0.0': Text('v0.0.9'),
                    'v0.2.0': Text('v0.0.8'),
                    for (var i = 0; i < 50; i++) 'v0.0.$i': Text('v0.0.$i'),
                  },
                  onTapOption: (option) {
                    print('Go to $option');
                  },
                ),
                BreadcrumbItem(
                  Text('Home'),
                  onTap: () {},
                ),
                BreadcrumbItem(Text('Onboarding')),
                BreadcrumbItem.withIcon('Group', Icons.list),
                BreadcrumbItem.withIcon('Page 1', Icons.description_outlined),
              ],
            ),
            const SizedBox(height: 10),
            Breadcrumb(
              children: [
                BreadcrumbItemWithMenu(
                  Text(
                    'iAqualink+',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  options: {
                    'FluidraPro': Text('Fluidra Pro'),
                  },
                  onTapOption: (option) {
                    print('Go to $option');
                  },
                ),
                BreadcrumbItem(Text('v0.1.0 (10/10/2021)')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
