import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  final Widget scenario;

  const DashboardScreen({
    Key? key,
    required this.scenario,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var tabs = ['scenario', 'qr'];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: context.router.selectedIndex(tabs) ?? 0,
            onDestinationSelected: (int index) {
              context.go(tabs[index]);
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.translate),
                label: Text('Scenario'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.qr_code),
                label: Text('QR'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: RouterOutlet(
              {
                'scenario': (_) => scenario,
              },
              onNotFound: (_) => 'scenario',
            ),
          )
        ],
      ),
    );
  }
}
